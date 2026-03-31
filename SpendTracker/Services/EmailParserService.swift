import Foundation

// MARK: - Email Parser Service
// V21 logic restored + declined filter + multi-line Axis format + cardType
class EmailParserService {

    static let shared = EmailParserService()
    private init() {}
    private let smsParser = SMSParserService.shared

    // Thread-safe regex cache — compiles each unique pattern once, reuses on all
    // subsequent calls. A single email parse hits 25+ patterns; caching cuts the
    // NSRegularExpression allocation cost to ~zero after the first parse.
    private static var _regexCache: [String: NSRegularExpression] = [:]
    private static let _cacheLock  = NSLock()
    private static func re(_ pattern: String,
                           _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        _cacheLock.lock(); defer { _cacheLock.unlock() }
        if let cached = _regexCache[key] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options)
        else { return nil }
        _regexCache[key] = compiled
        return compiled
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Multi-Transaction Entry Point
    // Some bank emails contain multiple transactions in one email
    // (e.g. Axis Bank daily digest, ICICI weekly summary).
    // Strategy: split on transaction boundaries and parse each chunk.
    // Falls back to single parse() if no split point found.
    // ─────────────────────────────────────────────────────────
    func parseAll(emailBody: String, sender: String, date: Date) -> [Transaction] {
        let cleaned = cleanText(emailBody)

        // Split boundaries — patterns that start a new transaction block:
        // "Amount Debited:" / "Amount Credited:" repeating in same email,
        // or "INR X.XX was debited/credited" appearing multiple times.
        let splitPatterns = [
            #"(?=Amount\s+(?:Debited|Credited)\s*:)"#,
            #"(?=INR\s+[0-9,]+(?:\.[0-9]{1,2})?\s+(?:was\s+)?(?:debited|credited))"#,
            #"(?=Rs\.?\s+[0-9,]+(?:\.[0-9]{1,2})?\s+(?:was\s+)?(?:debited|credited))"#,
        ]

        var chunks: [String] = []
        for pattern in splitPatterns {
            if let compiled = Self.re(pattern, .caseInsensitive) {
                let range   = NSRange(cleaned.startIndex..., in: cleaned)
                let matches = compiled.matches(in: cleaned, range: range)
                if matches.count > 1 {
                    // Found multiple transaction blocks — split on them
                    var positions = matches.map { Range($0.range, in: cleaned)!.lowerBound }
                    positions.append(cleaned.endIndex)
                    chunks = zip(positions, positions.dropFirst()).map {
                        String(cleaned[$0..<$1])
                    }
                    break
                }
            }
        }

        // No multi-transaction split found — treat as single email
        if chunks.isEmpty {
            if let txn = parse(emailBody: cleaned, sender: sender, date: date) {
                return [txn]
            }
            return []
        }

        // Parse each chunk, prepend original subject (first line) to each
        let subject = cleaned.components(separatedBy: "\n").first ?? ""
        var results: [Transaction] = []
        for chunk in chunks {
            let chunkWithSubject = subject + "\n" + chunk
            if let txn = parse(emailBody: chunkWithSubject, sender: sender, date: date) {
                results.append(txn)
            }
        }
        // Deduplicate: if all chunks parsed to same amount+type it was a false split
        if results.count > 1 {
            let unique = results.reduce(into: [Transaction]()) { acc, txn in
                let isDup = acc.contains {
                    abs($0.amount - txn.amount) < 0.01 && $0.type == txn.type
                }
                if !isDup { acc.append(txn) }
            }
            return unique
        }
        return results
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Main Entry Point (single transaction)
    // ─────────────────────────────────────────────────────────
    func parse(emailBody: String, sender: String, date: Date) -> Transaction? {
        let cleaned = cleanText(emailBody)
        let b       = cleaned.lowercased()

        // ── Reject DECLINED / FAILED transactions ─────────────
        // IMPORTANT: Use only phrases that appear EXCLUSIVELY in decline emails.
        // DO NOT use "not authorized" / "not authorised" — these appear in the
        // standard footer of ALL successful bank transaction emails:
        //   e.g. "If this transaction was not authorised by you, please call..."
        // Similarly avoid "unable to process" / "could not be processed" since
        // they appear in generic email footers too.
        let declineWords = [
            "has been declined", "was declined", "transaction declined",
            "payment declined", "been declined",
            "transaction failed", "payment failed",
            "domestic online transactions is disabled",
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
            // "credited/debited with INR 2213.00" — Axis NEFT, SBI
            (#"(?:credited|debited)\s+with\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // ICICI: "a transaction of INR 139.00" — high priority before generic INR
            (#"transaction\s+of\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "for INR 500" / "for Rs. 500" — covers "used for INR X" constructs
            (#"for\s+(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "INR 120.00" or "INR120.00"
            (#"INR\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "₹120" or "₹120/-"
            (#"₹\s*([0-9,]+(?:\.[0-9]{1,2})?)(?:\s*\/\-?)?"#, []),
            // "Rs. 120" or "Rs 120" or "Rs. 120/-"
            (#"[Rr][Ss]\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)(?:\s*\/\-?)?"#, []),
            // "Amount Debited: 120.00" / "Amount Credited: 120"
            (#"[Aa]mount\s*(?:[Dd]ebited|[Cc]redited)\s*[:\-]?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
            // "Amount: INR 120" / "Amount: 120"
            (#"[Aa]mount\s*[:\-]\s*(?:INR|Rs\.?)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#, []),
        ]
        for (p, opts) in patterns {
            if let compiled = Self.re(p, opts),
               let match    = compiled.firstMatch(in: b, range: NSRange(b.startIndex..., in: b)),
               let range    = Range(match.range(at: 1), in: b) {
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
            // Strong multi-word phrases — checked first, high confidence
            "was debited from your",  "has been debited from",  "debited from your",
            "has been debited with",  "was debited with",       "debited from",
            "has been debited",       "account.*?debited",
            "card.*used for",         "has been used for",      "has been used at",
            "has been used for a transaction",
            "is used for",            "purchase of",
            // SBI / generic: "payment has been made from your account"
            "made from your",         "has been made on your",
            "charged to your",        "debited for",
            "spent",                  "withdrawn",              "withdrawal",
            "auto debit",             "ach debit",              "nach debit",
            "mandate executed",
            // Bare-word fallback — only reached when no specific phrase matched
            "\\bdebited\\b",
        ]
        let creditWords = [
            // Strong specific phrases
            "was credited",           "has been credited",      "credited to",
            "has been credited with", "credited with inr",      "amount credited",
            "salary credited",
            // Reversals and refunds
            "reversed",              "refund",                  "cashback",
            // Transfer receipts
            "amount received",       "payment received",        "salary received",
            "funds.*?received",      "money.*?received",
            "neft received",         "imps received",           "upi received",
            // Bare-word fallback
            "\\bcredited\\b",
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
    // MARK: Merchant Normalization
    // Maps raw extracted names to canonical merchant/app names.
    // Longest match wins — check longer aliases before shorter ones.
    // ─────────────────────────────────────────────────────────
    private let merchantAliases: [(pattern: String, canonical: String)] = [
        // Payment apps
        ("amazon pay",     "Amazon Pay"),
        ("amazonpay",      "Amazon Pay"),
        ("google pay",     "Google Pay"),
        ("gpay",           "Google Pay"),
        ("phonepe",        "PhonePe"),
        ("paytm",          "Paytm"),
        ("bhim",           "BHIM UPI"),
        // E-commerce
        ("amazon prime",   "Amazon Prime"),
        ("amazon",         "Amazon"),
        ("flipkart",       "Flipkart"),
        ("myntra",         "Myntra"),
        ("meesho",         "Meesho"),
        ("ajio",           "Ajio"),
        ("nykaa",          "Nykaa"),
        ("tatacliq",       "TataCliq"),
        // Food delivery
        ("swiggy",         "Swiggy"),
        ("zomato",         "Zomato"),
        ("dominos",        "Domino's"),
        ("domino",         "Domino's"),
        ("mcdonalds",      "McDonald's"),
        ("burger king",    "Burger King"),
        ("kfc",            "KFC"),
        ("subway",         "Subway"),
        ("starbucks",      "Starbucks"),
        // Grocery
        ("bigbasket",      "BigBasket"),
        ("blinkit",        "Blinkit"),
        ("zepto",          "Zepto"),
        ("dmart",          "D-Mart"),
        ("reliance fresh", "Reliance Fresh"),
        // Travel
        ("irctc",          "IRCTC"),
        ("uber eats",      "Uber Eats"),
        ("uber",           "Uber"),
        ("ola cabs",       "Ola"),
        ("rapido",         "Rapido"),
        ("makemytrip",     "MakeMyTrip"),
        ("goibibo",        "Goibibo"),
        ("redbus",         "RedBus"),
        ("bookmyshow",     "BookMyShow"),
        // Entertainment
        ("netflix",        "Netflix"),
        ("spotify",        "Spotify"),
        ("hotstar",        "Hotstar"),
        ("zee5",           "Zee5"),
        ("sony liv",       "Sony LIV"),
        // Fintech
        ("zerodha",        "Zerodha"),
        ("groww",          "Groww"),
        ("upstox",         "Upstox"),
    ]

    private func normalizeMerchant(_ raw: String) -> String {
        let lowered = raw.lowercased()
        for (pattern, canonical) in merchantAliases {
            if lowered.contains(pattern) { return canonical }
        }
        return raw
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Merchant (V21 logic + multi-line + NEFT + normalization)
    // Public wrapper applies canonical normalization after extraction.
    // ─────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {
        return normalizeMerchant(rawExtractMerchant(body: body, sender: sender))
    }

    private func rawExtractMerchant(body: String, sender: String) -> String {
        let r = NSRange(body.startIndex..., in: body)

        // 1. Multi-line Axis: "Transaction Info:\nUPI/P2A/.../NAME/BANK/UPI"
        if let m = Self.re(#"[Tt]ransaction\s*[Ii]nfo\s*[:\-]?\s*\n\s*UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#, .dotMatchesLineSeparators)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let name = String(body[gr]).trimmingCharacters(in: .whitespaces).components(separatedBy: "/").first ?? ""
            if name.count > 1 { return beautify(name) }
        }

        // 2. UPI slash format: "UPI/P2A|P2M/REFNUM/NAME" (Axis, HDFC, SBI)
        if let m = Self.re(#"UPI/P2[AM]/\d+/([A-Za-z][A-Za-z0-9 ]{1,40})"#)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let name = String(body[gr]).trimmingCharacters(in: .whitespaces).components(separatedBy: "/").first ?? ""
            if name.count > 1 { return beautify(name) }
        }

        // 3. ICICI/HDFC UPI dash: "UPI-REFNUM-NAME" or "UPI/REFNUM/NAME"
        if let m = Self.re(#"UPI[-/]\d{6,}[-/]([A-Za-z][A-Za-z0-9 ]{1,40})"#)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let name = String(body[gr]).trimmingCharacters(in: .whitespaces)
            if name.count > 1 { return beautify(name) }
        }

        // 4. NEFT/IMPS remitter: "by NEFT/REF/NAME" or "IMPS/REF/NAME"
        if let m = Self.re(#"by\s+(?:NEFT|IMPS)/[A-Z0-9]+/([A-Za-z][A-Za-z0-9 &._\-]{1,40})"#, .caseInsensitive)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let n = String(body[gr]).trimmingCharacters(in: .whitespaces)
            if n.count > 1 { return beautify(n) }
        }

        // 5. "has been used at/for MERCHANT for INR" — ICICI CC, SBI
        if let m = Self.re(#"(?:has been used|was used|is used)\s+(?:at|for\s+purchase\s+at|for)\s+([A-Za-z][A-Za-z0-9 &._\-]{2,50})(?:\s+for\s+(?:INR|Rs|₹)|[.\n]|$)"#, .caseInsensitive)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let name = String(body[gr]).trimmingCharacters(in: .whitespaces)
            if name.count > 2, !isGeneric(name) { return beautify(name) }
        }

        // 6. "at MERCHANT" pattern — "transaction at BIG BAZAAR" (HDFC, Kotak)
        if let m = Self.re(#"(?:purchase|transaction|spent|payment)\s+at\s+([A-Za-z][A-Za-z0-9 &._\-]{2,50})(?=[.,\n]|\s+on|\s+for|\s+of|$)"#, .caseInsensitive)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let name = String(body[gr]).trimmingCharacters(in: .whitespaces)
            if name.count > 2, !isGeneric(name) { return beautify(name) }
        }

        // 7. Label patterns: Info/Merchant Name/Description/Remarks/paid to
        let labelPatterns: [(String, NSRegularExpression.Options)] = [
            (#"[Tt]ransaction\s*[Ii]nfo\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"\bInfo\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"[Mm]erchant\s*(?:[Nn]ame)?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"[Dd]escription\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"[Nn]arration\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"[Rr]emarks?\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, []),
            (#"(?:paid to|payment to|transferred to|sent to)\s+([A-Za-z][A-Za-z0-9 &._\-]{2,50})"#, .caseInsensitive),
        ]
        for (pattern, opts) in labelPatterns {
            if let m  = Self.re(pattern, opts)?.firstMatch(in: body, range: r),
               let gr = Range(m.range(at: 1), in: body) {
                let candidate = String(body[gr])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: "\n").first ?? ""
                let clean = candidate.components(separatedBy: CharacterSet.alphanumerics
                    .union(.init(charactersIn: " &._-")).inverted).joined()
                    .trimmingCharacters(in: .whitespaces)
                if clean.count > 2, !isGeneric(clean) { return beautify(clean) }
            }
        }

        // 8. ACH / bank transfer: "debited ... by ACH-DR-TP ACH ICICI BANK-2"
        if let m = Self.re(#"(?:debited|credited).{0,120}?\bby\s+([A-Za-z][A-Za-z0-9 &._\-]{2,50})(?=[.\n]|$)"#, .caseInsensitive)?.firstMatch(in: body, range: r),
           let gr = Range(m.range(at: 1), in: body) {
            let raw = String(body[gr]).trimmingCharacters(in: .whitespaces)
            if raw.count > 2, !isGeneric(raw) { return beautify(cleanACHMerchant(raw)) }
        }

        // 9. UPI VPA before @: "swiggy@oksbi" → "Swiggy"
        if let upi  = smsParser.extractUPIId(body: body) {
            let name = upi.components(separatedBy: "@").first ?? ""
            if name.count > 2 { return beautify(name) }
        }

        return smsParser.extractMerchant(body: body, sender: sender)
    }
    // (end of rawExtractMerchant)

    // ─────────────────────────────────────────────────────────
    // MARK: Account
    // ─────────────────────────────────────────────────────────
    private func extractAccount(body: String) -> String? {
        let nr = NSRange(body.startIndex..., in: body)
        let patterns: [(String, NSRegularExpression.Options)] = [
            // Multi-line: "Account Number:\nXX5171"
            (#"[Aa]ccount\s*[Nn]umber\s*[:\-]?\s*\n\s*[Xx]{2}(\d{4})\b"#,  .dotMatchesLineSeparators),
            // "A/C No. XX1234" / "Ac No XX1234"
            (#"[Aa][/.]?[Cc]\.?\s*[Nn]o\.?\s*[Xx]{1,4}(\d{4})"#,           .caseInsensitive),
            // "Credit Card XX7001" / "Debit Card XX1234"
            (#"(?:[Cc]redit|[Dd]ebit)\s+[Cc]ard\s+[Xx]{1,4}(\d{4})"#,      .caseInsensitive),
            // "Card XX1234" / "card ending 1234"
            (#"[Cc]ard\s+(?:[Xx]{1,4}|ending\s*)(\d{4})"#,                  .caseInsensitive),
            // "XXXXXXXX1234" — generic masked number
            (#"[Xx]{2,}(\d{4})\b"#,                                           .caseInsensitive),
        ]
        for (p, opts) in patterns {
            if let m = Self.re(p, opts)?.firstMatch(in: body, range: nr),
               let r = Range(m.range(at: 1), in: body) { return String(body[r]) }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Balance
    // ─────────────────────────────────────────────────────────
    private func extractBalance(body: String) -> Double? {
        let nr = NSRange(body.startIndex..., in: body)
        // Prefer account balance over credit limit lines
        let patterns = [
            #"[Aa]vail(?:able)?\s+[Bb]al(?:ance)?\s*[:\-]?\s*(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Bb]alance\s+(?:after|is)\s*[:\-]?\s*(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Bb]alance\s*[:\-]\s*(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"[Aa]vailable\s+[Cc]redit\s+[Ll]imit.*?(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let m = Self.re(p, .dotMatchesLineSeparators)?.firstMatch(in: body, range: nr),
               let rv = Range(m.range(at: 1), in: body) {
                let raw = String(body[rv]).replacingOccurrences(of: ",", with: "")
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
        let nr = NSRange(body.startIndex..., in: body)

        let pairs: [(String, [String])] = [
            // "19-03-26, 19:12:44" or "19-03-26 19:12:44" — Axis short year
            (#"(\d{2}-\d{2}-\d{2})[,\s]+\d{2}:\d{2}(?::\d{2})?"#,       ["dd-MM-yy"]),
            // "16-03-2026 at 15:34:13" or "16-03-2026 15:34" — Axis NEFT
            (#"(\d{2}-\d{2}-\d{4})\s+(?:at\s+)?\d{2}:\d{2}"#,           ["dd-MM-yyyy"]),
            // "Mar 19, 2026 at 01:11:35" / "Mar 19, 2026" — ICICI
            (#"([A-Za-z]{3}\s+\d{1,2},\s+\d{4})"#,                       ["MMM dd, yyyy", "MMM d, yyyy"]),
            // "19 Mar 2026" / "5 Jan 2026"
            (#"(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})"#,                      ["dd MMM yyyy", "d MMMM yyyy", "dd MMMM yyyy"]),
            // "19/03/2026" or "19-03-2026" (no time)
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#,                               ["dd-MM-yyyy", "dd/MM/yyyy"]),
            // "2026-03-19" — ISO format
            (#"(\d{4}-\d{2}-\d{2})"#,                                      ["yyyy-MM-dd"]),
        ]
        for (p, formats) in pairs {
            if let m = Self.re(p)?.firstMatch(in: body, range: nr),
               let rv = Range(m.range(at: 1), in: body) {
                let ds = String(body[rv])
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
        let nr = NSRange(body.startIndex..., in: body)
        // "UPI/912345678901" or "UPI-912345678901" — numeric reference
        if let m = Self.re(#"UPI[-/](\d{10,})"#)?.firstMatch(in: body, range: nr),
           let r = Range(m.range(at: 0), in: body) { return String(body[r]) }
        // IMPS / NEFT reference number as UPI fallback signal
        if let m = Self.re(#"(?:IMPS|NEFT|RTGS)[/ ](\d{10,})"#)?.firstMatch(in: body, range: nr),
           let r = Range(m.range(at: 0), in: body) { return String(body[r]) }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────

    // Converts "ACH-DR-TP ACH ICICI BANK-2" → "ICICI Bank EMI"
    // Strips ACH/NACH/TP prefixes and trailing sequence numbers
    private func cleanACHMerchant(_ raw: String) -> String {
        let knownBanks = ["HDFC", "ICICI", "SBI", "AXIS", "KOTAK", "YES",
                          "INDUSIND", "IDFC", "FEDERAL", "RBL", "PNB", "BOB",
                          "CANARA", "UNION", "BAJAJ", "TATA CAPITAL", "FULLERTON",
                          "CHOLAMANDALAM", "MUTHOOT", "MANAPPURAM", "L&T FINANCE"]
        let upper = raw.uppercased()
        for bank in knownBanks {
            if upper.contains(bank) {
                // Title-case the bank name and append "EMI" for clarity
                let name = bank.prefix(1).uppercased() + bank.dropFirst().lowercased()
                return "\(name) Bank EMI"
            }
        }
        // Not a known bank — strip "ACH-DR", "NACH", "TP", trailing digits
        let cleaned = raw
            .replacingOccurrences(of: #"ACH[\-]?DR[\-]?TP\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"NACH\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"ACH\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"-\d+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? raw : cleaned
    }

    private func isGeneric(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: .whitespaces)
        let stop: Set<String> = [
            "your","the","this","that","a","an",
            "bank","account","card","debit","credit",
            "amount","balance","transaction","payment",
            "rupees","inr","rs","dear","customer","summary",
            "enable","service","facility","online","domestic",
            "mobile","number","details","info","information",
            "regards","note","please","contact","helpline",
            "neft","imps","rtgs","upi","ref","reference",
        ]
        // Also reject entries that are purely numeric or too short
        return stop.contains(t) || t.count < 3 ||
               t.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "/" })
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
        // HTML entity decoding
        let entities: [(String, String)] = [
            ("&amp;","&"),("&lt;","<"),("&gt;",">"),
            ("&nbsp;"," "),("&ensp;"," "),("&emsp;"," "),("\u{00A0}"," "),
            ("&quot;","\""),("&#34;","\""),("&#39;","'"),("&apos;","'"),
            ("&rsquo;","'"),("&lsquo;","'"),("&ndash;","-"),("&mdash;","-"),
            ("&bull;"," "),("&middot;"," "),("&#8226;"," "),("&#183;"," "),
            ("&hellip;","..."),("&#8230;","..."),
            ("&raquo;",""),("&laquo;",""),("&#187;",""),("&#171;",""),
        ]
        entities.forEach { t = t.replacingOccurrences(of: $0.0, with: $0.1) }
        // Numeric HTML entities: &#123; and &#x7B;
        if let re = Self.re(#"&#x?([0-9A-Fa-f]+);"#) {
            let range = NSRange(t.startIndex..., in: t)
            let results = re.matches(in: t, range: range).reversed()
            for m in results {
                guard let mr = Range(m.range, in: t),
                      let cr = Range(m.range(at: 1), in: t) else { continue }
                let hex  = String(t[cr])
                let base = hex.lowercased().hasPrefix("x") ? 16 : 10
                let codeStr = hex.lowercased().hasPrefix("x") ? String(hex.dropFirst()) : hex
                if let code = UInt32(codeStr, radix: base),
                   let scalar = Unicode.Scalar(code) {
                    t.replaceSubrange(mr, with: String(Character(scalar)))
                }
            }
        }
        // Normalise line endings and whitespace
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\r",   with: "\n")
        t = t.replacingOccurrences(of: "\t",   with: " ")
        // Collapse multiple spaces on the same line (not across newlines)
        let lines = t.components(separatedBy: "\n").map { line -> String in
            var l = line
            while l.contains("  ") { l = l.replacingOccurrences(of: "  ", with: " ") }
            return l.trimmingCharacters(in: .init(charactersIn: " "))
        }
        // Remove completely blank lines (3+ consecutive newlines → 1)
        var result = lines.joined(separator: "\n")
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result
    }
}
