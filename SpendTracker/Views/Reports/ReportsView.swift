import SwiftUI

// MARK: - Reports View
struct ReportsView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    private var report: MonthlyReport {
        store.generateReport(for: selectedMonth)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    overviewCards
                    categoryTable
                    topMerchantsCard
                    dailyHeatmapCard
                    exportButtons
                }
                .padding()
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
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
            VStack(spacing: 2) {
                Text(report.monthName)
                    .font(.title3).fontWeight(.bold)
                Text("Monthly Report")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { moveMonth(1) }) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(
                        Calendar.current.isDateInThisMonth(selectedMonth)
                        ? Color.gray
                        : Color(hex: "#6C63FF")
                    )
            }
            .disabled(Calendar.current.isDateInThisMonth(selectedMonth))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    // MARK: - Overview Cards
    private var overviewCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ReportCard(
                    title: "Total Spend",
                    value: "₹\(Int(report.totalSpend))",
                    icon: "arrow.up.circle.fill",
                    color: .red
                )
                ReportCard(
                    title: "Income",
                    value: "₹\(Int(report.totalCredit))",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
            }
            HStack(spacing: 10) {
                ReportCard(
                    title: "Net Savings",
                    value: report.netBalance >= 0
                        ? "+₹\(Int(report.netBalance))"
                        : "-₹\(Int(abs(report.netBalance)))",
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
            HStack(spacing: 10) {
                ReportCard(
                    title: "Avg Daily",
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
                } else {
                    ReportCard(
                        title: "Top Category",
                        value: "None",
                        icon: "questionmark.circle",
                        color: .gray
                    )
                }
            }
        }
    }

    // MARK: - Category Table
    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)

            let sorted = report.categoryBreakdown
                .sorted { $0.value > $1.value }

            if sorted.isEmpty {
                Text("No spending data this month")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Category").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("Amount").font(.caption).foregroundColor(.secondary)
                        Text("  %").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    ForEach(Array(sorted.enumerated()), id: \.element.key) { idx, item in
                        HStack(spacing: 10) {
                            Image(systemName: item.key.icon)
                                .foregroundColor(item.key.color)
                                .frame(width: 20)
                            Text(item.key.rawValue)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text("₹\(Int(item.value))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(Int(item.value / max(report.totalSpend, 1) * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        if idx < sorted.count - 1 {
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
        .shadow(color: .black.opacity(0.05), radius: 6)
    }

    // MARK: - Top Merchants
    private var topMerchantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.headline)

            if report.topMerchants.isEmpty {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(report.topMerchants.enumerated()), id: \.offset) { idx, merchant in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#6C63FF").opacity(0.15))
                                .frame(width: 32, height: 32)
                            Text("\(idx + 1)")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(Color(hex: "#6C63FF"))
                        }
                        Text(merchant.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("₹\(Int(merchant.amount))")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)

                    if idx < report.topMerchants.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }

    // MARK: - Daily Heatmap
    private var dailyHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Activity")
                .font(.headline)

            let maxSpend = report.dailySpend.values.max() ?? 1
            let daysInMonth = Calendar.current.range(
                of: .day, in: .month, for: selectedMonth
            )?.count ?? 30

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let spend = report.dailySpend[day] ?? 0
                    let intensity = spend / maxSpend

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                spend > 0
                                ? Color(hex: "#6C63FF").opacity(0.2 + intensity * 0.8)
                                : Color.gray.opacity(0.1)
                            )
                            .frame(height: 32)
                            .overlay(
                                Text("\(day)")
                                    .font(.system(size: 9))
                                    .foregroundColor(
                                        intensity > 0.5 ? .white : .secondary
                                    )
                            )
                    }
                }
            }

            // Legend
            HStack {
                Text("Less").font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 3) {
                    ForEach([0.1, 0.3, 0.5, 0.7, 0.9], id: \.self) { opacity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#6C63FF").opacity(opacity))
                            .frame(width: 12, height: 12)
                    }
                }
                Text("More").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }

    // MARK: - Export Buttons
    private var exportButtons: some View {
        VStack(spacing: 10) {
            Button(action: exportPDF) {
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
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Helpers
    private func moveMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = d
        }
    }

    private func exportPDF() {
        let generator = PDFReportGenerator()
        if let url = generator.generateReport(report) {
            exportURL = url
            showShareSheet = true
        }
    }

    private func exportCSV() {
        let csv = store.exportCSV(month: selectedMonth)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(report.monthName.replacingOccurrences(of: " ", with: "_"))_SpendTracker.csv"
            )
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        showShareSheet = true
    }
}

