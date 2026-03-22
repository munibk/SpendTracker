import SwiftUI
import BackgroundTasks

@main
struct SpendTrackerApp: App {

    @StateObject private var store      = TransactionStore()
    @StateObject private var smsService = SMSReaderService()
    @StateObject private var gmail      = GmailService.shared

    init() {
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(smsService)
                .onAppear {
                    smsService.configure(store: store)
                    smsService.startMonitoring()
                    scheduleBackgroundRefresh()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: URL Handler
    // Handles:
    //   spendtracker://import?sms=<encoded>   ← Shortcuts SMS
    //   com.yourname.spendtracker:/oauth2callback?code=<code> ← Gmail OAuth
    // ─────────────────────────────────────────────────────────
    private func handleIncomingURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""

        // Gmail OAuth callback
        if scheme == "com.yourname.spendtracker" {
            gmail.handleCallback(url: url)
            return
        }

        // SMS import via Shortcuts
        if scheme == "spendtracker" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems  = components.queryItems else { return }

            let params = Dictionary(uniqueKeysWithValues:
                queryItems.compactMap { item -> (String, String)? in
                    guard let v = item.value else { return nil }
                    return (item.name, v)
                })

            guard let smsBody = params["sms"]?.removingPercentEncoding,
                  !smsBody.isEmpty else { return }

            let sender = params["sender"]?.removingPercentEncoding ?? "BANK"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = self.smsService.importManualSMS(smsBody, sender: sender)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Background Tasks
    // ─────────────────────────────────────────────────────────
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.spendtracker.sms.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleBackgroundRefresh(task: refreshTask)
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // Auto fetch Gmail in background
        gmail.fetchBankEmails(store: store) { _ in
            task.setTaskCompleted(success: true)
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.spendtracker.sms.refresh"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
