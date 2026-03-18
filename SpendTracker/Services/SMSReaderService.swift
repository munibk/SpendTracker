import Foundation
import Combine
import SQLite3
import UIKit

// MARK: - SMS Reader Service
class SMSReaderService: ObservableObject {

    @Published var isMonitoring: Bool = false
    @Published var lastSyncDate: Date?
    @Published var permissionGranted: Bool = false
    @Published var syncStatus: String = "Not started"
    @Published var totalParsed: Int = 0

    private weak var store: TransactionStore?
    private let parser = SMSParserService.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private let lastMessageIDKey = "lastProcessedMessageID"
    private let messagesDBPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Library/SMS/sms.db"
    }()

    func configure(store: TransactionStore) {
        self.store = store
    }

    // MARK: - Monitoring
    func startMonitoring() {
        isMonitoring = true
        syncStatus = "Monitoring active"
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
        syncStatus = "Stopped"
    }

    // MARK: - Fetch
    func fetchNewMessages() {
        syncStatus = "Syncing..."
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.messagesDBPath) {
                self.readFromDatabase()
            } else {
                DispatchQueue.main.async {
                    self.syncStatus = "Use Manual Import — tap + to paste SMS"
                    self.permissionGranted = false
                }
            }
        }
    }

    // MARK: - SQLite Read
    private func readFromDatabase() {
        guard let db = openDatabase() else {
            DispatchQueue.main.async { self.syncStatus = "Cannot open SMS database" }
            return
        }
        defer { sqlite3_close(db) }

        let lastID = UserDefaults.standard.integer(forKey: lastMessageIDKey)
        let query = """
            SELECT m.ROWID, m.text, m.date, h.id as sender
            FROM message m
            JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.ROWID > \(lastID)
              AND m.is_from_me = 0
              AND (
                LOWER(m.text) LIKE '%debited%' OR
                LOWER(m.text) LIKE '%credited%' OR
                LOWER(m.text) LIKE '%rs.%' OR
                LOWER(m.text) LIKE '%upi%' OR
                LOWER(m.text) LIKE '%atm%' OR
                LOWER(m.text) LIKE '%neft%' OR
                LOWER(m.text) LIKE '%imps%'
              )
            ORDER BY m.ROWID ASC LIMIT 500
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        var maxID = lastID
        var newTransactions: [Transaction] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID   = Int(sqlite3_column_int64(statement, 0))
            let text    = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let appleTs = sqlite3_column_int64(statement, 2)
            let sender  = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""

            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(appleTs) / 1_000_000_000)

            if var txn = parser.parse(smsBody: text, sender: sender) {
                txn.date = date
                newTransactions.append(txn)
            }
            maxID = max(maxID, rowID)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !newTransactions.isEmpty {
                self.store?.addTransactions(newTransactions)
                self.totalParsed += newTransactions.count
                NotificationService.shared.sendNewTransactionsAlert(count: newTransactions.count)
            }
            UserDefaults.standard.set(maxID, forKey: self.lastMessageIDKey)
            self.lastSyncDate = Date()
            self.permissionGranted = true
            self.syncStatus = newTransactions.isEmpty
                ? "✅ Up to date"
                : "✅ Imported \(newTransactions.count) transactions"
        }
    }

    private func openDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(messagesDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    // MARK: - Manual Import
    func importManualSMS(_ text: String, sender: String = "BANK") -> Transaction? {
        guard let txn = parser.parse(smsBody: text, sender: sender) else { return nil }
        store?.addTransaction(txn)
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
        return count
    }
}
