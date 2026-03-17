import SwiftUI

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Date Helpers
extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }
    var endOfMonth: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth)!
    }
    var monthYearString: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: self)
    }
    var shortMonthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMM yy"; return f.string(from: self)
    }
}

// MARK: - Number Formatting
extension Double {
    var inrFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "₹\(Int(self))"
    }
    var inrFormattedWithDecimal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "₹\(self)"
    }
    var shortened: String {
        if self >= 100_000 { return "₹\(String(format: "%.1f", self/100_000))L" }
        if self >= 1_000 { return "₹\(String(format: "%.1f", self/1_000))K" }
        return "₹\(Int(self))"
    }
}
