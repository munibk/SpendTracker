import Foundation
import Combine

// MARK: - SMS Reader Service
/// Reads SMS messages from the Messages app database.
/// Note: On iOS, direct SMS database access requires private APIs.
/// This implementation uses the Messages framework approach and
/// prompts users to grant access via the Contacts & SMS entitlement.
class SMSReaderService: ObservableObject {
    
    @Published var isMonitoring: Bool = false
    @Published var lastSyncDate: Date?
    @Published var permissionGranted: Bool = false
    @Published var totalParsed: Int = 0
    @Published var syncStatus: String = "Not started"
    
    private weak var store: TransactionStore?
    private let parser = SMSParserService.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    
    // Messages.app sqlite database path (requires entitlement or jailbreak)
    // For non-jailbroken devices, we use a notification-based approach
    private let messagesDBPath = "\(NSHomeDirectory())/Library/SMS/sms.db"
    
    // UserDefaults key for last processed message ID
    private let lastMessageIDKey = "lastProcessedMessageID"
    
    func configure(store: TransactionStore) {
        self.store = store
    }
    
    // MARK: - Start Monitoring
    func startMonitoring() {
        isMonitoring = true
        syncStatus = "Monitoring active"
        
        // Initial fetch
        fetchNewMessages()
        
        // Poll every 5 minutes when app is foreground
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchNewMessages()
        }
        
        // Listen for app becoming active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.fetchNewMessages()
            }
            .store(in: &cancellables)
    }
    
    func stopMonitoring() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        syncStatus = "Stopped"
    }
    
    // MARK: - Fetch Messages
    func fetchNewMessages() {
        syncStatus = "Syncing..."
        
        // On standard iOS, we read via SQLite if entitlement is granted
        // Otherwise, fall back to manual import
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            if FileManager.default.fileExists(atPath: self.messagesDBPath) {
                self.readFromDatabase()
            } else {
                DispatchQueue.main.async {
                    self.syncStatus = "⚠️ Grant Full Disk Access or use Manual Import"
                    self.permissionGranted = false
                }
            }
        }
    }
    
    // MARK: - Read from SQLite DB
    private func readFromDatabase() {
        // Requires: com.apple.private.sms.read entitlement (private API)
        // For personal use / sideloaded apps with entitlement stripping workaround:
        
        guard let db = SQLiteDatabase(path: messagesDBPath) else {
            DispatchQueue.main.async {
                self.syncStatus = "Cannot open SMS database"
            }
            return
        }
        
        let lastID = UserDefaults.standard.integer(forKey: lastMessageIDKey)
        
        // Query bank messages newer than last processed
        let query = """
        SELECT m.ROWID, m.text, m.date, h.id as sender, m.is_from_me
        FROM message m
        JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.ROWID > \(lastID)
          AND m.is_from_me = 0
          AND (
            LOWER(h.id) LIKE '%bank%'
            OR LOWER(h.id) LIKE '%hdfc%'
            OR LOWER(h.id) LIKE '%sbi%'
            OR LOWER(h.id) LIKE '%icici%'
            OR LOWER(h.id) LIKE '%axis%'
            OR LOWER(h.id) LIKE '%kotak%'
            OR LOWER(m.text) LIKE '%debited%'
            OR LOWER(m.text) LIKE '%credited%'
            OR LOWER(m.text) LIKE '%spent%'
            OR LOWER(m.text) LIKE '%rs.%'
            OR LOWER(m.text) LIKE '%upi%'
          )
        ORDER BY m.ROWID ASC
        LIMIT 500
        """
        
        let rows = db.executeQuery(query)
        var maxID = lastID
        var newTransactions: [Transaction] = []
        
        for row in rows {
            guard let rowID = row["ROWID"] as? Int,
                  let text = row["text"] as? String,
                  let sender = row["sender"] as? String,
                  let appleDate = row["date"] as? Int64 else { continue }
            
            // Apple's timestamp is nanoseconds since 2001-01-01
            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(appleDate) / 1_000_000_000)
            
            if let transaction = parser.parse(smsBody: text, sender: sender) {
                var txn = transaction
                txn.date = date
                newTransactions.append(txn)
            }
            
            maxID = max(maxID, rowID)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !newTransactions.isEmpty {
                self.store?.addTransactions(newTransactions)
                self.totalParsed += newTransactions.count
                NotificationService.shared.sendNewTransactionsAlert(count: newTransactions.count)
            }
            
            UserDefaults.standard.set(maxID, forKey: self.lastMessageIDKey)
            self.lastSyncDate = Date()
            self.permissionGranted = true
            self.syncStatus = "✅ Synced \(newTransactions.count) new txns"
        }
    }
    
    // MARK: - Manual SMS Import
    /// User pastes SMS text manually — useful when DB access isn't available
    func importManualSMS(_ text: String, sender: String = "BANK") -> Transaction? {
        if let txn = parser.parse(smsBody: text, sender: sender) {
            store?.addTransaction(txn)
            return txn
        }
        return nil
    }
    
    // MARK: - Bulk Import from Text
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

// MARK: - Minimal SQLite Wrapper
class SQLiteDatabase {
    private var db: OpaquePointer?
    
    init?(path: String) {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(db)
            return nil
        }
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    func executeQuery(_ query: String) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return results
        }
        defer { sqlite3_finalize(statement) }
        
        let columnCount = sqlite3_column_count(statement)
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    row[columnName] = Int(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    }
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    break
                }
            }
            results.append(row)
        }
        return results
    }
}

// Add SQLite import at top of file in Xcode:
// import SQLite3
