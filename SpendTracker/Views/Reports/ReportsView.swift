import SwiftUI
import PDFKit

// MARK: - Reports View
struct ReportsView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    
    private var report: MonthlyReport {
        store.generateReport(for: selectedMonth)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Month selector
                    monthSelector
                    
                    // Overview cards
                    overviewSection
                    
                    // Category breakdown table
                    categoryTable
                    
                    // Top merchants
                    topMerchantsSection
                    
                    // Daily heatmap
                    dailyHeatmap
                    
                    // Export buttons
                    exportSection
                }
                .padding()
            }
            .navigationTitle("Monthly Report")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: generateAndSharePDF) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    // MARK: - Month Selector
    private var monthSelector: some View {
        HStack {
            Button(action: { moveMonth(-1) }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#6C63FF"))
            }
            Spacer()
            VStack {
                Text(report.monthName)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Monthly Report")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { moveMonth(1) }) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(Calendar.current.isDateInThisMonth(selectedMonth) ? .gray : Color(hex: "#6C63FF"))
            }
            .disabled(Calendar.current.isDateInThisMonth(selectedMonth))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color(hex: "#6C63FF"), Color(hex: "#4ECDC4")],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        )
        .colorScheme(.dark)
    }
    
    // MARK: - Overview
    private var overviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ReportCard(title: "Total Spend", value: "₹\(Int(report.totalSpend))", icon: "arrow.up.circle.fill", color: .red)
                ReportCard(title: "Income", value: "₹\(Int(report.totalCredit))", icon: "arrow.down.circle.fill", color: .green)
            }
            HStack(spacing: 12) {
                ReportCard(
                    title: "Net Savings",
                    value: report.netBalance >= 0 ? "+₹\(Int(report.netBalance))" : "-₹\(Int(abs(report.netBalance)))",
                    icon: "banknote.fill",
                    color: report.netBalance >= 0 ? .blue : .red
                )
                ReportCard(
                    title: "Transactions",
                    value: "\(report.transactions.count)",
                    icon: "list.number",
                    color: .purple
                )
            }
            HStack(spacing: 12) {
                ReportCard(
                    title: "Avg Daily Spend",
                    value: "₹\(Int(report.averageDailySpend))",
                    icon: "calendar.circle.fill",
                    color: .orange
                )
                if let top = report.topCategory {
                    ReportCard(
                        title: "Top Category",
                        value: top.rawValue,
                        icon: top.icon,
                        color: top.color
                    )
                }
            }
        }
    }
    
    // MARK: - Category Table
    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Breakdown")
                .font(.headline)
            
            let sorted = report.categoryBreakdown.sorted { $0.value > $1.value }
            
            if sorted.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Category").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("Amount").font(.caption).foregroundColor(.secondary)
                        Text("  Share").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    Divider()
                    
                    ForEach(sorted, id: \.key) { cat, amount in
                        HStack {
                            Image(systemName: cat.icon)
                                .foregroundColor(cat.color)
                                .frame(width: 20)
                            Text(cat.rawValue)
                                .font(.subheadline)
                            Spacer()
                            Text("₹\(amount.formatted(.number.precision(.fractionLength(0))))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(Int(amount / max(report.totalSpend, 1) * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        
                        if cat.rawValue != sorted.last?.key.rawValue {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    // MARK: - Top Merchants
    private var topMerchantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.headline)
            
            if report.topMerchants.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                ForEach(Array(report.topMerchants.enumerated()), id: \.offset) { idx, merchant in
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#6C63FF").opacity(0.15))
                                .frame(width: 32, height: 32)
                            Text("\(idx + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color(hex: "#6C63FF"))
                        }
                        Text(merchant.name)
                            .font(.subheadline)
                        Spacer()
                        Text("₹\(Int(merchant.amount))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    // MARK: - Daily Heatmap
    private var dailyHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Activity")
                .font(.headline)
            
            let maxSpend = report.dailySpend.values.max() ?? 1
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let spend = report.dailySpend[day] ?? 0
                    let intensity = spend / maxSpend
                    
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(spend > 0 ? Color(hex: "#6C63FF").opacity(0.2 + intensity * 0.8) : Color.gray.opacity(0.1))
                            .frame(height: 32)
                            .overlay(
                                Text("\(day)")
                                    .font(.system(size: 9))
                                    .foregroundColor(intensity > 0.5 ? .white : .secondary)
                            )
                        if spend > 0 {
                            Text("₹\(Int(spend/1000))k")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    // MARK: - Export
    private var exportSection: some View {
        VStack(spacing: 12) {
            Button(action: generateAndSharePDF) {
                Label("Export as PDF", systemImage: "doc.richtext.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#6C63FF"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button(action: exportCSV) {
                Label("Export as CSV", systemImage: "tablecells.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Helpers
    private func moveMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func generateAndSharePDF() {
        let pdfGenerator = PDFReportGenerator()
        if let url = pdfGenerator.generateReport(report) {
            pdfURL = url
            showShareSheet = true
        }
    }
    
    private func exportCSV() {
        let csv = store.exportCSV(month: selectedMonth)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(report.monthName)_SpendTracker.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        pdfURL = url
        showShareSheet = true
    }
}

// MARK: - Report Card
struct ReportCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PDF Report Generator
class PDFReportGenerator {
    
    func generateReport(_ report: MonthlyReport) -> URL? {
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 40
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
        UIGraphicsBeginPDFPage()
        
        var yPos: CGFloat = margin
        
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor(hex: "#6C63FF")
        ]
        "SpendTracker — Monthly Report".draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
        yPos += 35
        
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.gray
        ]
        report.monthName.draw(at: CGPoint(x: margin, y: yPos), withAttributes: subtitleAttrs)
        yPos += 30
        
        // Summary line
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ]
        let line1 = "Total Spend: ₹\(Int(report.totalSpend))   |   Income: ₹\(Int(report.totalCredit))   |   Savings: ₹\(Int(max(report.netBalance, 0)))"
        line1.draw(at: CGPoint(x: margin, y: yPos), withAttributes: lineAttrs)
        yPos += 20
        
        let line2 = "Transactions: \(report.transactions.count)   |   Avg Daily: ₹\(Int(report.averageDailySpend))"
        line2.draw(at: CGPoint(x: margin, y: yPos), withAttributes: lineAttrs)
        yPos += 30
        
        // Separator
        UIColor.lightGray.setStroke()
        UIBezierPath(rect: CGRect(x: margin, y: yPos, width: pageWidth - 2 * margin, height: 1)).fill()
        yPos += 16
        
        // Category breakdown header
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        "Category Breakdown".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
        yPos += 24
        
        let sorted = report.categoryBreakdown.sorted { $0.value > $1.value }
        let rowAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
        
        for (cat, amount) in sorted {
            if yPos > pageHeight - 60 {
                UIGraphicsBeginPDFPage()
                yPos = margin
            }
            
            let pct = Int(amount / max(report.totalSpend, 1) * 100)
            let rowText = "  \(cat.rawValue)"
            let amtText = "₹\(amount.formatted(.number.precision(.fractionLength(0))))  (\(pct)%)"
            rowText.draw(at: CGPoint(x: margin, y: yPos), withAttributes: rowAttrs)
            amtText.draw(at: CGPoint(x: pageWidth - margin - 120, y: yPos), withAttributes: rowAttrs)
            yPos += 18
        }
        
        yPos += 20
        
        // Top merchants
        "Top Merchants".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
        yPos += 24
        
        for (idx, merchant) in report.topMerchants.enumerated() {
            if yPos > pageHeight - 60 {
                UIGraphicsBeginPDFPage()
                yPos = margin
            }
            let text = "\(idx + 1). \(merchant.name)"
            let amt = "₹\(Int(merchant.amount))"
            text.draw(at: CGPoint(x: margin, y: yPos), withAttributes: rowAttrs)
            amt.draw(at: CGPoint(x: pageWidth - margin - 80, y: yPos), withAttributes: rowAttrs)
            yPos += 18
        }
        
        // Footer
        yPos = pageHeight - 30
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.lightGray
        ]
        "Generated by SpendTracker • \(Date().formatted(date: .abbreviated, time: .shortened))".draw(
            at: CGPoint(x: margin, y: yPos), withAttributes: footerAttrs
        )
        
        UIGraphicsEndPDFContext()
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(report.monthName.replacingOccurrences(of: " ", with: "_"))_Report.pdf")
        
        pdfData.write(to: url, atomically: true)
        return url
    }
}

// UIColor hex extension
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
