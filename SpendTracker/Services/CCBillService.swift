import Foundation
import SwiftUI

// MARK: - CC Bill Status
enum CCBillStatus: String, Codable {
    case noStatement   = "No Statement"
    case unpaid        = "Unpaid"
    case partiallyPaid = "Partially Paid"
    case paid          = "Paid"

    var color: Color {
        switch self {
        case .noStatement:   return Color(.systemGray3)
        case .unpaid:        return Color(hex: "#E74C3C")
        case .partiallyPaid: return Color(hex: "#F39C12")
        case .paid:          return Color(hex: "#2ECC71")
        }
    }
    var icon: String {
        switch self {
        case .noStatement:   return "doc.questionmark"
        case .unpaid:        return "exclamationmark.circle.fill"
        case .partiallyPaid: return "clock.badge.exclamationmark"
        case .paid:          return "checkmark.seal.fill"
        }
    }
    var label: String { rawValue }
}

// MARK: - CC Bill Record
// One record per credit card per billing cycle.
struct CCBillRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var bank: String              // "ICICI Bank"
    var cardName: String          // "Amazon Pay", "MY ZONE", etc.
    var billingMonth: Date        // normalized to first day of billing month
    var periodStart: Date?
    var periodEnd: Date?
    var totalDue: Double    = 0
    var minimumDue: Double  = 0
    var dueDate: Date?
    var payments: [CCPayment] = []
    var lastUpdated: Date = Date()

    struct CCPayment: Codable {
        var date:   Date
        var amount: Double
    }

    var totalPaid: Double    { payments.reduce(0) { $0 + $1.amount } }
    var outstanding: Double  { max(0, totalDue - totalPaid) }

    var status: CCBillStatus {
        guard totalDue > 0 else {
            // No statement found — show as paid if we have a payment, else no statement
            return payments.isEmpty ? .noStatement : .paid
        }
        let paid = totalPaid
        if paid <= 0                       { return .unpaid }
        if paid >= totalDue - 1.0          { return .paid }
        return .partiallyPaid
    }

    // Stable identifier for dedup/matching
    var matchKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: billingMonth)
        return "\(bank.lowercased())|\(cardName.lowercased())|\(c.year ?? 0)-\(c.month ?? 0)"
    }

    static func makeKey(bank: String, cardName: String, month: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(bank.lowercased())|\(cardName.lowercased())|\(c.year ?? 0)-\(c.month ?? 0)"
    }
}

// MARK: - CC Bill Service
// Processes Gmail CC statement & payment-confirmation emails to track bill status.
//
// Statement subjects detected:
//   "Amazon Pay ICICI Bank Credit Card Statement for the period March 1, 2026 to March 28, 2026"
//   "HDFC Bank Credit Card Statement for March 2026"
//   "<any bank> Credit Card Statement"
//
// Payment confirmation subjects detected:
//   "Payment received on your ICICI Bank Credit Card"
//   "Your HDFC Bank Credit Card payment has been received"
//   "<any bank> Credit Card payment received"

class CCBillService: ObservableObject {

    static let shared = CCBillService()

    @Published private(set) var records: [CCBillRecord] = []
    private let storageKey = "cc_bill_records_v1"

    private init() { loadRecords() }

