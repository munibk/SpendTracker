import SwiftUI
import BackgroundTasks

@main
struct SpendTrackerApp: App {
    
    @StateObject private var store = TransactionStore()
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
        }
    }
    
    // MARK: - Background Tasks
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.spendtracker.sms.refresh",
            using: nil
        ) { task in
            self.handleBackgroundSMSRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundSMSRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        
        let operation = SMSRefreshOperation(
            smsService: smsService,
            store: store
        )
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        OperationQueue.main.addOperation(operation)
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.spendtracker.sms.refresh"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
        
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - Background Operation
class SMSRefreshOperation: Operation {
    private let smsService: SMSReaderService
    private let store: TransactionStore
    
    init(smsService: SMSReaderService, store: TransactionStore) {
        self.smsService = smsService
        self.store = store
    }
    
    override func main() {
        guard !isCancelled else { return }
        smsService.fetchNewMessages()
    }
}
