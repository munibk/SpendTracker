import SwiftUI
import BackgroundTasks

@main
struct SpendTrackerApp: App {

    @StateObject private var store      = TransactionStore()
    @StateObject private var smsService = SMSReaderService()

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

    // MARK: - URL Scheme Handler
    // Handles: spendtracker://import?sms=<encoded>
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "spendtracker" else { return }

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems  = components.queryItems else { return }

        let params = Dictionary(
            uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        // Get SMS body
        guard let smsBody = params["sms"]?.removingPercentEncoding,
              !smsBody.isEmpty else { return }

        let sender = params["sender"]?.removingPercentEncoding ?? "BANK"

        // Import the SMS
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = self.smsService.importManualSMS(smsBody, sender: sender)
        }
    }

    // MARK: - Background Tasks
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
        smsService.fetchNewMessages()
        task.setTaskCompleted(success: true)
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.spendtracker.sms.refresh"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
