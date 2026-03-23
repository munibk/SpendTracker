import Foundation

// MARK: - Email Parser Service
// V21 logic restored + declined filter + multi-line Axis format + cardType
class EmailParserService {

    static let shared = EmailParserService()
    private init() {}
    private let smsParser = SMSParserService.shared

    // ─────────────────────────────────────────────────────────
    // MARK: Main Entry Point
    // ─────────────────────────────────────────────────────────
    func parse(emailBody: String, sender: String, date: Date) -> Transaction? {
        let cleaned = cleanText(emailBody)
        let b       = cleaned.lowercased()

        // ── Reject DECLINED / FAILED transactions first ───────
        let declineWords = [
            "has been declined", "was declined", "transaction declined",
            "payment declined", "been declined", "not successful",
            "unsuccessful", "transaction failed", "payment failed",
            "domestic online transactions is disabled",
            "enable the service", "enable the facility",
            "insufficient funds", "not authorised", "not authorized",
            "could not be processed", "unable to process"
        ]
        for kw in declineWords {
            if b.contains(kw) { return nil }
        }

        // Must look like a transaction email
        let txnWords = ["debited","credited","transaction","payment",
                        "inr","rs.","rs ","₹","used for","amount"]
        guard txnWords.contains(where: { b.contains($0) }) else { return nil }

        guard let amount = extractAmount(body: cleaned) else { return nil }
        guard let type   = extractType(body: cleaned)   else { return nil }

        let merchant     = extractMerchant(body: cleaned, sender: sender)
        let bank         = smsParser.detectBank(sender: sender, body: cleaned)
        let accountLast4 = extractAccount(body: cleaned)
        let balance      = extractBalance(body: cleaned)
        let upiRef       = extractUPIRef(body: cleaned)
        let cardType     = smsParser.detectCardType(body: cleaned)
        let txnDate      = extractDate(body: cleaned) ?? date
        let category     = CategoryService.shared.categorize(
                               merchant: merchant, body: b,
                               type: type, upiId: upiRef)

        return Transaction(
            date: txnDate, amount: amount, type: type,
            category: category, merchant: merchant, bankName: bank,
            smsBody: String(cleaned.prefix(500)), accountLast4: accountLast4,
            balance: balance, upiId: upiRef, cardType: cardType
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Amount
    // ─────────────────────────────────────────────────────────
    private func extractAmount(body: String) -> Double? {
        // Remove balance/limit lines to avoid wrong match
        let cleanedLines = body.components(separatedBy: "\n").filter { line in
            let l = line.lowercased()
            return !l.contains("available credit limit") &&
                   !l.contains("total credit limit")     &&
                   !l.contains("credit limit")           &&
                   !l.contains("available balance")      &&
                   !l.contains("avl bal")                &&
                   !l.contains("avail bal")              &&
                   !l.contains("outstanding")            &&
                   !l.contains("minimum due")            &&
                   !l.contains("total due")
        }
        let b = cleanedLines.joined(separator: "\n")

        let patterns: [(String, NSRegularExpression.Options)] = [
            // Multi-line Axis: "Amount Credited:\nINR 1.00"
            (#"[Aa]mount\s*(?:[Dd]ebited|[Cc]redited)\s*[:\-]?\s*\n\s*(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, .dotMatchesLineSeparators),
            // "credited with INR 2213.00" — Axis NEFT
            (#"(?:credited|debited)\s+with\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "INR 120.00" or "INR120.00"
            (#"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "Rs. 120" or "Rs 120"
            (#"[Rr][Ss]\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "₹120"
            (#"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "Amount Debited: 120.00"
            (#"[Aa]mount\s*[Dd]ebited\s*[:\-]?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "Amount: INR 120"
            (#"[Aa]mount\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
        ]
        for (p, opts) in patterns {
            if let re    = try? NSRegularExpression(pattern: p, options: opts),
               let match = re.firstMatch(in: b, range: NSRange(b.startIndex..., in: b)),
               let range = Range(match.range(at: 1), in: b) {
                let raw = String(b[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transaction Type (V21 logic — simple and reliable)
    // ─────────────────────────────────────────────────────────
    private func extractType(body: String) -> TransactionType? {
        let b = body.lowercased()

        let debitWords = [
            "was debited", "has been debited", "debited from",
            "card.*used for", "has been used for", "purchase of",
            "payment of", "spent", "withdrawn", "withdrawal",
            "auto debit", "mandate",
            // Axis Bank NEFT debit
            "has been debited with"
        ]
        let creditWords = [
            "was credited", "has been credited", "credited to",
            "received", "refund", "cashback", "reversed",
            "salary credited",
            // Axis Bank credit formats
            "has been credited with",
            "amount credited",
            "credited with inr"
        ]

        for w in debitWords {
            if b.range(of: w, options: .regularExpression) != nil { return .debit }
        }
        for w in creditWords {
            if b.range(of: w, options: .regularExpression) != nil { return .credit }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Merchant (V21 logic + multi-line + NEFT)
    // ─────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {

        // Multi-line Axis: "Transaction Info:\nUPI/P2A/.../MAMTHA V/SBIN/UPI"
        let mlUPI = #"[Tt]ransaction\s*[Ii]nfo\s*[:\-]?\s*\n\s*UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#
        if let re = try? NSRegularExpression(pattern: mlUPI, options: .dotMatchesLineSeparators),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let full = String(body[r]).trimmingCharacters(in: .whitespaces)
            let name = full.components(separatedBy: "/").first ?? full
            if name.count > 1 { return beautify(name) }
        }

        // Axis same-line: "UPI/P2A/517025145854/T DINAKARAN"
        let axisUPI = #"UPI/P2[AM]/\d+/([A-Za-z ]{2,40})"#
        if let re    = try? NSRegularExpression(pattern: axisUPI),
           let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            let full = String(body[range]).trimmingCharacters(in: .whitespaces)
            let name = full.components(separatedBy: "/").first ?? full
            if name.count > 1 { return beautify(name) }
        }

        // ICICI: "UPI-912372950586-Mr MUTHU"
        let icicUPI = #"UPI[-/]\d+[-/]([A-Za-z ]{2,40})"#
        if let re    = try? NSRegularExpression(pattern: icicUPI),
           let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            let name = String(body[range]).trimmingCharacters(in: .whitespaces)
            if name.count > 1 { return beautify(name) }
        }

        // Axis NEFT: "by NEFT/BOFAH26073000408/NOKI"
        let neft = #"by\s+(?:NEFT|IMPS)/[A-Z0-9]+/([A-Za-z][A-Za-z0-9 &._\-]{1,40})"#
        if let re = try? NSRegularExpression(pattern: neft, options: .caseInsensitive),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // Label patterns (V21)
        let infoPatterns = [
            #"[Tt]ransaction\s*[Ii]nfo\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"\bInfo\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Mm]erchant\s*[Nn]ame\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Dd]escription\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Rr]emarks?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"(?:paid to|payment to|transferred to)\s+([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
        ]
        for pattern in infoPatterns {
            if let re    = try? NSRegularExpression(pattern: pattern),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let candidate = String(body[range])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: "\n").first ?? ""
                if candidate.count > 2 && !isGeneric(candidate) {
                    return beautify(candidate)
                }
            }
        }

        // ACH / bank transfer — "debited/credited ... by NAME"
        // e.g. "debited with INR 48377.00 ... by ACH-DR-TP ACH ICICI BANK-2"
        let byName = #"(?:debited|credited).{0,120}?\bby\s+([A-Za-z][A-Za-z0-9 &._\-]{2,50})(?=[.\n]|$)"#
        if let re = try? NSRegularExpression(pattern: byName, options: .caseInsensitive),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let candidate = String(body[r]).trimmingCharacters(in: .whitespaces)
            if candidate.count > 2, !isGeneric(candidate) { return beautify(candidate) }
        }

        // UPI VPA before @
        if let upi = smsParser.extractUPIId(body: body) {
            let name = upi.components(separatedBy: "@").first ?? ""
            if name.count > 2 { return beautify(name) }
        }

        return smsParser.extractMerchant(body: body, sender: sender)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Account
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let patterns: [(String, NSRegularExpression.Options)] = [
            // Multi-line: "Account Number:\nXX5171"
            (#"[Aa]ccount\s*[Nn]umber\s*[:\-]?\s*\n\s*[Xx]{2}(\d{4})\b"#, .dotMatchesLineSeparators),
            (#"[Aa]/[Cc]\.?\s*(?:no\.?)?\s*[Xx]{1,4}(\d{4})"#,            .caseInsensitive),
            (#"[Cc]redit\s+[Cc]ard\s+[Xx]{2}(\d{4})"#,                    .caseInsensitive),
            (#"[Cc]ard\s+[Xx]{2}(\d{4})"#,                                 .caseInsensitive),
            (#"[Xx]{2,}(\d{4})\b"#,                                         .caseInsensitive),
        ]
        for (p, opts) in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: opts),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) { return String(body[r]) }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Balance
    // ─────────────────────────────────────────────────────────
    private func extractBalance(body: String) -> Double? {
        let patterns = [
            #"[Aa]vailable\s+[Cc]redit\s+[Ll]imit.*?INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Aa]vail(?:able)?\s+[Bb]al(?:ance)?\s*[:\-]?\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Bb]alance\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .dotMatchesLineSeparators),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let raw = String(body[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw) { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Date (V21 + Axis NEFT full year)
    // ─────────────────────────────────────────────────────────
    private func extractDate(body: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let pairs: [(String, [String])] = [
            // "19-03-26, 19:12:44" — Axis short year
            (#"(\d{2}-\d{2}-\d{2}),?\s+\d{2}:\d{2}:\d{2}"#, ["dd-MM-yy"]),
            // "16-03-2026 at 15:34:13" — Axis NEFT full year
            (#"(\d{2}-\d{2}-\d{4})\s+at\s+\d{2}:\d{2}:\d{2}"#, ["dd-MM-yyyy"]),
            // "Mar 19, 2026 at 01:11:35" — ICICI
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})"#, ["MMM dd, yyyy"]),
            // "19-03-2026"
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#, ["dd-MM-yyyy","dd/MM/yyyy"]),
            // "19 Mar 2026"
            (#"(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})"#, ["dd MMM yyyy"]),
        ]
        for (p, formats) in pairs {
            if let re = try? NSRegularExpression(pattern: p),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let ds = String(body[r])
                for f in formats {
                    fmt.dateFormat = f
                    if let d = fmt.date(from: ds) { return d }
                }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: UPI Reference
    // ─────────────────────────────────────────────────────────
    private func extractUPIRef(body: String) -> String? {
        if let vpa = smsParser.extractUPIId(body: body) { return vpa }
        if let re  = try? NSRegularExpression(pattern: #"UPI[-/](\d{10,})"#),
           let m   = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r   = Range(m.range(at: 0), in: body) { return String(body[r]) }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────
    private func isGeneric(_ s: String) -> Bool {
        let stop = ["your","the","this","that","bank","account","card",
                    "debit","credit","amount","balance","transaction",
                    "rupees","inr","rs","dear","customer","summary",
                    "enable","service","facility","online","domestic"]
        return stop.contains(s.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private func beautify(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        // Strip trailing punctuation (e.g. "GROCERY." → "GROCERY", "NOKI." → "NOKI")
        while let last = t.last, ".,;:!?".contains(last) { t.removeLast() }
        return t.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
    }

    private func cleanText(_ text: String) -> String {
        var t = text
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&nbsp;"," "),
         ("&quot;","\""),("&#39;","'"),("&rsquo;","'"),("&ndash;","-")]
            .forEach { t = t.replacingOccurrences(of: $0.0, with: $0.1) }
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\t",   with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }
}
