import Foundation

// MARK: - SMS Parser Service
/// Comprehensive Indian bank SMS parser.
/// Supports 25+ banks with a generic regex fallback for any unknown bank.
class SMSParserService {

    static let shared = SMSParserService()
    private init() {}

    // ─────────────────────────────────────────────────────────────
    // MARK: Public entry point
    // ─────────────────────────────────────────────────────────────
    func parse(smsBody: String, sender: String) -> Transaction? {
        guard isBankSMS(body: smsBody.lowercased(), sender: sender.lowercased()) else { return nil }
        guard let type   = extractTransactionType(body: smsBody) else { return nil }
        guard let amount = extractAmount(body: smsBody)           else { return nil }

        let merchant     = extractMerchant(body: smsBody, sender: sender)
        let bank         = detectBank(sender: sender, body: smsBody)
        let accountLast4 = extractAccountLast4(body: smsBody)
        let balance      = extractBalance(body: smsBody)
        let date         = extractDate(body: smsBody) ?? Date()
        let upiId        = extractUPIId(body: smsBody)
        let category     = CategoryService.shared.categorize(
                               merchant: merchant,
                               body: smsBody.lowercased(),
                               type: type,
                               upiId: upiId)

        return Transaction(
            date:         date,
            amount:       amount,
            type:         type,
            category:     category,
            merchant:     merchant,
            bankName:     bank,
            smsBody:      smsBody,
            accountLast4: accountLast4,
            balance:      balance,
            upiId:        upiId
        )
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Bank Detection (25+ Indian banks + generic)
    // ─────────────────────────────────────────────────────────────
    private let bankMap: [(patterns: [String], name: String)] = [
        // ── Private Sector ──────────────────────────────────────
        (["hdfc", "hdfcbk", "hdfcbank"],                  "HDFC Bank"),
        (["icici", "icicib", "icicibank"],                 "ICICI Bank"),
        (["axis", "axisbk", "axisbank"],                   "Axis Bank"),
        (["kotak", "kotakbk", "kotakbank", "kmbl"],        "Kotak Mahindra Bank"),
        (["yesbank", "yesbk", "ybl"],                      "Yes Bank"),
        (["indusind", "indusindbk", "induslnd"],           "IndusInd Bank"),
        (["idfcfirst", "idfc", "idfcfb"],                  "IDFC First Bank"),
        (["federalbank", "federal", "fedbk"],              "Federal Bank"),
        (["rblbank", "rbl"],                               "RBL Bank"),
        (["dcbbank", "dcb"],                               "DCB Bank"),
        (["bandhan", "bandhanbnk"],                        "Bandhan Bank"),
        (["karnataka", "ktkbk"],                           "Karnataka Bank"),
        (["csb", "catholicbank"],                          "CSB Bank"),
        (["tmb", "tamilmercantile"],                       "Tamil Mercantile Bank"),
        (["lakshmivilas", "lvb"],                          "Lakshmi Vilas Bank"),
        (["dhanlaxmi"],                                    "Dhanlaxmi Bank"),
        (["jkbank"],                                       "J&K Bank"),
        (["southindian", "sib"],                           "South Indian Bank"),
        (["cityunion", "cub"],                             "City Union Bank"),
        (["nainital"],                                     "Nainital Bank"),
        // ── Public Sector ────────────────────────────────────────
        (["sbi", "sbiinb", "sbipsg", "oksbi"],            "State Bank of India"),
        (["pnb", "punjabnat"],                             "Punjab National Bank"),
        (["bob", "bankofbaroda", "barodabk"],              "Bank of Baroda"),
        (["canara", "canarabk", "canarabank"],             "Canara Bank"),
        (["unionbank", "uboi"],                            "Union Bank of India"),
        (["bankofmaharashtra", "mahabank"],                "Bank of Maharashtra"),
        (["indianbank", "indbk"],                          "Indian Bank"),
        (["centralbank", "cbi"],                           "Central Bank of India"),
        (["uco", "ucobank"],                               "UCO Bank"),
        (["psbbank", "psb"],                               "Punjab & Sind Bank"),
        (["iob", "indianoverseas"],                        "Indian Overseas Bank"),
        (["boi", "bankofindia"],                           "Bank of India"),
        (["idbi", "idbibk"],                               "IDBI Bank"),
        // ── Small Finance / Payment Banks ────────────────────────
        (["aubank", "ausf"],                               "AU Small Finance Bank"),
        (["equitas", "equitasbnk"],                        "Equitas Small Finance Bank"),
        (["esaf"],                                         "ESAF Small Finance Bank"),
        (["ujjivan"],                                      "Ujjivan Small Finance Bank"),
        (["jana", "janabank"],                             "Jana Small Finance Bank"),
        (["suryoday"],                                     "Suryoday Small Finance Bank"),
        (["fincare", "fincarebnk"],                        "Fincare Small Finance Bank"),
        (["airtel", "airtelpaymentsbank"],                 "Airtel Payments Bank"),
        (["paytmbank", "paytmpayments"],                   "Paytm Payments Bank"),
        (["jiopaymentsbank", "jiomoney"],                  "Jio Payments Bank"),
        (["indiapost", "ippb"],                            "India Post Payments Bank"),
        // ── Cards / NBFC ─────────────────────────────────────────
        (["amex", "americanexpress"],                      "American Express"),
        (["citi", "citibank"],                             "Citibank"),
        (["hsbc"],                                         "HSBC Bank"),
        (["sc", "standardchartered", "scbk"],              "Standard Chartered"),
        (["bajajfinserv", "bajajfin"],                     "Bajaj Finserv"),
        (["sliceit", "slice"],                             "Slice"),
        (["onecard"],                                      "OneCard"),
        (["lazypay"],                                      "LazyPay"),
    ]

    func detectBank(sender: String, body: String) -> String {
        let s = sender.lowercased()
        let b = body.lowercased()
        for entry in bankMap {
            if entry.patterns.contains(where: { s.contains($0) || b.contains($0) }) {
                return entry.name
            }
        }
        // Generic: try to pull "XYZ Bank" from the SMS body
        if let regex = try? NSRegularExpression(pattern: #"([A-Z][A-Za-z ]{2,20})\s+[Bb]ank"#),
           let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 0), in: body) {
            return String(body[range])
        }
        return "Unknown Bank"
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Is Bank SMS?
    // ─────────────────────────────────────────────────────────────
    private func isBankSMS(body: String, sender: String) -> Bool {
        let txnWords = ["debited","credited","debit","credit","transaction",
                        "spent","withdrawn","withdrawal","transferred","payment",
                        "rs.","rs ","inr ","₹","a/c","acct","avl bal",
                        "avail bal","balance","txn","upi","imps","neft",
                        "rtgs","atm wtdl","mandate","emi","auto debit",
                        "cash withdrawal","purchase","pos ","online purchase"]
        let knownBankSenders = bankMap.flatMap(\.patterns)

        return knownBankSenders.contains(where: { sender.contains($0) })
            || txnWords.contains(where: { body.contains($0) })
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Transaction Type
    // ─────────────────────────────────────────────────────────────
    func extractTransactionType(body: String) -> TransactionType? {
        let b = body.lowercased()

        let debitWords  = ["debited","debit","withdrawn","withdrawal","spent","purchase",
                           "paid","payment of","transferred from","sent to","mandate executed",
                           "charged","deducted","auto debit","emi paid","cash withdrawal",
                           "atm wtdl","pos purchase","online purchase","dr "]
        let creditWords = ["credited","credit","received","deposited","refund","cashback",
                           "salary credited","added to","transferred to your",
                           "imps cr","neft cr","upi cr","reversed","reversal","cr "]

        if debitWords.contains(where: { b.contains($0) }) { return .debit }
        if creditWords.contains(where: { b.contains($0) }) { return .credit }

        // Sign-based fallback: DR / CR suffix in many bank formats
        if b.range(of: #"\bdr\b"#, options: .regularExpression) != nil { return .debit }
        if b.range(of: #"\bcr\b"#, options: .regularExpression) != nil { return .credit }

        return nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Amount Extraction
    // ─────────────────────────────────────────────────────────────
    func extractAmount(body: String) -> Double? {
        // Patterns ordered by specificity
        let patterns: [String] = [
            // Rs.1,234.56 / Rs 1234 / INR 1234.56 / ₹1234
            #"(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "amount Rs/INR ..."
            #"amount[\s:]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "1234.56 has been debited/credited"
            #"([0-9,]+\.[0-9]{2})\s+(?:has been |is )?(?:debited|credited|spent)"#,
            // "txn of Rs500"
            #"txn\s+of\s+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            // "for Rs 500" used in many UPI SMSes
            #"for\s+(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        let b = body.lowercased()
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: b, range: NSRange(b.startIndex..., in: b)),
               let range = Range(match.range(at: 1), in: b) {
                let raw = String(b[range]).replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Merchant Extraction
    // ─────────────────────────────────────────────────────────────
    func extractMerchant(body: String, sender: String) -> String {
        // 1. UPI VPA pattern → extract name before @
        if let upi = extractUPIId(body: body) {
            let name = upi.components(separatedBy: "@").first ?? ""
            if name.count > 2 { return beautify(name) }
        }

        // 2. "at <MERCHANT>" or "to <MERCHANT>"
        let patterns = [
            #"(?:at|to|towards|for payment to|paid to)\s+([A-Za-z][A-Za-z0-9 &'._\-]{2,35}?)(?:\s+on|\s+dated|\s+via|\s+for|\s+ref|\.|\,|\n|$)"#,
            #"merchant[:\s]+([A-Za-z][A-Za-z0-9 &'._\-]{2,30})"#,
            #"Info:\s*([A-Za-z][A-Za-z0-9 &'._\-]{2,35})"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let candidate = String(body[range]).trimmingCharacters(in: .whitespaces)
                if candidate.count > 2, !isGenericWord(candidate) {
                    return beautify(candidate)
                }
            }
        }

        // 3. Keyword lookup for well-known apps
        let wellKnown: [(kw: String, label: String)] = [
            ("swiggy","Swiggy"), ("zomato","Zomato"), ("amazon","Amazon"),
            ("flipkart","Flipkart"), ("meesho","Meesho"), ("myntra","Myntra"),
            ("ajio","AJIO"), ("nykaa","Nykaa"), ("uber","Uber"),
            ("ola cab","Ola"), ("rapido","Rapido"), ("irctc","IRCTC"),
            ("netflix","Netflix"), ("hotstar","Hotstar"), ("spotify","Spotify"),
            ("phonepe","PhonePe"), ("paytm","Paytm"), ("google pay","Google Pay"),
            ("gpay","Google Pay"), ("bigbasket","BigBasket"), ("blinkit","Blinkit"),
            ("zepto","Zepto"), ("dunzo","Dunzo"), ("jio","Jio"), ("airtel","Airtel"),
            ("dominos","Domino's"), ("mcdonalds","McDonald's"), ("kfc","KFC"),
            ("pizza hut","Pizza Hut"), ("subway","Subway"), ("starbucks","Starbucks"),
            ("haldirams","Haldiram's"), ("fasoos","Faasos"), ("box8","BOX8"),
        ]
        let bl = body.lowercased()
        for pair in wellKnown {
            if bl.contains(pair.kw) { return pair.label }
        }
        return "Unknown"
    }

    private func isGenericWord(_ s: String) -> Bool {
        let stop = ["your","the","this","that","bank","account","card","debit",
                    "credit","amount","balance","transaction","rupees","inr","rs"]
        return stop.contains(s.lowercased())
    }
    private func beautify(_ s: String) -> String {
        s.split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
         .joined(separator: " ")
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Account Last 4
    // ─────────────────────────────────────────────────────────────
    func extractAccountLast4(body: String) -> String? {
        let patterns = [
            #"(?:a/c|acct|account|card)[\s\w]*?(?:no\.?|number|num|#)?\s*(?:[xX*]+)?([0-9]{4})\b"#,
            #"(?:[xX*]{4,}|XX)([0-9]{4})\b"#,
            #"ending\s+(?:with\s+)?([0-9]{4})\b"#,
            #"\b(?:ac|ac\.|a\.c\.)?\s*(?:\*+|x+)([0-9]{4})\b"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r = Range(m.range(at: 1), in: body) {
                return String(body[r])
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Available Balance
    // ─────────────────────────────────────────────────────────────
    func extractBalance(body: String) -> Double? {
        let patterns = [
            #"(?:avl\.?\s*bal|avail(?:able)?\s*bal(?:ance)?|bal(?:ance)?\s*(?:is|:)?|balance after)\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r = Range(m.range(at: 1), in: body) {
                let raw = String(body[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw) { return v }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Date Extraction
    // ─────────────────────────────────────────────────────────────
    func extractDate(body: String) -> Date? {
        typealias FmtGroup = (pattern: String, formats: [String])
        let groups: [FmtGroup] = [
            (#"(\d{2}[-/]\d{2}[-/]\d{4})"#,       ["dd-MM-yyyy","dd/MM/yyyy"]),
            (#"(\d{2}[-/]\d{2}[-/]\d{2})"#,        ["dd-MM-yy","dd/MM/yy"]),
            (#"(\d{1,2}[-\s][A-Za-z]{3}[-\s]\d{4})"#, ["d-MMM-yyyy","d MMM yyyy"]),
            (#"(\d{1,2}[-\s][A-Za-z]{3}[-\s]\d{2})"#,  ["d-MMM-yy","d MMM yy"]),
            (#"([A-Za-z]{3}\s+\d{1,2},?\s+\d{4})"#,   ["MMM dd, yyyy","MMM dd yyyy"]),
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for g in groups {
            if let re = try? NSRegularExpression(pattern: g.pattern),
               let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r = Range(m.range(at: 1), in: body) {
                let ds = String(body[r])
                for f in g.formats {
                    fmt.dateFormat = f
                    if let d = fmt.date(from: ds) { return d }
                }
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: UPI VPA Extraction
    // ─────────────────────────────────────────────────────────────
    func extractUPIId(body: String) -> String? {
        // Handles all NPCI handles: @oksbi, @ybl, @paytm, @upi, @okhdfcbank, etc.
        let pattern = #"[a-zA-Z0-9.\-_+]+@[a-zA-Z0-9.\-_]+"#
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r = Range(m.range(at: 0), in: body) {
            return String(body[r]).lowercased()
        }
        return nil
    }
}