    // ─────────────────────────────────────────────────────────
    // MARK: Persistence
    // ─────────────────────────────────────────────────────────
    private func loadRecords() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CCBillRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Email Processing Entry Point
    // Called by GmailService for every fetched email.
    // ─────────────────────────────────────────────────────────
    func processEmail(subject: String, body: String, date: Date) {
        let sl = subject.lowercased()
        if isStatementSubject(sl) {
            processStatement(subject: subject, body: body, date: date)
        } else if isPaymentSubject(sl) {
            processPayment(subject: subject, body: body, date: date)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Subject Detection
    // ─────────────────────────────────────────────────────────
    private func isStatementSubject(_ sl: String) -> Bool {
        sl.contains("credit card statement")
    }

    private func isPaymentSubject(_ sl: String) -> Bool {
        // "payment received on your ICICI Bank Credit Card"
        // "Payment received: HDFC Credit Card"
        // "Your payment for Axis Bank Credit Card has been received"
        (sl.contains("credit card") && sl.contains("payment") && sl.contains("received")) ||
        (sl.contains("credit card") && sl.contains("payment received"))
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Statement Parsing
    // ─────────────────────────────────────────────────────────
    private func processStatement(subject: String, body: String, date: Date) {
        let (bank, cardName) = extractCardIdentity(from: subject)
        let (periodStart, periodEnd) = extractStatementPeriod(from: subject)
        let billingMonth = (periodEnd ?? periodStart ?? date).startOfMonth

        let totalDue   = extractDueAmount(from: body, keywords: [
            "total amount due", "total due", "total outstanding",
            "statement balance", "amount payable", "closing balance"
        ])
        let minimumDue = extractDueAmount(from: body, keywords: [
            "minimum amount due", "minimum due", "min. amount due",
            "minimum payment due", "min due", "minimum payment"
        ])
        let dueDate = extractDueDate(from: body)

        var record = findOrCreate(bank: bank, cardName: cardName, billingMonth: billingMonth)
        if totalDue   > 0 { record.totalDue   = totalDue   }
        if minimumDue > 0 { record.minimumDue = minimumDue }
        record.periodStart = periodStart ?? record.periodStart
        record.periodEnd   = periodEnd   ?? record.periodEnd
        record.dueDate     = dueDate     ?? record.dueDate
        record.lastUpdated = Date()

        upsert(record)
        DispatchQueue.main.async { self.persist() }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Payment Parsing
    // ─────────────────────────────────────────────────────────
    private func processPayment(subject: String, body: String, date: Date) {
        let (bank, cardName) = extractCardIdentity(from: subject)
        let amount = extractPaymentAmount(from: body)
        guard amount > 0 else { return }

        // Find best-matching unpaid/partial record for this bank+card
        var record: CCBillRecord
        if let target = findBestForPayment(bank: bank, cardName: cardName, paymentDate: date) {
            record = target
        } else {
            // No statement yet — file payment against the preceding billing month
            let prevMonth = Calendar.current
                .date(byAdding: .month, value: -1, to: date)!.startOfMonth
            record = findOrCreate(bank: bank, cardName: cardName, billingMonth: prevMonth)
        }

        // Dedup: don't double-add if same amount on same day
        let isDup = record.payments.contains {
            abs($0.amount - amount) < 1 && abs($0.date.timeIntervalSince(date)) < 86_400
        }
        guard !isDup else { return }

        record.payments.append(CCBillRecord.CCPayment(date: date, amount: amount))
        record.lastUpdated = Date()
        upsert(record)
        DispatchQueue.main.async { self.persist() }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Queries
    // ─────────────────────────────────────────────────────────
    func records(for month: Date) -> [CCBillRecord] {
        let target = month.startOfMonth
        return records
            .filter { $0.billingMonth == target }
            .sorted { $0.bank < $1.bank }
    }

    // One record per card (latest billing month), for the overview card on CreditCardView
    var latestPerCard: [CCBillRecord] {
        var byCard: [String: CCBillRecord] = [:]
        for r in records {
            let key = "\(r.bank.lowercased())|\(r.cardName.lowercased())"
            if let ex = byCard[key] {
                if r.billingMonth > ex.billingMonth { byCard[key] = r }
            } else {
                byCard[key] = r
            }
        }
        return Array(byCard.values).sorted { ($0.bank + $0.cardName) < ($1.bank + $1.cardName) }
    }

    // All billing history for one specific card, newest first
    func history(bank: String, cardName: String) -> [CCBillRecord] {
        let bl = bank.lowercased()
        let cl = cardName.lowercased()
        return records
            .filter { $0.bank.lowercased() == bl && $0.cardName.lowercased() == cl }
            .sorted { $0.billingMonth > $1.billingMonth }
    }

    // MARK: - Manual override (allow user to mark as paid from the UI)
    func markPaid(recordID: UUID, amount: Double, on date: Date) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var r = records[idx]
        let isDup = r.payments.contains {
            abs($0.amount - amount) < 1 && abs($0.date.timeIntervalSince(date)) < 86_400
        }
        if !isDup {
            r.payments.append(CCBillRecord.CCPayment(date: date, amount: amount))
            r.lastUpdated = Date()
            records[idx]  = r
            persist()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Private Helpers
    // ─────────────────────────────────────────────────────────
    private func findOrCreate(bank: String, cardName: String, billingMonth: Date) -> CCBillRecord {
        let key = CCBillRecord.makeKey(bank: bank, cardName: cardName, month: billingMonth)
        return records.first { $0.matchKey == key }
            ?? CCBillRecord(bank: bank, cardName: cardName, billingMonth: billingMonth)
    }

    private func upsert(_ record: CCBillRecord) {
        if let idx = records.firstIndex(where: { $0.matchKey == record.matchKey }) {
            records[idx] = record
        } else {
            records.append(record)
        }
    }

    private func findBestForPayment(bank: String, cardName: String, paymentDate: Date) -> CCBillRecord? {
        let bl = bank.lowercased()
        let cl = cardName.lowercased()
        return records
            .filter { r in
                let bMatch = r.bank.lowercased().contains(bl) || bl.contains(r.bank.lowercased())
                let cMatch = cl.isEmpty || r.cardName.isEmpty ||
                             r.cardName.lowercased().contains(cl) || cl.contains(r.cardName.lowercased())
                return bMatch && cMatch && r.status != .paid && r.billingMonth <= paymentDate
            }
            .sorted { $0.billingMonth > $1.billingMonth }
            .first
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Subject / Body Parsers
    // ─────────────────────────────────────────────────────────

    // Known bank name patterns (longest/most-specific first)
    private let knownBanks: [(pattern: String, normalized: String)] = [
        ("standard chartered", "Standard Chartered"),
        ("icici bank",         "ICICI Bank"),
        ("hdfc bank",          "HDFC Bank"),
        ("kotak mahindra",     "Kotak Bank"),
        ("kotak bank",         "Kotak Bank"),
        ("kotak",              "Kotak Bank"),
        ("axis bank",          "Axis Bank"),
        ("yes bank",           "Yes Bank"),
        ("indusind bank",      "IndusInd Bank"),
        ("indusind",           "IndusInd Bank"),
        ("idfc first",         "IDFC First Bank"),
        ("idfc",               "IDFC Bank"),
        ("au small finance",   "AU Bank"),
        ("au bank",            "AU Bank"),
        ("rbl bank",           "RBL Bank"),
        ("citi bank",          "Citi Bank"),
        ("citibank",           "Citi Bank"),
        ("sbi",                "SBI"),
        ("hdfc",               "HDFC Bank"),
        ("axis",               "Axis Bank"),
        ("bob",                "Bank of Baroda"),
        ("pnb",                "PNB"),
    ]

    // Returns (bankName, cardProductName)
    // e.g. "Amazon Pay ICICI Bank Credit Card Statement..."
    //   → ("ICICI Bank", "Amazon Pay")
    // "Payment received on your ICICI Bank Credit Card"
    //   → ("ICICI Bank", "")
    func extractCardIdentity(from subject: String) -> (bank: String, cardName: String) {
        let sl = subject.lowercased()
        var bank      = ""
        var bankStart = sl.endIndex   // position of bank name in sl

        for (pattern, normalized) in knownBanks {
            if let range = sl.range(of: pattern) {
                bank      = normalized
                bankStart = range.lowerBound
                break
            }
        }
        if bank.isEmpty { bank = "Unknown Bank" }

        // Card product name = everything before the bank name, cleaned up
        var cardName = ""
        if bankStart < sl.endIndex {
            let offset  = sl.distance(from: sl.startIndex, to: bankStart)
            let subjEnd = subject.index(subject.startIndex, offsetBy: offset)
            var before  = String(subject[subject.startIndex..<subjEnd])
                .trimmingCharacters(in: .whitespaces)
            for pfx in ["Your ", "your "] {
                if before.hasPrefix(pfx) { before = String(before.dropFirst(pfx.count)) }
            }
            cardName = before
        }

        return (bank, cardName.trimmingCharacters(in: .whitespaces))
    }

    // Extract billing period from subject
    // "for the period March 1, 2026 to March 28, 2026"
    private func extractStatementPeriod(from subject: String) -> (start: Date?, end: Date?) {
        let patterns = [
            #"for\s+the\s+period\s+(\w+\s+\d+,?\s*\d{4})\s+to\s+(\w+\s+\d+,?\s*\d{4})"#,
            #"(\w+\s+\d+,?\s*\d{4})\s+to\s+(\w+\s+\d+,?\s*\d{4})"#,
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        for pattern in patterns {
            guard let re    = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = re.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)),
                  match.numberOfRanges >= 3,
                  let r1    = Range(match.range(at: 1), in: subject),
                  let r2    = Range(match.range(at: 2), in: subject)
            else { continue }

            let s1 = String(subject[r1]).trimmingCharacters(in: .whitespaces)
            let s2 = String(subject[r2]).trimmingCharacters(in: .whitespaces)
            for f in ["MMMM d, yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMM d yyyy"] {
                fmt.dateFormat = f
                let d1 = fmt.date(from: s1)
                let d2 = fmt.date(from: s2)
                if d1 != nil || d2 != nil { return (d1, d2) }
            }
        }
        return (nil, nil)
    }

    // Extract total/minimum due from email body
    private func extractDueAmount(from body: String, keywords: [String]) -> Double {
        let bl  = body.lowercased()
        let pat = #"(?:inr|rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#
        guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return 0 }

        for kw in keywords {
            guard let kwEnd = bl.range(of: kw)?.upperBound else { continue }
            let limit  = min(120, bl.distance(from: kwEnd, to: bl.endIndex))
            let slice  = String(bl[kwEnd ..< bl.index(kwEnd, offsetBy: limit)])
            if let m   = re.firstMatch(in: slice, range: NSRange(slice.startIndex..., in: slice)),
               let r   = Range(m.range(at: 1), in: slice) {
                let raw = String(slice[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 1 { return v }
            }
        }
        return 0
    }

    // Extract the payment amount from a payment-received email body
    private func extractPaymentAmount(from body: String) -> Double {
        let bl  = body.lowercased()
        let pat = #"(?:inr|rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)"#
        guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return 0 }

        // Priority: look near payment-context keywords first
        for kw in ["payment of", "payment received", "amount paid", "amount received",
                   "amount credited", "received a payment of"] {
            guard let kwStart = bl.range(of: kw)?.lowerBound else { continue }
            let limit = min(150, bl.distance(from: kwStart, to: bl.endIndex))
            let slice = String(bl[kwStart ..< bl.index(kwStart, offsetBy: limit)])
            if let m  = re.firstMatch(in: slice, range: NSRange(slice.startIndex..., in: slice)),
               let r  = Range(m.range(at: 1), in: slice) {
                let raw = String(slice[r]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 1 { return v }
            }
        }
        // Fallback: first INR/₹ amount anywhere in the body
        if let m  = re.firstMatch(in: bl, range: NSRange(bl.startIndex..., in: bl)),
           let r  = Range(m.range(at: 1), in: bl) {
            let raw = String(bl[r]).replacingOccurrences(of: ",", with: "")
            if let v = Double(raw), v > 1 { return v }
        }
        return 0
    }

    // Extract due date from body
    private func extractDueDate(from body: String) -> Date? {
        let bl  = body.lowercased()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        for kw in ["payment due date", "due date", "pay by", "last date of payment"] {
            guard let end = bl.range(of: kw)?.upperBound else { continue }
            let limit = min(60, bl.distance(from: end, to: bl.endIndex))
            let sliceL = String(bl[end ..< bl.index(end, offsetBy: limit)])
            // Re-map to original body for correct casing
            let offset  = bl.distance(from: bl.startIndex, to: end)
            let bStart  = body.index(body.startIndex, offsetBy: offset)
            let bEnd    = body.index(bStart, offsetBy: limit)
            let sliceO  = String(body[bStart..<bEnd])

            let dateRe  = #"\b(\d{1,2}[-/ ]\w+[-/ ]\d{2,4}|\w+ \d{1,2},? \d{4})\b"#
            if let re   = try? NSRegularExpression(pattern: dateRe, options: .caseInsensitive),
               let m    = re.firstMatch(in: sliceO, range: NSRange(sliceO.startIndex..., in: sliceO)),
               let r    = Range(m.range(at: 1), in: sliceO) {
                let ds = String(sliceO[r])
                for f in ["dd-MMM-yyyy", "dd MMM yyyy", "MMMM d, yyyy",
                          "dd/MM/yyyy", "MMM dd, yyyy", "d MMMM yyyy"] {
                    fmt.dateFormat = f
                    if let d = fmt.date(from: ds) { return d }
                }
            }
            _ = sliceL  // suppress unused warning
        }
        return nil
    }
}
