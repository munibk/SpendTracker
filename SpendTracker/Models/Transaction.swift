import Foundation
import SwiftUI

// MARK: - Transaction Model
struct Transaction: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var amount: Double
    var type: TransactionType
    var category: SpendCategory
    var merchant: String
    var bankName: String
    var smsBody: String
    var accountLast4: String?
    var balance: Double?
    var upiId: String?
    var isManual: Bool
    var note: String?
    
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        amount: Double,
        type: TransactionType,
        category: SpendCategory = .others,
        merchant: String = "Unknown",
        bankName: String = "Unknown",
        smsBody: String = "",
        accountLast4: String? = nil,
        balance: Double? = nil,
        upiId: String? = nil,
        isManual: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.type = type
        self.category = category
        self.merchant = merchant
        self.bankName = bankName
        self.smsBody = smsBody
        self.accountLast4 = accountLast4
        self.balance = balance
        self.upiId = upiId
        self.isManual = isManual
        self.note = note
    }
}

// MARK: - Transaction Type
enum TransactionType: String, Codable, CaseIterable {
    case debit = "Debit"
    case credit = "Credit"
    
    var icon: String {
        switch self {
        case .debit: return "arrow.up.right.circle.fill"
        case .credit: return "arrow.down.left.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .debit: return .red
        case .credit: return .green
        }
    }
}

// MARK: - Spending Category
enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food & Dining"
    case shopping = "Shopping"
    case upi = "UPI Transfer"
    case fuel = "Fuel"
    case bills = "Bills & Utilities"
    case atm = "ATM Withdrawal"
    case travel = "Travel"
    case entertainment = "Entertainment"
    case health = "Health & Medical"
    case education = "Education"
    case groceries = "Groceries"
    case recharge = "Recharge & Top-up"
    case emi = "EMI & Loans"
    case investment = "Investment"
    case salary = "Salary"
    case others = "Others"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .shopping: return "bag.fill"
        case .upi: return "qrcode"
        case .fuel: return "fuelpump.fill"
        case .bills: return "bolt.fill"
        case .atm: return "banknote.fill"
        case .travel: return "airplane"
        case .entertainment: return "tv.fill"
        case .health: return "cross.fill"
        case .education: return "book.fill"
        case .groceries: return "cart.fill"
        case .recharge: return "phone.fill"
        case .emi: return "creditcard.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .salary: return "indianrupeesign.circle.fill"
        case .others: return "ellipsis.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .food: return Color(hex: "#FF6B6B")
        case .shopping: return Color(hex: "#4ECDC4")
        case .upi: return Color(hex: "#45B7D1")
        case .fuel: return Color(hex: "#FFA07A")
        case .bills: return Color(hex: "#98D8C8")
        case .atm: return Color(hex: "#7B68EE")
        case .travel: return Color(hex: "#20B2AA")
        case .entertainment: return Color(hex: "#FFD700")
        case .health: return Color(hex: "#FF69B4")
        case .education: return Color(hex: "#87CEEB")
        case .groceries: return Color(hex: "#90EE90")
        case .recharge: return Color(hex: "#DDA0DD")
        case .emi: return Color(hex: "#F0808A")
        case .investment: return Color(hex: "#3CB371")
        case .salary: return Color(hex: "#32CD32")
        case .others: return Color(hex: "#A9A9A9")
        }
    }
    
    // Keywords used for auto-categorization
    var keywords: [String] {
        switch self {
        case .food:
            return ["swiggy", "zomato", "dominos", "pizza", "burger", "restaurant",
                    "cafe", "food", "eating", "dine", "mcdonalds", "kfc", "subway",
                    "barbeque", "dhaba", "hotel", "biryani", "starbucks", "chai"]
        case .shopping:
            return ["amazon", "flipkart", "myntra", "ajio", "meesho", "nykaa",
                    "shoppers stop", "westside", "zara", "h&m", "max fashion",
                    "lifestyle", "reliance trends", "snapdeal", "tatacliq", "paytm mall"]
        case .upi:
            return ["upi", "gpay", "phonepe", "paytm", "bhim", "imps", "neft",
                    "transfer to", "sent to", "paid to", "@ok", "@ybl", "@paytm",
                    "@oksbi", "@okicici", "@okhdfcbank", "p2p", "peer"]
        case .fuel:
            return ["petrol", "diesel", "fuel", "hp", "iocl", "bpcl", "reliance petrol",
                    "shell", "indian oil", "hindustan petroleum", "bharat petroleum", "cng", "gas station"]
        case .bills:
            return ["electricity", "water", "broadband", "internet", "jio", "airtel",
                    "vodafone", "vi ", "bsnl", "tata sky", "dth", "gas bill", "piped gas",
                    "mahanagar gas", "bescom", "tneb", "msedcl", "utilities", "postpaid"]
        case .atm:
            return ["atm", "cash withdrawal", "cash wtdl", "atm wtdl", "atm cash"]
        case .travel:
            return ["irctc", "railway", "bus", "uber", "ola", "rapido", "auto",
                    "cab", "makemytrip", "goibibo", "yatra", "cleartrip", "flight",
                    "airport", "metro", "redbus", "ticket booking"]
        case .entertainment:
            return ["netflix", "amazon prime", "hotstar", "zee5", "sony liv", "disney",
                    "bookmyshow", "pvr", "inox", "movie", "theatre", "spotify", "youtube premium",
                    "gaming", "steam", "playstation"]
        case .health:
            return ["pharmacy", "medical", "hospital", "clinic", "doctor", "apollo",
                    "1mg", "netmeds", "medplus", "diagnostic", "lab test", "health",
                    "ayurvedic", "medicine", "chemist"]
        case .education:
            return ["byju", "unacademy", "udemy", "coursera", "school fees", "college fees",
                    "tuition", "education", "books", "library", "exam fee", "coaching"]
        case .groceries:
            return ["bigbasket", "grofers", "blinkit", "zepto", "dmart", "reliance fresh",
                    "more supermarket", "supermarket", "grocery", "vegetables", "fruits",
                    "kirana", "provisions", "milk", "dairy"]
        case .recharge:
            return ["recharge", "prepaid", "talktime", "data pack", "top up", "mobile recharge",
                    "dth recharge", "fastag"]
        case .emi:
            return ["emi", "loan", "installment", "mortgage", "home loan", "car loan",
                    "personal loan", "equated", "repayment", "bajaj finance", "hdfc loan"]
        case .investment:
            return ["mutual fund", "sip", "zerodha", "groww", "upstox", "stocks", "nse",
                    "bse", "ipo", "ppf", "fd ", "fixed deposit", "rd ", "recurring deposit",
                    "insurance premium", "lic", "sbi life", "hdfc life"]
        case .salary:
            return ["salary", "payroll", "ctc", "wages", "stipend", "remuneration"]
        case .others:
            return []
        }
    }
}

// MARK: - Formatted Helpers
extension Transaction {
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "₹\(amount)"
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}
