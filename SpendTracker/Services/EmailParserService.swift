import Foundation

// MARK: - Email Parser Service
class EmailParserService {

    static let shared = EmailParserService()
    private init() {}
    private let smsParser = SMSParserService.shared

    // ─────────────────────────────────────────────────────────
    // MARK: Main Entry Point
    // ─────────────────────────────────────────────────────────
    func parse(emailBody: String, sender: String, date: Date) -> Transaction? {
        let cleaned      = cleanText(emailBody)
        let lines        = cleaned.components(separatedBy: "\n")
        let subject      = lines.first ?? ""
        let body         = lines.dropFirst().joined(separator: "\n")
        let subjectLower = subject.lowercased()
        let bodyLower    = body.lowercased()
        let fullLower    = cleaned.lowercased()

        // ── Step 1: HARD REJECT — Declined / Failed / Disabled ─
        // The screenshot shows "has been declined" in body
        // Also "Enable The Service" / "domestic online transactions is disabled"
        // are ICICI decline notifications — reject all of these
        let declineKeywords = [
            "has been declined",
            "was declined",
            "transaction declined",
            "payment declined",
            "declined on",
            "been declined",
            "not successful",
            "unsuccessful",
            "transaction failed",
            "payment failed",
            "could not be processed",
            "not processed",
            "insufficient funds",
            "insufficient balance",
            "rejected",
            "not authorised",
            "not authorized",
            "transaction blocked",
            "unable to process",
            // ICICI specific decline messages
            "domestic online transactions is disabled",
            "service for domestic online transactions",
            "enable the service",      // merchant was "Enable The Service" — this is a decline
            "enable the facility",
            "to complete the transaction successfully",
            "we regret to inform",
            "your transaction.*declined",  // regex handled below
        ]
        for kw in declineKeywords {
            if subjectLower.contains(kw) || bodyLower.contains(kw) {
                return nil // Declined — skip
            }
        }

        // Must have transaction indicators
        let txnWords = ["debited","credited","amount debited","amount credited",
                        "debit alert","credit alert"]
        // Must have BOTH a txn word AND an amount
        guard txnWords.contains(where: { fullLower.contains($0) }) else { return nil }
        guard fullLower.contains("inr") || fullLower.contains("rs.") ||
              fullLower.contains("rs ") || fullLower.contains("₹")   else { return nil }

        // ── Step 2: Type from subject + body ───────────────────
        guard let type = extractType(subject: subject, body: body) else { return nil }

        // ── Step 3: Amount from subject first, then body ───────
        guard let amount = extractAmount(subject: subject, body: cleaned) else { return nil }

        // ── Step 4: All other fields ───────────────────────────
        let merchant     = extractMerchant(body: cleaned, sender: sender)
        let bank         = smsParser.detectBank(sender: sender, body: cleaned)
        let accountLast4 = extractAccount(body: cleaned)
        let balance      = extractBalance(body: cleaned)
        let upiRef       = extractUPIRef(body: cleaned)
        let cardType     = smsParser.detectCardType(body: cleaned)
        let txnDate      = extractDate(body: cleaned) ?? date
        let category     = CategoryService.shared.categorize(
                               merchant: merchant, body: fullLower,
                               type: type, upiId: upiRef)

        return Transaction(
            date: txnDate, amount: amount, type: type,
            category: category, merchant: merchant, bankName: bank,
            smsBody: String(cleaned.prefix(500)), accountLast4: accountLast4,
            balance: balance, upiId: upiRef, cardType: cardType
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Type — Subject first, body confirmation
    // ─────────────────────────────────────────────────────────
    func extractType(subject: String, body: String) -> TransactionType? {
        let s = subject.lowercased()
        let b = body.lowercased()

        let subjectCreditKw = [
            "credited", "credit alert", "amount credited",
            "money received", "funds credited", "salary credited",
            "neft credit", "imps credit", "refund", "cashback",
            "account credited", "transfer received",
            "was credited",          // "INR 1.00 was credited to your A/c"
            "has been credited",
            // Axis Bank specific
            "credit transaction alert",
            "credit transaction",
            "a/c credited",
            "account has been credited",
        ]
        let subjectDebitKw  = [
            "debited", "debit alert", "amount debited",
            "transaction alert", "used for", "withdrawn",
            "neft debit", "imps debit", "auto debit", "emi", "pos",
            "was debited",           // "INR 1.00 was debited from your A/c no"
            "has been debited",
            // Axis Bank specific
            "debit transaction alert",
            "debit transaction",
            "a/c debited",
        ]

        var subjectType: TransactionType? = nil
        for kw in subjectCreditKw { if s.contains(kw) { subjectType = .credit; break } }
        if subjectType == nil {
            for kw in subjectDebitKw { if s.contains(kw) { subjectType = .debit; break } }
        }

        let bodyCreditKw = [
            "amount credited", "was credited", "has been credited",
            "credited to your", "money received", "funds credited",
            "neft cr", "imps cr", "upi cr", "salary credited",
            "deposited", "refund", "cashback", "reversed to",
            "transfer received", "received in your",
            // Axis Bank NEFT credit format:
            // "your A/c no. XX5171 has been credited with INR 2213.00"
            "has been credited with",
            "credited with inr",
            "credited with rs",
        ]
        let bodyDebitKw  = [
            "amount debited", "was debited", "has been debited",
            "debited from", "has been used for", "purchase of",
            "neft dr", "imps dr", "upi dr", "pos purchase",
            "charged to", "emi deducted", "deducted from",
            // Axis Bank debit format
            "has been debited with",
            "debited with inr",
        ]

        let bodyCredit = bodyCreditKw.contains { b.contains($0) }
        let bodyDebit  = bodyDebitKw.contains  { b.contains($0) }

        if let st = subjectType {
            if st == .credit && bodyCredit { return .credit }
            if st == .debit  && bodyDebit  { return .debit  }
            if bodyCredit { return .credit }
            if bodyDebit  { return .debit  }
            return st
        }
        if bodyCredit { return .credit }
        if bodyDebit  { return .debit  }
        if b.range(of: #"\bcr\b"#, options: .regularExpression) != nil { return .credit }
        if b.range(of: #"\bdr\b"#, options: .regularExpression) != nil { return .debit  }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Amount — subject first (most accurate)
    // ─────────────────────────────────────────────────────────
    private func extractAmount(subject: String, body: String) -> Double? {

        // Step 1: From subject — banks always put exact amount here
        // "INR 120.00 was debited" / "INR 1.00 was credited"
        let subjectPatterns = [
            #"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)\s+(?:was|has been|is)"#,
            #"(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in subjectPatterns {
            if let re    = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let match = re.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)),
               let range = Range(match.range(at: 1), in: subject) {
                let raw = String(subject[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }

        // Step 2: From body — remove balance/limit lines first
        let cleanedLines = body.components(separatedBy: "\n").filter { line in
            let l = line.lowercased()
            return !l.contains("available credit limit") &&
                   !l.contains("total credit limit")     &&
                   !l.contains("credit limit")           &&
                   !l.contains("available balance")      &&
                   !l.contains("avl bal")                &&
                   !l.contains("avail bal")              &&
                   !l.contains("balance after")          &&
                   !l.contains("closing balance")        &&
                   !l.contains("opening balance")        &&
                   !l.contains("outstanding")            &&
                   !l.contains("minimum due")            &&
                   !l.contains("total due")              &&
                   !l.contains("total amount due")       &&
                   !l.contains("minimum amount")
        }
        let cleaned = cleanedLines.joined(separator: "\n")

        let bodyPatterns: [(String, NSRegularExpression.Options)] = [
            (#"[Aa]mount\s*(?:[Dd]ebited|[Cc]redited)\s*[:\-]?\s*\n\s*(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, .dotMatchesLineSeparators),
            (#"[Aa]mount\s*[Dd]ebited\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            (#"[Aa]mount\s*[Cc]redited\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // Axis Bank NEFT format: "has been credited with INR 2213.00"
            (#"(?:credited|debited)\s+with\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            (#"transaction\s+of\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            (#"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)\s+(?:was|has been|is)"#, []),
            (#"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            (#"[Rr][Ss]\.?\s+([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            (#"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
        ]
        for (p, opts) in bodyPatterns {
            if let re    = try? NSRegularExpression(pattern: p, options: opts),
               let match = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range(at: 1), in: cleaned) {
                let raw = String(cleaned[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Merchant
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

        // Same-line Axis UPI: "UPI/P2A/517025145854/T DINAKARAN"
        if let re = try? NSRegularExpression(pattern: #"UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let full = String(body[r]).trimmingCharacters(in: .whitespaces)
            let name = full.components(separatedBy: "/").first ?? full
            if name.count > 1 { return beautify(name) }
        }

        // ICICI: "UPI-912372950586-Mr MUTHU"
        if let re = try? NSRegularExpression(pattern: #"UPI-\d{6,}-([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // ── Axis Bank NEFT format ─────────────────────────────
        // "by NEFT/BOFAH26073000408/NOKI"
        // Last segment after final / is the sender name
        if let re = try? NSRegularExpression(pattern: #"by\s+NEFT/[A-Z0-9]+/([A-Za-z][A-Za-z0-9 &._\-]{1,40})"#,
                                              options: .caseInsensitive),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // ── Axis Bank IMPS format ─────────────────────────────
        // "by IMPS/REF123456/SENDER NAME"
        if let re = try? NSRegularExpression(pattern: #"by\s+IMPS/[A-Z0-9]+/([A-Za-z][A-Za-z0-9 &._\-]{1,40})"#,
                                              options: .caseInsensitive),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }
        // Label patterns
        let labelPatterns = [
            #"[Mm]erchant\s*(?:[Nn]ame)?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Dd]escription\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Rr]emarks?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"(?:paid to|payment to|transferred to)\s+([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
        ]
        for p in labelPatterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let t = String(body[r]).trimmingCharacters(in: .whitespaces)
                if t.count > 2, !isGeneric(t) { return beautify(t) }
            }
        }
        // VPA before @
        if let vpa = smsParser.extractUPIId(body: body) {
            let name = vpa.components(separatedBy: "@").first ?? ""
            if name.count > 2, !name.allSatisfy({ $0.isNumber }) { return beautify(name) }
        }
        return smsParser.extractMerchant(body: body, sender: sender)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Account
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"[Aa]ccount\s*[Nn]umber\s*[:\-]?\s*\n\s*[Xx]{2}(\d{4})\b"#, .dotMatchesLineSeparators),
            (#"[Aa]/[Cc]\.?\s*(?:[Nn]o\.?)?\s*[Xx]{1,4}(\d{4})\b"#, .caseInsensitive),
            (#"[Cc]redit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#, .caseInsensitive),
            (#"[Dd]ebit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#,  .caseInsensitive),
            (#"[Cc]ard\s+[Xx]{2}(\d{4})\b"#,              .caseInsensitive),
            (#"[Xx]{2,}(\d{4})\b"#,                        .caseInsensitive),
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
            #"[Aa]vail(?:able)?\s+[Bb]al(?:ance)?\s*[:\-]?\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Bb]alance\s*(?:after)?\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive,.dotMatchesLineSeparators]),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let raw = String(body[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw) { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Date — with time
    // ─────────────────────────────────────────────────────────
    private func extractDate(body: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        // Patterns that include TIME — most accurate
        let withTimePairs: [(String, [String])] = [
            // "19-03-26, 19:12:44 IST" — Axis Bank short year
            (#"(\d{2}-\d{2}-\d{2}),?\s+(\d{2}:\d{2}:\d{2})\s*(?:IST|UTC)?"#,
             ["dd-MM-yy HH:mm:ss"]),
            // "16-03-2026 at 15:34:13 IST" — Axis Bank NEFT full year
            (#"(\d{2}-\d{2}-\d{4})\s+at\s+(\d{2}:\d{2}:\d{2})\s*(?:IST|UTC)?"#,
             ["dd-MM-yyyy HH:mm:ss"]),
            // "Mar 19, 2026 at 01:11:35" — ICICI
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})\s+at\s+(\d{2}:\d{2}:\d{2})"#,
             ["MMM dd, yyyy HH:mm:ss"]),
            // "19-03-2026 19:12" — generic with time
            (#"(\d{2}[-/]\d{2}[-/]\d{4})\s+(\d{2}:\d{2})"#,
             ["dd-MM-yyyy HH:mm","dd/MM/yyyy HH:mm"]),
        ]

        for (pattern, formats) in withTimePairs {
            if let re = try? NSRegularExpression(pattern: pattern),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) {
                // Combine date + time groups
                var dateStr = ""
                if let r1 = Range(m.range(at: 1), in: body),
                   let r2 = Range(m.range(at: 2), in: body) {
                    dateStr = "\(String(body[r1])) \(String(body[r2]))"
                } else if let r1 = Range(m.range(at: 0), in: body) {
                    dateStr = String(body[r1])
                }
                for f in formats {
                    fmt.dateFormat = f
                    if let d = fmt.date(from: dateStr.trimmingCharacters(in: .whitespaces)) {
                        return d
                    }
                }
            }
        }

        // Date only fallback
        let datePairs: [(String, [String])] = [
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})"#,   ["MMM dd, yyyy"]),
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#,            ["dd-MM-yyyy","dd/MM/yyyy"]),
            (#"(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})"#,     ["dd MMM yyyy"]),
            (#"(\d{2}-[A-Za-z]{3}-\d{2})"#,            ["dd-MMM-yy"]),
            (#"(\d{2}-\d{2}-\d{2})"#,                  ["dd-MM-yy"]),
        ]
        for (pattern, formats) in datePairs {
            if let re = try? NSRegularExpression(pattern: pattern),
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
        let stop = ["your","the","this","bank","account","card","debit","credit",
                    "amount","balance","transaction","inr","rs","dear","customer",
                    "alert","notification","info","summary","enable","service",
                    "facility","online","domestic"]
        return stop.contains(s.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private func beautify(_ s: String) -> String {
        s.split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
         .joined(separator: " ")
    }

    private func cleanText(_ text: String) -> String {
        var t = text
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&nbsp;"," "),
         ("&quot;","\""),("&#39;","'")].forEach {
            t = t.replacingOccurrences(of: $0.0, with: $0.1)
        }
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\t",   with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }
}
