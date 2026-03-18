import Foundation
import SwiftUI

// MARK: - Transaction Type
enum TransactionType: String, Codable, CaseIterable {
    case debit  = "Debit"
    case credit = "Credit"

    var icon: String {
        switch self {
        case .debit:  return "arrow.up.right.circle.fill"
        case .credit: return "arrow.down.left.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .debit:  return .red
        case .credit: return .green
        }
    }
}

// MARK: - Spend Category
enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food          = "Food & Dining"
    case shopping      = "Shopping"
    case upi           = "UPI Transfer"
    case fuel          = "Fuel"
    case bills         = "Bills & Utilities"
    case atm           = "ATM Withdrawal"
    case travel        = "Travel"
    case entertainment = "Entertainment"
    case health        = "Health & Medical"
    case education     = "Education"
    case groceries     = "Groceries"
    case recharge      = "Recharge & Top-up"
    case emi           = "EMI & Loans"
    case investment    = "Investment"
    case salary        = "Salary"
    case others        = "Others"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food:          return "fork.knife"
        case .shopping:      return "bag.fill"
        case .upi:           return "qrcode"
        case .fuel:          return "fuelpump.fill"
        case .bills:         return "bolt.fill"
        case .atm:           return "banknote.fill"
        case .travel:        return "airplane"
        case .entertainment: return "tv.fill"
        case .health:        return "cross.fill"
        case .education:     return "book.fill"
        case .groceries:     return "cart.fill"
        case .recharge:      return "phone.fill"
        case .emi:           return "creditcard.fill"
        case .investment:    return "chart.line.uptrend.xyaxis"
        case .salary:        return "indianrupeesign.circle.fill"
        case .others:        return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .food:          return Color(hex: "#FF6B6B")
        case .shopping:      return Color(hex: "#4ECDC4")
        case .upi:           return Color(hex: "#45B7D1")
        case .fuel:          return Color(hex: "#FFA07A")
        case .bills:         return Color(hex: "#98D8C8")
        case .atm:           return Color(hex: "#7B68EE")
        case .travel:        return Color(hex: "#20B2AA")
        case .entertainment: return Color(hex: "#FFD700")
        case .health:        return Color(hex: "#FF69B4")
        case .education:     return Color(hex: "#87CEEB")
        case .groceries:     return Color(hex: "#90EE90")
        case .recharge:      return Color(hex: "#DDA0DD")
        case .emi:           return Color(hex: "#F0808A")
        case .investment:    return Color(hex: "#3CB371")
        case .salary:        return Color(hex: "#32CD32")
        case .others:        return Color(hex: "#A9A9A9")
        }
    }

    var keywords: [String] {
        switch self {
        case .food:
            return ["swiggy","zomato","dominos","pizza","burger","restaurant","cafe",
                    "food","dine","mcdonalds","kfc","subway","starbucks","biryani",
                    "dhaba","barbeque","dining","eatery","hotpot","haldiram"]
        case .shopping:
            return ["amazon","flipkart","myntra","ajio","meesho","nykaa","shoppers stop",
                    "westside","zara","lifestyle","reliance trends","snapdeal","tatacliq",
                    "lenskart","pepperfry","ikea","decathlon"]
        case .upi:
            return ["upi","gpay","phonepe","paytm","bhim","imps","neft","rtgs",
                    "transfer to","sent to","paid to","p2p","@ok","@ybl","@paytm"]
        case .fuel:
            return ["petrol","diesel","fuel","hp pump","iocl","bpcl","reliance petrol",
                    "shell","indian oil","hindustan petroleum","bharat petroleum","cng","hpcl"]
        case .bills:
            return ["electricity","water bill","broadband","internet","jio postpaid",
                    "airtel bill","vodafone","vi bill","bsnl","tata sky","dth","gas bill",
                    "piped gas","mahanagar gas","bescom","tneb","msedcl","utilities","postpaid"]
        case .atm:
            return ["atm","cash withdrawal","cash wtdl","atm wtdl","atm cash","cash dispense"]
        case .travel:
            return ["irctc","railway","uber","ola","rapido","auto fare","makemytrip",
                    "goibibo","yatra","cleartrip","flight","airport","metro","redbus",
                    "cab","bus ticket","train ticket"]
        case .entertainment:
            return ["netflix","amazon prime","hotstar","zee5","sony liv","disney","bookmyshow",
                    "pvr","inox","movie","theatre","spotify","youtube premium","gaming","steam"]
        case .health:
            return ["pharmacy","medical store","hospital","clinic","doctor","apollo pharmacy",
                    "1mg","netmeds","medplus","diagnostic","lab test","health","medicine","chemist"]
        case .education:
            return ["byju","unacademy","udemy","coursera","school fee","college fee",
                    "tuition","books","exam fee","coaching","course fee"]
        case .groceries:
            return ["bigbasket","grofers","blinkit","zepto","dmart","reliance fresh",
                    "more supermarket","supermarket","grocery","vegetables","fruits",
                    "kirana","provisions","daily needs"]
        case .recharge:
            return ["recharge","prepaid","talktime","data pack","top up","mobile recharge",
                    "dth recharge","fastag recharge"]
        case .emi:
            return ["emi","loan emi","installment","home loan","car loan","personal loan",
                    "bajaj finance","hdfc loan","emi paid","equated monthly"]
        case .investment:
            return ["mutual fund","sip","zerodha","groww","upstox","stocks","nse","bse",
                    "ipo","ppf","fixed deposit","fd maturity","recurring deposit","lic",
                    "insurance premium","dividend"]
        case .salary:
            return ["salary","payroll","wages","stipend","ctc","remuneration","salary credited"]
        case .others:
            return []
        }
    }
}

// MARK: - Transaction Model
struct Transaction: Identifiable, Codable, Equatable {
    var id:           UUID
    var date:         Date
    var amount:       Double
    var type:         TransactionType
    var category:     SpendCategory
    var merchant:     String
    var bankName:     String
    var smsBody:      String
    var accountLast4: String?
    var balance:      Double?
    var upiId:        String?
    var isManual:     Bool
    var note:         String?

    init(
        id:           UUID          = UUID(),
        date:         Date          = Date(),
        amount:       Double,
        type:         TransactionType,
        category:     SpendCategory  = .others,
        merchant:     String         = "Unknown",
        bankName:     String         = "Unknown",
        smsBody:      String         = "",
        accountLast4: String?        = nil,
        balance:      Double?        = nil,
        upiId:        String?        = nil,
        isManual:     Bool           = false,
        note:         String?        = nil
    ) {
        self.id           = id
        self.date         = date
        self.amount       = amount
        self.type         = type
        self.category     = category
        self.merchant     = merchant
        self.bankName     = bankName
        self.smsBody      = smsBody
        self.accountLast4 = accountLast4
        self.balance      = balance
        self.upiId        = upiId
        self.isManual     = isManual
        self.note         = note
    }

    var formattedAmount: String {
        "₹\(String(format: "%.2f", amount))"
    }
    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f.string(from: date)
    }
}
