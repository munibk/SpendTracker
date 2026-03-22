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

        // Split subject from body — subject is the first line
        let lines   = cleaned.components(separatedBy: "\n")
        let subject = lines.first ?? ""
        let body    = lines.dropFirst().joined(separator: "\n")

        // Must look like a transaction email
        let txnWords = ["debited","credited","transaction","inr","rs.","rs ","₹",
                        "used for","amount debited","amount credited","debit alert",
                        "credit alert","payment of","purchase of"]
        guard txnWords.contains(where: { b.contains($0) }) else { return nil }

        // Use subject + body for type detection (most accurate)
        guard let type = extractType(subject: subject, body: body) else { return nil }
        guard let amount = extractAmount(body: cleaned)             else { return nil }

        let merchant     = extractMerchant(body: cleaned, sender: sender)
        let bank         = smsParser.detectBank(sender: sender, body: cleaned)
        let accountLast4 = extractAccount(body: cleaned)
        let balance      = extractBalance(body: cleaned)
        let upiRef       = extractUPIRef(body: cleaned)
        let cardType     = smsParser.detectCardType(body: cleaned)
        let txnDate      = extractDate(body: cleaned) ?? date

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

        // ── Pre-process: remove balance/limit lines ────────────
        let cleanedLines = body.components(separatedBy: "\n").filter { line in
            let l = line.lowercased()
            return !l.contains("available credit limit") &&
                   !l.contains("available balance") &&
                   !l.contains("avl bal") &&
                   !l.contains("avail bal") &&
                   !l.contains("total credit limit") &&
                   !l.contains("credit limit") &&
                   !l.contains("balance after") &&
                   !l.contains("closing balance") &&
                   !l.contains("opening balance") &&
                   !l.contains("outstanding") &&
                   !l.contains("minimum due") &&
                   !l.contains("total due") &&
                   !l.contains("minimum amount due")
        }
        let cleaned = cleanedLines.joined(separator: "\n")

        // ── Pattern 1: Multi-line format (Axis Bank style) ─────
        // "Amount Debited:\nINR 120.00"
        // "Amount Credited:\nINR 1.00"
        let multiLinePattern = #"[Aa]mount\s*(?:[Dd]ebited|[Cc]redited)\s*[:\-]?\s*\n\s*(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#
        if let re    = try? NSRegularExpression(pattern: multiLinePattern, options: .dotMatchesLineSeparators),
           let match = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            let raw = String(cleaned[range]).replacingOccurrences(of: ",", with: "")
            if let v = Double(raw), v > 0 { return v }
        }

        // ── Pattern 2: Same line formats ──────────────────────
        let patterns = [
            // "Amount Debited: INR 120.00"
            #"[Aa]mount\s*[Dd]ebited\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Amount Credited: INR 1.00"
            #"[Aa]mount\s*[Cc]redited\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "INR 120.00 was debited/credited"
            #"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)\s+(?:was|has been|is)"#,
            // "transaction of INR 500"
            #"transaction\s+of\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "INR 120.00" — generic fallback (after balance lines removed)
            #"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Rs. 500"
            #"[Rr][Ss]\.?\s+([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "₹500"
            #"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "Amount: 500"
            #"[Aa]mount\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]

        for p in patterns {
            if let re    = try? NSRegularExpression(pattern: p),
               let match = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range(at: 1), in: cleaned) {
                let raw = String(cleaned[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Type — Subject first, body confirmation
    // Strategy:
    //   1. Check subject line — most reliable signal
    //   2. Confirm with body — prevents false positives
    //   3. Fallback to body-only if subject unclear
    // ─────────────────────────────────────────────────────────
    func extractType(subject: String, body: String) -> TransactionType? {
        let s = subject.lowercased()
        let b = body.lowercased()

        // ── Step 1: Subject-based detection ───────────────────
        // Banks always mention debit/credit clearly in subject
        let subjectCredit = [
            "credited", "credit alert", "amount credited",
            "money received", "funds credited", "salary credited",
            "neft credit", "imps credit", "upi credit",
            "transfer received", "refund", "cashback",
            "account credited"
        ]
        let subjectDebit = [
            "debited", "debit alert", "amount debited",
            "transaction alert", "payment", "purchase",
            "used for", "withdrawn", "withdrawal",
            "neft debit", "imps debit", "upi debit",
            "auto debit", "emi", "pos"
        ]

        var subjectType: TransactionType? = nil
        for kw in subjectCredit { if s.contains(kw) { subjectType = .credit; break } }
        if subjectType == nil {
            for kw in subjectDebit { if s.contains(kw) { subjectType = .debit; break } }
        }

        // ── Step 2: Body confirmation ──────────────────────────
        // Check if body agrees with subject signal
        let bodyCredit = [
            "amount credited", "was credited", "has been credited",
            "credited to your", "money received", "funds credited",
            "neft cr", "imps cr", "upi cr", "salary credited",
            "deposited", "refund", "cashback", "reversed to",
            "transfer received", "received in your"
        ]
        let bodyDebit = [
            "amount debited", "was debited", "has been debited",
            "debited from", "has been used for", "purchase of",
            "payment of", "withdrawn", "auto debit", "mandate",
            "neft dr", "imps dr", "upi dr", "pos purchase",
            "charged to", "emi deducted", "deducted from"
        ]

        let bodyConfirmsCredit = bodyCredit.contains { b.contains($0) }
        let bodyConfirmsDebit  = bodyDebit.contains  { b.contains($0) }

        // ── Step 3: Decision logic ─────────────────────────────
        if let st = subjectType {
            // Subject found — confirm with body
            if st == .credit && bodyConfirmsCredit { return .credit }
            if st == .debit  && bodyConfirmsDebit  { return .debit  }

            // Subject and body disagree — trust body (more detailed)
            if bodyConfirmsCredit { return .credit }
            if bodyConfirmsDebit  { return .debit  }

            // Body has no confirmation — trust subject alone
            return st
        }

        // ── Step 4: No subject signal — use body only ──────────
        if bodyConfirmsCredit { return .credit }
        if bodyConfirmsDebit  { return .debit  }

        // ── Step 5: CR/DR suffix fallback ─────────────────────
        if b.range(of: #"\bcr\b"#, options: .regularExpression) != nil { return .credit }
        if b.range(of: #"\bdr\b"#, options: .regularExpression) != nil { return .debit  }

        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Merchant — key for correct categorization
    // ─────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {

        // ── Pattern 1: Multi-line "Transaction Info:\nUPI/P2A/.../NAME" ─
        // Axis Bank format: Transaction Info:\nUPI/P2A/607854315875/MAMTHA V/SBIN/UPI
        let multiLineInfo = #"[Tt]ransaction\s*[Ii]nfo\s*[:\-]?\s*\n\s*UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#
        if let re = try? NSRegularExpression(pattern: multiLineInfo, options: .dotMatchesLineSeparators),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            // Name can be "MAMTHA V/SBIN/UPI" — take only part before next /
            let full = String(body[r]).trimmingCharacters(in: .whitespaces)
            let name = full.components(separatedBy: "/").first ?? full
            if name.count > 1 { return beautify(name) }
        }

        // ── Pattern 2: Same-line "Transaction Info: UPI/P2A/.../NAME" ──
        // Axis Bank same-line format
        if let re = try? NSRegularExpression(pattern: #"UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let full = String(body[r]).trimmingCharacters(in: .whitespaces)
            let name = full.components(separatedBy: "/").first ?? full
            if name.count > 1 { return beautify(name) }
        }

        // ── Pattern 3: ICICI "Info: UPI-912372950586-Mr MUTHU" ───────
        if let re = try? NSRegularExpression(pattern: #"UPI-\d{6,}-([A-Za-z][A-Za-z0-9 ]{1,40})"#),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let n = String(body[r]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // ── Pattern 4: Multi-line "Transaction Info:\nSOME TEXT" ─────
        let multiLineLabelPattern = #"[Tt]ransaction\s*[Ii]nfo\s*[:\-]?\s*\n\s*([A-Za-z][A-Za-z0-9 &._\-]{2,40})"#
        if let re = try? NSRegularExpression(pattern: multiLineLabelPattern, options: .dotMatchesLineSeparators),
           let m  = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r  = Range(m.range(at: 1), in: body) {
            let candidate = String(body[r]).trimmingCharacters(in: .whitespaces)
            if candidate.count > 2, !isGenericWord(candidate) {
                return beautify(candidate)
            }
        }

        // ── Pattern 5: Same-line label patterns ───────────────────────
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

        // ── Pattern 6: VPA handle before @ ────────────────────────────
        if let vpa = smsParser.extractUPIId(body: body) {
            let name = vpa.components(separatedBy: "@").first ?? ""
            if name.count > 2, !name.allSatisfy({ $0.isNumber }) {
                return beautify(name)
            }
        }

        return smsParser.extractMerchant(body: body, sender: sender)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Account
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let patterns = [
            // Multi-line: "Account Number:\nXX5171" — Axis Bank
            #"[Aa]ccount\s*[Nn]umber\s*[:\-]?\s*\n\s*[Xx]{2}(\d{4})\b"#,
            // Same-line: "A/c no. XX5171"
            #"[Aa]/[Cc]\.?\s*(?:[Nn]o\.?)?\s*[Xx]{1,4}(\d{4})\b"#,
            // "Credit Card XX9008"
            #"[Cc]redit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            // "Debit Card XX1234"
            #"[Dd]ebit\s+[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            // "Card XX1234"
            #"[Cc]ard\s+[Xx]{2}(\d{4})\b"#,
            // "Account Number: XX5171"
            #"[Aa]ccount\s+[Nn]umber\s*[:\-]\s*[Xx]{2}(\d{4})\b"#,
            // Generic XX1234
            #"[Xx]{2,}(\d{4})\b"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]),
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
