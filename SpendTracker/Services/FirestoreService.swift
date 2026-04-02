import Foundation

// MARK: - Firestore Service
// Uses Firebase Firestore REST API — no SDK / CocoaPods / SPM required.
//
// Setup (one-time, in Firebase Console):
//   1. Create a Firebase project at console.firebase.google.com
//   2. Add an iOS app with bundle ID com.yourname.spendtracker
//   3. Enable Firestore (in Native mode)
//   4. Set Firestore rules:
//        rules_version = '2';
//        service cloud.firestore {
//          match /databases/{database}/documents {
//            match /users/{uid}/{document=**} {
//              allow read, write: if request.auth != null && request.auth.uid == uid;
//            }
//          }
//        }
//   5. Get your Web API Key from Project Settings → General
//   6. Enter it in the app Settings screen (saved to UserDefaults "firestore_api_key")
//   7. Get your Project ID from Project Settings → General
//   8. Enter it in the app Settings screen (saved to UserDefaults "firestore_project_id")
//
// Data structure:
//   users/{uid}/transactions/{txnId}   ← Transaction documents
//   users/{uid}/budgets/data           ← Single budget document
//
// The Firebase UID is acquired by exchanging the Google id_token
// for a Firebase ID token via the identitytoolkit REST API.

class FirestoreService: ObservableObject {

    static let shared = FirestoreService()

    // ── Config — set by the user in Settings ──────────────
    var projectID: String {
        UserDefaults.standard.string(forKey: "firestore_project_id") ?? ""
    }
    var apiKey: String {
        UserDefaults.standard.string(forKey: "firestore_api_key") ?? ""
    }

    // ── Firebase Auth state ────────────────────────────────
    @Published var isConfigured: Bool = false
    private(set) var firebaseUID: String?
    private var firebaseIDToken: String?
    private var firebaseTokenExpiry: Date?