// MARK: - Report Card
struct ReportCard: View {
    let title: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
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

// MARK: - PDF Generator
class PDFReportGenerator {

    func generateReport(_ report: MonthlyReport) -> URL? {
        let pageW: CGFloat = 595.2
        let pageH: CGFloat = 841.8
        let margin: CGFloat = 40

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(
            data,
            CGRect(x: 0, y: 0, width: pageW, height: pageH),
            nil
        )
        UIGraphicsBeginPDFPage()

        var y: CGFloat = margin

        // Title
        draw("SpendTracker — Monthly Report",
             at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 22, weight: .bold),
             color: UIColor(hex: "#6C63FF"))
        y += 32

        draw(report.monthName,
             at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 14),
             color: .gray)
        y += 28

        // Divider
        drawLine(x: margin, y: y, width: pageW - 2 * margin)
        y += 16

        // Summary
        let summaryLines = [
            "Total Spend : ₹\(Int(report.totalSpend))",
            "Income      : ₹\(Int(report.totalCredit))",
            "Savings     : ₹\(Int(max(report.netBalance, 0)))",
            "Transactions: \(report.transactions.count)",
            "Avg Daily   : ₹\(Int(report.averageDailySpend))"
        ]
        for line in summaryLines {
            draw(line, at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 12), color: .darkGray)
            y += 18
        }
        y += 10

        drawLine(x: margin, y: y, width: pageW - 2 * margin)
        y += 16

        // Category Breakdown
        draw("Category Breakdown",
             at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 14, weight: .semibold),
             color: .black)
        y += 22

        let sorted = report.categoryBreakdown.sorted { $0.value > $1.value }
        for (cat, amount) in sorted {
            if y > pageH - 60 { newPage(&y, margin: margin) }
            let pct = Int(amount / max(report.totalSpend, 1) * 100)
            draw("  \(cat.rawValue)",
                 at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 11), color: .darkGray)
            draw("₹\(Int(amount))  (\(pct)%)",
                 at: CGPoint(x: pageW - margin - 120, y: y),
                 font: .systemFont(ofSize: 11), color: .darkGray)
            y += 18
        }
        y += 14

        // Top Merchants
        if y > pageH - 100 { newPage(&y, margin: margin) }
        draw("Top Merchants",
             at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 14, weight: .semibold),
             color: .black)
        y += 22

        for (idx, merchant) in report.topMerchants.enumerated() {
            if y > pageH - 60 { newPage(&y, margin: margin) }
            draw("\(idx + 1). \(merchant.name)",
                 at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 11), color: .darkGray)
            draw("₹\(Int(merchant.amount))",
                 at: CGPoint(x: pageW - margin - 80, y: y),
                 font: .systemFont(ofSize: 11), color: .darkGray)
            y += 18
        }

        // Footer
        let footerY = pageH - 28
        draw("Generated by SpendTracker • \(Date().formatted(date: .abbreviated, time: .shortened))",
             at: CGPoint(x: margin, y: footerY),
             font: .systemFont(ofSize: 9), color: .lightGray)

        UIGraphicsEndPDFContext()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(report.monthName.replacingOccurrences(of: " ", with: "_"))_Report.pdf"
            )
        data.write(to: url, atomically: true)
        return url
    }

    private func draw(_ text: String,
                      at point: CGPoint,
                      font: UIFont,
                      color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    private func drawLine(x: CGFloat, y: CGFloat, width: CGFloat) {
        UIColor.lightGray.setFill()
        UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: 0.5)).fill()
    }

    private func newPage(_ y: inout CGFloat, margin: CGFloat) {
        UIGraphicsBeginPDFPage()
        y = margin
    }
}
