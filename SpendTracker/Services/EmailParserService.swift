import Foundation

// MARK: - Email Parser Service
// Handles real Indian bank email formats
// Tested against: Axis Bank, ICICI Bank, HDFC, SBI, Kotak
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
        let txnWords = ["debited","credited","transaction","payment",
                        "inr","rs.","rs ","₹","used for","amount"]
        guard txnWords.contains(where: { b.contains($0) }) else { return nil }

        guard let amount = extractAmount(body: cleaned)            else { return nil }
        guard let type   = extractType(body: cleaned)              else { return nil }

        let merchant     = extractMerchant(body: cleaned, sender: sender)
        let bank         = smsParser.detectBank(sender: sender, body: cleaned)
        let accountLast4 = extractAccount(body: cleaned)
        let balance      = extractBalance(body: cleaned)
        let upiRef       = extractUPIRef(body: cleaned)
        let txnDate      = extractDate(body: cleaned) ?? date
        let category     = CategoryService.shared.categorize(
                               merchant: merchant,
                               body:     b,
                               type:     type,
                               upiId:    upiRef)

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
            upiId:        upiRef
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Amount
    // Handles:
    //   "INR 120.00 was debited"       ← Axis Bank
    //   "transaction of INR 25.00"     ← ICICI
    //   "Rs. 500 debited"              ← generic
    // ─────────────────────────────────────────────────────────
    private func extractAmount(body: String) -> Double? {
        let patterns = [
            // "INR 120.00" or "INR120.00"
            #"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Rs. 120" or "Rs 120"
            #"[Rr][Ss]\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "₹120"
            #"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Amount Debited: 120.00"
            #"[Aa]mount\s*[Dd]ebited\s*[:\-]?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Amount: INR 120"
            #"[Aa]mount\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for pattern in patterns {
            if let re    = try? NSRegularExpression(pattern: pattern),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let raw = String(body[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transaction Type
    // Handles:
    //   "INR 120.00 was debited"       ← Axis Bank
    //   "Credit Card XX9008 has been used" ← ICICI (= debit)
    //   "amount has been credited"     ← generic credit
    // ─────────────────────────────────────────────────────────
    private func extractType(body: String) -> TransactionType? {
        let b = body.lowercased()

        let debitWords = [
            "was debited", "has been debited", "debited from",
            "card.*used for", "has been used for", "purchase of",
            "payment of", "spent", "withdrawn", "withdrawal",
            "auto debit", "emi", "mandate"
        ]
        let creditWords = [
            "was credited", "has been credited", "credited to",
            "received", "refund", "cashback", "reversed",
            "salary credited"
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
    // MARK: Merchant
    // Handles:
    //   "Transaction Info: UPI/P2A/517025145854/T DINAKARAN"  ← Axis
    //   "Info: UPI-912372950586-Mr MUTHU"                     ← ICICI
    //   "Info: SWIGGY" / "Merchant: Amazon"                   ← generic
    // ─────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {

        // Pattern 1: Axis Bank "Transaction Info: UPI/P2A/<ref>/<NAME>"
        // e.g. UPI/P2A/517025145854/T DINAKARAN
        let axisUPI = #"UPI/P2A/\d+/([A-Za-z ]{2,40})"#
        if let re    = try? NSRegularExpression(pattern: axisUPI),
           let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            let name = String(body[range]).trimmingCharacters(in: .whitespaces)
            if name.count > 1 { return beautify(name) }
        }

        // Pattern 2: ICICI "Info: UPI-<ref>-<NAME>"
        // e.g. UPI-912372950586-Mr MUTHU
        let icicUPI = #"UPI[-/]\d+[-/]([A-Za-z ]{2,40})"#
        if let re    = try? NSRegularExpression(pattern: icicUPI),
           let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            let name = String(body[range]).trimmingCharacters(in: .whitespaces)
            if name.count > 1 { return beautify(name) }
        }

        // Pattern 3: "Transaction Info: <NAME>"
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

        // Pattern 4: UPI VPA before @ sign
        if let upi = smsParser.extractUPIId(body: body) {
            let name = upi.components(separatedBy: "@").first ?? ""
            if name.count > 2 { return beautify(name) }
        }

        // Pattern 5: Well-known merchants in body
        return smsParser.extractMerchant(body: body, sender: sender)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Account Number
    // Handles:
    //   "A/c no. XX5171"      ← Axis Bank
    //   "Credit Card XX9008"  ← ICICI
    //   "account ending 1234" ← generic
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let patterns = [
            // "A/c no. XX5171" or "A/c XX5171"
            #"[Aa]/[Cc]\.?\s*(?:no\.?)?\s*[Xx]{1,4}(\d{4})"#,
            // "Credit Card XX9008"
            #"[Cc]redit\s+[Cc]ard\s+[Xx]{2}(\d{4})"#,
            // "Card XX1234"
            #"[Cc]ard\s+[Xx]{2}(\d{4})"#,
            // "Account Number: XX5171"
            #"[Aa]ccount\s+[Nn]umber\s*[:\-]\s*[Xx]{2}(\d{4})"#,
            // Generic last 4
            #"[Xx]{2,}(\d{4})\b"#,
        ]
        for pattern in patterns {
            if let re    = try? NSRegularExpression(pattern: pattern),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                return String(body[range])
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Balance
    // Handles:
    //   "Available Credit Limit on your card is INR 1,88,219.86"  ← ICICI
    //   "Available balance: INR 10,000"                           ← generic
    // ─────────────────────────────────────────────────────────
    private func extractBalance(body: String) -> Double? {
        let patterns = [
            #"[Aa]vailable\s+[Cc]redit\s+[Ll]imit.*?INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Aa]vail(?:able)?\s+[Bb]al(?:ance)?\s*[:\-]?\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Bb]alance\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for pattern in patterns {
            if let re    = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let raw = String(body[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw) { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Date
    // Handles:
    //   "19-03-26, 19:12:44 IST"    ← Axis Bank (yy format)
    //   "Mar 19, 2026 at 01:11:35"  ← ICICI
    //   "19-03-2026"                ← generic
    // ─────────────────────────────────────────────────────────
    private func extractDate(body: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        // Try each pattern + format pair
        let pairs: [(pattern: String, formats: [String])] = [
            // Axis: "19-03-26, 19:12:44"
            (#"(\d{2}-\d{2}-\d{2}),?\s+\d{2}:\d{2}:\d{2}"#,
             ["dd-MM-yy", "dd-MM-yyyy"]),
            // ICICI: "Mar 19, 2026"
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})"#,
             ["MMM dd, yyyy"]),
            // Generic: "19-03-2026"
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#,
             ["dd-MM-yyyy", "dd/MM/yyyy"]),
            // Generic: "19 Mar 2026"
            (#"(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})"#,
             ["dd MMM yyyy"]),
        ]

        for pair in pairs {
            if let re    = try? NSRegularExpression(pattern: pair.pattern),
               let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let ds = String(body[range])
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
        // Extract VPA if present
        if let vpa = smsParser.extractUPIId(body: body) { return vpa }
        // Extract UPI ref number
        let pattern = #"UPI[-/](\d{10,})"#
        if let re    = try? NSRegularExpression(pattern: pattern),
           let match = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 0), in: body) {
            return String(body[range])
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────
    private func isGeneric(_ s: String) -> Bool {
        let stop = ["your","the","this","that","bank","account","card",
                    "debit","credit","amount","balance","transaction",
                    "rupees","inr","rs","dear","customer","summary"]
        return stop.contains(s.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private func beautify(_ s: String) -> String {
        s.split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
         .joined(separator: " ")
    }

    private func cleanText(_ text: String) -> String {
        var t = text
        let entities: [(String, String)] = [
            ("&amp;","&"), ("&lt;","<"), ("&gt;",">"),
            ("&nbsp;"," "), ("&quot;","\""), ("&#39;","'"),
        ]
        for (e, r) in entities { t = t.replacingOccurrences(of: e, with: r) }
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\t",   with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }
}
