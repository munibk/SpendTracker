import SwiftUI

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var store:      TransactionStore
    @EnvironmentObject var smsService: SMSReaderService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.pie.fill")
                }
                .tag(0)

            TransactionsListView()
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle.fill")
                }
                .tag(1)

            ChartsView()
                .tabItem {
                    Label("Charts", systemImage: "chart.bar.xaxis")
                }
                .tag(2)

            GmailView()
                .tabItem {
                    Label("Gmail", systemImage: "envelope.fill")
                }
                .tag(3)

            ReportsView()
                .tabItem {
                    Label("Reports", systemImage: "doc.text.fill")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(5)
        }
        .accentColor(Color(hex: "#6C63FF"))
        .onAppear {
            NotificationService.shared.requestPermission()
        }
    }
}
