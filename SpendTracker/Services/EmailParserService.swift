import Foundation

// MARK: - Email Parser Service
// Accurately parses Indian bank transaction emails
// Tested with: Axis Bank, ICICI Bank, HDFC, SBI, Kotak
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

        // Must look like a transaction email
        let txnWords = ["debited","credited","transaction","inr","rs.","rs ","₹",
                        "used for","amount debited","amount credited","debit alert",
                        "credit alert","payment of","purchase of"]
        guard txnWords.contains(where: { b.contains($0) }) else { return nil }

        guard let amount = extractAmount(body: cleaned)    else { return nil }
        guard let type   = extractType(body: cleaned)      else { return nil }

        let merchant     = extractMerchant(body: cleaned, sender: sender)
        let bank         = smsParser.detectBank(sender: sender, body: cleaned)
        let accountLast4 = extractAccount(body: cleaned)
        let balance      = extractBalance(body: cleaned)
        let upiRef       = extractUPIRef(body: cleaned)
        let cardType     = smsParser.detectCardType(body: cleaned)
        let txnDate      = extractDate(body: cleaned) ?? date

        // Categorize using full email text + merchant + upi
        let category = CategoryService.shared.categorize(
            merchant: merchant,
            body:     b,
            type:     type,
            upiId:    upiRef
        )

        return Transaction(
            date:         txnDate,
            amount:       amount,
            type:         type,
            category:     category,
            merchant:     merchant,
            bankName:     bank,
            smsBody:      String(cleaned.prefix(500)),
            accountLast4: accountLast4,
            balance:      balance,
            upiId:        upiRef,
            cardType:     cardType
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Amount
    // ─────────────────────────────────────────────────────────
    private func extractAmount(body: String) -> Double? {
        let patterns = [
            // "INR 120.00" — Axis, ICICI
            #"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Rs. 500" or "Rs 500"
            #"[Rr][Ss]\.?\s+([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "₹500"
            #"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Amount Debited: 500" or "Amount: 500"
            #"[Aa]mount\s*(?:[Dd]ebited|[Cc]redited)?\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "transaction of INR 500"
            #"transaction\s+of\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let re    = try? NSRegularExpression(pattern: p),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let raw = String(body[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Type
    // ─────────────────────────────────────────────────────────
    private func extractType(body: String) -> TransactionType? {
        let b = body.lowercased()

        let debitPhrases = [
            "was debited", "has been debited", "debited from",
            "has been used for", "card.*used for", "purchase of",
            "payment of", "spent", "withdrawn", "withdrawal",
            "auto debit", "mandate", "emi deducted", "pos purchase"
        ]
        let creditPhrases = [
            "was credited", "has been credited", "credited to",
            "received", "refund", "cashback", "reversed",
            "salary credited", "amount credited"
        ]

        for p in debitPhrases {
            if b.range(of: p, options: .regularExpression) != nil { return .debit }
        }
        for p in creditPhrases {
            if b.range(of: p, options: .regularExpression) != nil { return .credit }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Merchant — key for correct categorization
    // ─────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {

        // ── Pattern 1: Axis Bank UPI format ──────────────────
        // "Transaction Info: UPI/P2A/517025145854/T DINAKARAN"
        if let re = try? NSRegularExpression(pattern: #"UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // ── Pattern 2: ICICI UPI format ───────────────────────
        // "Info: UPI-912372950586-Mr MUTHU"
        if let re = try? NSRegularExpression(pattern: #"UPI-\d{6,}-([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // ── Pattern 3: Transaction Info / Info label ──────────
        let labelPatterns = [
            #"[Tt]ransaction\s*[Ii]nfo\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"\bInfo\s*[:\-]\s*(?!UPI)([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Mm]erchant\s*(?:[Nn]ame)?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Dd]escription\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"[Rr]emarks?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
            #"(?:paid to|payment to|transferred to|at)\s+([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#,
        ]
        for p in labelPatterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let candidate = String(body[r])
                    .components(separatedBy: "\n").first ?? ""
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 2, !isGenericWord(trimmed) {
                    return beautify(trimmed)
                }
            }
        }

        // ── Pattern 4: VPA handle before @ ───────────────────
        if let vpa = smsParser.extractUPIId(body: body) {
            let name = vpa.components(separatedBy: "@").first ?? ""
            // Remove numeric-only UPI refs
            if name.count > 2, !name.allSatisfy({ $0.isNumber }) {
                return beautify(name)
            }
        }

        // ── Pattern 5: Well-known app names in body ───────────
        return smsParser.extractMerchant(body: body, sender: sender)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Account
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let patterns = [
            #"[Aa]/[Cc]\.?\s*(?:[Nn]o\.?)?\s*[Xx]{1,4}(\d{4})\b"#,
            #"[Cc]redit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            #"[Dd]ebit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            #"[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            #"[Aa]ccount\s+[Nn]umber\s*[:\-]\s*[Xx]{2}(\d{4})\b"#,
            #"[Xx]{2,}(\d{4})\b"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                return String(body[r])
            }
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
            #"[Bb]alance\s*(?:after)?\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let raw = String(body[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw) { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Date
    // ─────────────────────────────────────────────────────────
    private func extractDate(body: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let pairs: [(pattern: String, formats: [String])] = [
            // "19-03-26, 19:12:44" — Axis Bank short year
            (#"(\d{2}-\d{2}-\d{2}),?\s+\d{2}:\d{2}:\d{2}"#,
             ["dd-MM-yy"]),
            // "Mar 19, 2026" — ICICI
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})"#,
             ["MMM dd, yyyy"]),
            // "19-03-2026" or "19/03/2026"
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#,
             ["dd-MM-yyyy","dd/MM/yyyy"]),
            // "19 Mar 2026"
            (#"(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})"#,
             ["dd MMM yyyy"]),
            // "21-Mar-26" — ICICI SMS style
            (#"(\d{2}-[A-Za-z]{3}-\d{2})"#,
             ["dd-MMM-yy"]),
        ]

        for pair in pairs {
            if let re = try? NSRegularExpression(pattern: pair.pattern),
               let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r  = Range(m.range(at: 1), in: body) {
                let ds = String(body[r])
                for f in pair.formats {
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
        // Full VPA like merchant@upi
        if let vpa = smsParser.extractUPIId(body: body) { return vpa }
        // UPI ref number pattern
        if let re = try? NSRegularExpression(pattern: #"UPI[-/](\d{10,})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 0), in: body) {
            return String(body[r])
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────
    private func isGenericWord(_ s: String) -> Bool {
        let stop = ["your","the","this","that","bank","account","card","debit",
                    "credit","amount","balance","transaction","rupees","inr","rs",
                    "dear","customer","summary","alert","notification","info"]
        return stop.contains(s.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private func beautify(_ s: String) -> String {
        s.split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
         .joined(separator: " ")
    }

    private func cleanText(_ text: String) -> String {
        var t = text
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&nbsp;"," "),("&quot;","\""),("&#39;","'")].forEach {
            t = t.replacingOccurrences(of: $0.0, with: $0.1)
        }
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\t",   with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }
}
