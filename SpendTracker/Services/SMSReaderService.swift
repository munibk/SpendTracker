import Foundation
import Combine
import UIKit

// MARK: - SMS Reader Service
class SMSReaderService: ObservableObject {

    @Published var isMonitoring:     Bool   = false
    @Published var lastSyncDate:     Date?
    @Published var permissionGranted: Bool  = false
    @Published var syncStatus:       String = "Not started"
    @Published var totalParsed:      Int    = 0

    private weak var store: TransactionStore?
    private let parser = SMSParserService.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private let lastMessageIDKey = "lastProcessedMessageID"

    func configure(store: TransactionStore) {
        self.store = store
    }

    // MARK: - Monitoring
    func startMonitoring() {
        isMonitoring = true
        syncStatus   = "Monitoring active"
        fetchNewMessages()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchNewMessages()
        }

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.fetchNewMessages() }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        syncStatus   = "Stopped"
    }

    // MARK: - Fetch
    // NOTE: iOS blocks direct SMS database access on non-jailbroken devices.
    // This method gracefully falls back to manual import when DB is unavailable.
    func fetchNewMessages() {
        syncStatus = "Ready — paste SMS to import"
        DispatchQueue.main.async {
            self.permissionGranted = false
            self.syncStatus = "Use + button to import SMS manually"
        }
    }

    // MARK: - Manual Import (primary method on standard iOS)
    func importManualSMS(_ text: String, sender: String = "BANK") -> Transaction? {
        guard let txn = parser.parse(smsBody: text, sender: sender) else { return nil }
        store?.addTransaction(txn)
        totalParsed += 1
        lastSyncDate = Date()
        syncStatus   = "✅ Imported: \(txn.merchant) ₹\(Int(txn.amount))"
        return txn
    }

    func bulkImport(messages: [(body: String, sender: String, date: Date)]) -> Int {
        var count = 0
        for msg in messages {
            if var txn = parser.parse(smsBody: msg.body, sender: msg.sender) {
                txn.date = msg.date
                store?.addTransaction(txn)
                count += 1
            }
        }
        if count > 0 {
            totalParsed  += count
            lastSyncDate  = Date()
            syncStatus    = "✅ Imported \(count) transactions"
            NotificationService.shared.sendNewTransactionsAlert(count: count)
        }
        return count
    }
}
