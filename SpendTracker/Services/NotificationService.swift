import Foundation
import UserNotifications

// MARK: - Notification Service
class NotificationService {
    
    static let shared = NotificationService()
    private init() {}
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            print("Notification permission: \(granted)")
        }
    }
    
    func sendNewTransactionsAlert(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "💰 SpendTracker"
        content.body = "\(count) new transaction\(count > 1 ? "s" : "") detected from SMS"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "new_transactions_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendBudgetAlert(category: SpendCategory, utilized: Double, limit: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Budget Alert"
        content.body = "\(category.rawValue) is at \(Int(utilized * 100))% of ₹\(Int(limit)) budget"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "budget_\(category.rawValue)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendMonthlyReportReady(month: String, totalSpend: Double) {
        let content = UNMutableNotificationContent()
        content.title = "📊 Monthly Report Ready"
        content.body = "\(month) report: Total spend ₹\(Int(totalSpend))"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "monthly_report_\(month)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