    // ── In-app debug log (last 50 entries) ────────────────
    @Published var debugLogs: [String] = []
    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(ts)] \(msg)"
        print(entry)
        DispatchQueue.main.async {
            self.debugLogs.insert(entry, at: 0)
            if self.debugLogs.count > 50 { self.debugLogs = Array(self.debugLogs.prefix(50)) }
        }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    private init() {
        firebaseUID    = UserDefaults.standard.string(forKey: "firebase_uid")
        firebaseIDToken = AppKeychain.read("firebase_id_token")
        if let exp = UserDefaults.standard.object(forKey: "firebase_token_expiry") as? Date {
            firebaseTokenExpiry = exp
        }
        isConfigured = !projectID.isEmpty && !apiKey.isEmpty && firebaseUID != nil
        log(isConfigured ? "Init: configured (uid=\(firebaseUID ?? ""))" : "Init: not configured (projectID=\(projectID.isEmpty ? "missing" : "ok"), apiKey=\(apiKey.isEmpty ? "missing" : "ok"), uid=\(firebaseUID == nil ? "missing" : "ok"))")
    }

    // ─────────────────────────────────────────────────────
    // MARK: Firebase Auth — sign in with Google id_token
    // ─────────────────────────────────────────────────────
    func signInWithGoogle(idToken: String, completion: @escaping (Bool) -> Void) {
        guard !apiKey.isEmpty else { log("signInWithGoogle: ❌ apiKey missing"); completion(false); return }

        let url = URL(string:
            "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "postBody":           "id_token=\(idToken)&providerId=google.com",
            "requestUri":         "https://\(projectID).firebaseapp.com",
            "returnIdpCredential": true,
            "returnSecureToken":  true,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        log("signInWithGoogle: calling identitytoolkit…")
        session.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                self.log("signInWithGoogle: ❌ network error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }; return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.log("signInWithGoogle: ❌ no data / bad JSON")
                DispatchQueue.main.async { completion(false) }; return
            }
            if let errMsg = (json["error"] as? [String: Any])?["message"] as? String {
                self.log("signInWithGoogle: ❌ Firebase error: \(errMsg)")
                DispatchQueue.main.async { completion(false) }; return
            }
            guard let uid  = json["localId"]   as? String,
                  let idt  = json["idToken"]   as? String,
                  let exp  = json["expiresIn"] as? String,
                  let secs = Double(exp)
            else {
                self.log("signInWithGoogle: ❌ missing fields in response: \(json.keys.joined(separator:","))")
                DispatchQueue.main.async { completion(false) }; return
            }

            let expiry = Date().addingTimeInterval(secs - 60)
            self.firebaseUID          = uid
            self.firebaseIDToken      = idt
            self.firebaseTokenExpiry  = expiry

            UserDefaults.standard.set(uid,    forKey: "firebase_uid")
            UserDefaults.standard.set(expiry, forKey: "firebase_token_expiry")
            AppKeychain.save(idt, key: "firebase_id_token")
            self.log("signInWithGoogle: ✅ signed in, uid=\(uid)")

            DispatchQueue.main.async {
                self.isConfigured = true
                completion(true)
            }
        }.resume()
    }

    // ── Refresh Firebase token using a Google refresh_token ──
    func refreshFirebaseToken(googleRefreshToken: String, completion: @escaping (Bool) -> Void) {
        guard !apiKey.isEmpty else { completion(false); return }

        let url = URL(string:
            "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(googleRefreshToken)"
            .data(using: .utf8)

        session.dataTask(with: req) { [weak self] data, _, error in
            guard let self, let data, error == nil,
                  let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idt    = json["id_token"] as? String,
                  let expStr = json["expires_in"] as? String,
                  let secs   = Double(expStr)
            else { DispatchQueue.main.async { completion(false) }; return }

            let expiry = Date().addingTimeInterval(secs - 60)
            self.firebaseIDToken     = idt
            self.firebaseTokenExpiry = expiry
            UserDefaults.standard.set(expiry, forKey: "firebase_token_expiry")
            AppKeychain.save(idt, key: "firebase_id_token")

            DispatchQueue.main.async { completion(true) }
        }.resume()
    }

    // ── Ensures we have a valid token before every request ──
    func validFirebaseToken(completion: @escaping (String?) -> Void) {
        if let expiry = firebaseTokenExpiry,
           Date() < expiry,
           let token = firebaseIDToken {
            completion(token); return
        }
        log("validFirebaseToken: token expired, refreshing…")
        guard let googleRefresh = AppKeychain.read("refresh_token") else {
            log("validFirebaseToken: ❌ no Google refresh_token in Keychain")
            completion(nil); return
        }
        refreshFirebaseToken(googleRefreshToken: googleRefresh) { [weak self] success in
            completion(success ? self?.firebaseIDToken : nil)
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Transactions
    // ─────────────────────────────────────────────────────

    // Save or overwrite a single transaction
    func saveTransaction(_ txn: Transaction) {
        guard let uid = firebaseUID, !projectID.isEmpty else {
            log("saveTransaction: ❌ skipped (uid=\(firebaseUID == nil ? "nil" : "ok"), projectID=\(projectID.isEmpty ? "missing" : "ok"))")
            return
        }
        validFirebaseToken { [weak self] token in
            guard let self, let token else {
                self?.log("saveTransaction: ❌ no valid Firebase token")
                return
            }
            let docID = txn.id.uuidString
            let url   = self.docURL("users/\(uid)/transactions/\(docID)")
            var req   = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: self.firestoreDoc(from: txn))
            self.session.dataTask(with: req) { [weak self] data, resp, error in
                if let error {
                    self?.log("saveTransaction: ❌ \(error.localizedDescription)")
                } else if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self?.log("saveTransaction: ❌ HTTP \(http.statusCode) — \(body.prefix(120))")
                } else {
                    self?.log("saveTransaction: ✅ \(txn.merchant) ₹\(txn.amount)")
                }
            }.resume()
        }
    }

    // Delete a transaction
    func deleteTransaction(id: UUID) {
        guard let uid = firebaseUID, !projectID.isEmpty else { return }
        validFirebaseToken { [weak self] token in
            guard let self, let token else { return }
            let url = self.docURL("users/\(uid)/transactions/\(id.uuidString)")
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            self.session.dataTask(with: req) { _, _, error in
                if let error { print("Firestore delete error: \(error)") }
            }.resume()
        }
    }

    // Fetch all transactions (called on first launch / new device)
    func fetchAllTransactions(completion: @escaping ([Transaction]) -> Void) {
        guard let uid = firebaseUID, !projectID.isEmpty else {
            log("fetchAllTransactions: ❌ skipped — not configured")
            completion([]); return
        }
        log("fetchAllTransactions: fetching…")
        validFirebaseToken { [weak self] token in
            guard let self, let token else {
                self?.log("fetchAllTransactions: ❌ no valid token")
                completion([]); return
            }
            let url = self.collectionURL("users/\(uid)/transactions")
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            self.session.dataTask(with: req) { [weak self] data, resp, error in
                guard let self else { return }
                if let error {
                    self.log("fetchAllTransactions: ❌ \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }; return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    self.log("fetchAllTransactions: ❌ bad response")
                    DispatchQueue.main.async { completion([]) }; return
                }
                if let errMsg = (json["error"] as? [String: Any])?["message"] as? String {
                    self.log("fetchAllTransactions: ❌ \(errMsg)")
                    DispatchQueue.main.async { completion([]) }; return
                }
                let docs = json["documents"] as? [[String: Any]] ?? []
                let txns = docs.compactMap { self.transaction(from: $0) }
                self.log("fetchAllTransactions: ✅ got \(txns.count) transactions")
                DispatchQueue.main.async { completion(txns) }
            }.resume()
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Budgets
    // ─────────────────────────────────────────────────────

    func saveBudgets(_ budgets: [SpendCategory: Double]) {
        guard let uid = firebaseUID, !projectID.isEmpty else { return }
        validFirebaseToken { [weak self] token in
            guard let self, let token else { return }
            let rawBudgets = Dictionary(uniqueKeysWithValues:
                budgets.map { ($0.key.rawValue, $0.value) })
            var fields: [String: Any] = [:]
            for (k, v) in rawBudgets { fields[k] = ["doubleValue": v] }
            let body: [String: Any] = ["fields": fields]

            let url = self.docURL("users/\(uid)/budgets/data")
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            self.session.dataTask(with: req) { _, _, error in
                if let error { print("Firestore budgets save error: \(error)") }
            }.resume()
        }
    }

    func fetchBudgets(completion: @escaping ([SpendCategory: Double]) -> Void) {
        guard let uid = firebaseUID, !projectID.isEmpty else { completion([:]); return }
        validFirebaseToken { [weak self] token in
            guard let self, let token else { completion([:]); return }
            let url = self.docURL("users/\(uid)/budgets/data")
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            self.session.dataTask(with: req) { [weak self] data, resp, error in
                guard let data, error == nil,
                      let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let fields = json["fields"] as? [String: Any]
                else { DispatchQueue.main.async { completion([:]); }; return }
                var budgets: [SpendCategory: Double] = [:]
                for (k, v) in fields {
                    guard let cat = SpendCategory(rawValue: k),
                          let dv  = (v as? [String: Any])?["doubleValue"] as? Double
                    else { continue }
                    budgets[cat] = dv
                }
                DispatchQueue.main.async { completion(budgets) }
            }.resume()
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Clear all remote data
    // ─────────────────────────────────────────────────────
    func clearAllRemoteData() {
        guard let uid = firebaseUID else { return }
        // Fetch all IDs then delete each — Firestore REST has no bulk delete
        fetchAllTransactions { [weak self] txns in
            txns.forEach { self?.deleteTransaction(id: $0.id) }
        }
        _ = uid  // budgets doc is tiny, just leave it
    }

    // ─────────────────────────────────────────────────────
    // MARK: Sign Out
    // ─────────────────────────────────────────────────────
    func signOut() {
        firebaseUID         = nil
        firebaseIDToken     = nil
        firebaseTokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: "firebase_uid")
        UserDefaults.standard.removeObject(forKey: "firebase_token_expiry")
        AppKeychain.delete("firebase_id_token")
        DispatchQueue.main.async { self.isConfigured = false }
    }

    // ─────────────────────────────────────────────────────
    // MARK: URL helpers
    // ─────────────────────────────────────────────────────
    private func docURL(_ path: String) -> URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/\(path)")!
    }

    private func collectionURL(_ path: String) -> URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/\(path)?pageSize=1000")!
    }

    // ─────────────────────────────────────────────────────
    // MARK: Firestore ↔ Transaction conversion
    // ─────────────────────────────────────────────────────

    // Encode a Transaction into Firestore's REST field format
    private func firestoreDoc(from txn: Transaction) -> [String: Any] {
        var fields: [String: Any] = [
            "id":         ["stringValue": txn.id.uuidString],
            "amount":     ["doubleValue": txn.amount],
            "type":       ["stringValue": txn.type.rawValue],
            "category":   ["stringValue": txn.category.rawValue],
            "merchant":   ["stringValue": txn.merchant],
            "bankName":   ["stringValue": txn.bankName],
            "date":       ["timestampValue": ISO8601DateFormatter().string(from: txn.date)],
            "isManual":   ["booleanValue": txn.isManual],
            "cardType":   ["stringValue": txn.cardType.rawValue],
        ]
        if let a  = txn.accountLast4 { fields["accountLast4"] = ["stringValue": a] }
        if let b  = txn.balance      { fields["balance"]      = ["doubleValue": b] }
        if let u  = txn.upiId        { fields["upiId"]        = ["stringValue": u] }
        if let n  = txn.note         { fields["note"]         = ["stringValue": n] }
        return ["fields": fields]
    }

    // Decode a Firestore document into a Transaction
    private func transaction(from doc: [String: Any]) -> Transaction? {
        guard let fields = doc["fields"] as? [String: Any] else { return nil }

        func str(_ key: String)    -> String? { (fields[key] as? [String: Any])?["stringValue"] as? String }
        func dbl(_ key: String)    -> Double? { (fields[key] as? [String: Any])?["doubleValue"] as? Double }
        func bool_(_ key: String)  -> Bool    { (fields[key] as? [String: Any])?["booleanValue"] as? Bool ?? false }
        func ts(_ key: String)     -> Date?   {
            guard let s = (fields[key] as? [String: Any])?["timestampValue"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: s)
        }

        guard let idStr     = str("id"),
              let id        = UUID(uuidString: idStr),
              let amount    = dbl("amount"),
              let typeStr   = str("type"),
              let txType    = TransactionType(rawValue: typeStr),
              let catStr    = str("category"),
              let category  = SpendCategory(rawValue: catStr),
              let merchant  = str("merchant"),
              let bankName  = str("bankName"),
              let date      = ts("date")
        else { return nil }

        let cardType = CardType(rawValue: str("cardType") ?? "") ?? .none

        return Transaction(
            id:            id,
            date:          date,
            amount:        amount,
            type:          txType,
            category:      category,
            merchant:      merchant,
            bankName:      bankName,
            accountLast4:  str("accountLast4"),
            balance:       dbl("balance"),
            upiId:         str("upiId"),
            isManual:      bool_("isManual"),
            note:          str("note"),
            cardType:      cardType
        )
    }
}
