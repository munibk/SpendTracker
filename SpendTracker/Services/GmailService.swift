import Foundation
import UIKit

// MARK: - Gmail Service
// Uses Gmail REST API (OAuth2) to fetch bank transaction emails
// No third party libraries needed — pure URLSession

class GmailService: ObservableObject {

    static let shared = GmailService()

    // ── OAuth Config ─────────────────────────────────────────
    // IMPORTANT: Replace with your own Google OAuth Client ID
    // Get it free from: https://console.cloud.google.com
    // Steps in README_GMAIL_SETUP.md
    private let clientID     = "396449652721-030jr599hc1r67sj22hngg0imt4pha0s.apps.googleusercontent.com"
    private let redirectURI  = "com.yourname.spendtracker:/oauth2callback"
    private let scope        = "https://www.googleapis.com/auth/gmail.readonly"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let gmailAPI     = "https://gmail.googleapis.com/gmail/v1"

    // ── State ────────────────────────────────────────────────
    @Published var isConnected:    Bool   = false
    @Published var userEmail:      String = ""
    @Published var isFetching:     Bool   = false
    @Published var fetchStatus:    String = "Not connected"
    @Published var lastFetchDate:  Date?  = nil
    @Published var importedCount:  Int    = 0

    private var accessToken:  String? {
        get { UserDefaults.standard.string(forKey: "gmail_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_access_token") }
    }
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "gmail_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_refresh_token") }
    }
    private var tokenExpiry: Date? {
        get { UserDefaults.standard.object(forKey: "gmail_token_expiry") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_token_expiry") }
    }

    private init() {
        isConnected = accessToken != nil && refreshToken != nil
        userEmail   = UserDefaults.standard.string(forKey: "gmail_user_email") ?? ""
    }

    // ─────────────────────────────────────────────────────────
    // MARK: OAuth2 Login
    // ─────────────────────────────────────────────────────────
    func startLogin() {
        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: scope),
            URLQueryItem(name: "access_type",   value: "offline"),
            URLQueryItem(name: "prompt",        value: "consent"),
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    // Called from SpendTrackerApp.onOpenURL when redirect comes back
    func handleCallback(url: URL) {
        guard url.scheme == "com.yourname.spendtracker",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }

        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: tokenEndpoint) else { return }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")

        let body = [
            "code":          code,
            "client_id":     clientID,
            "redirect_uri":  redirectURI,
            "grant_type":    "authorization_code",
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            DispatchQueue.main.async {
                if let access  = json["access_token"]  as? String { self.accessToken  = access  }
                if let refresh = json["refresh_token"] as? String { self.refreshToken = refresh }
                if let expires = json["expires_in"]    as? Double {
                    self.tokenExpiry = Date().addingTimeInterval(expires - 60)
                }
                self.isConnected = true
                self.fetchUserEmail()
                self.fetchStatus = "Connected ✅"
            }
        }.resume()
    }

    func disconnect() {
        accessToken  = nil
        refreshToken = nil
        tokenExpiry  = nil
        UserDefaults.standard.removeObject(forKey: "gmail_user_email")
        DispatchQueue.main.async {
            self.isConnected = false
            self.userEmail   = ""
            self.fetchStatus = "Disconnected"
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Token Refresh
    // ─────────────────────────────────────────────────────────
    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refresh = refreshToken,
              let url     = URL(string: tokenEndpoint) else {
            completion(false); return
        }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refresh,
            "client_id":     clientID,
            "grant_type":    "refresh_token",
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String
            else { completion(false); return }

            self.accessToken = access
            if let expires = json["expires_in"] as? Double {
                self.tokenExpiry = Date().addingTimeInterval(expires - 60)
            }
            completion(true)
        }.resume()
    }

    private func validToken(completion: @escaping (String?) -> Void) {
        if let expiry = tokenExpiry, Date() < expiry, let token = accessToken {
            completion(token); return
        }
        refreshAccessToken { [weak self] success in
            completion(success ? self?.accessToken : nil)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch User Email
    // ─────────────────────────────────────────────────────────
    private func fetchUserEmail() {
        validToken { [weak self] token in
            guard let self, let token else { return }
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let email = json["emailAddress"] as? String
                else { return }
                DispatchQueue.main.async {
                    self.userEmail = email
                    UserDefaults.standard.set(email, forKey: "gmail_user_email")
                }
            }.resume()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch Bank Emails
    // ─────────────────────────────────────────────────────────

    // Bank email sender addresses / subject keywords
    // Updated based on real Indian bank email formats
    private let bankQueries: [String] = [
        // ── Axis Bank ────────────────────────────────────────
        "from:axisbank",
        "from:axis",
        // ── ICICI Bank ───────────────────────────────────────
        "from:icicibank",
        "from:icici",
        // ── HDFC Bank ────────────────────────────────────────
        "from:hdfcbank",
        "from:hdfc",
        // ── SBI ──────────────────────────────────────────────
        "from:sbi",
        // ── Kotak ────────────────────────────────────────────
        "from:kotak",
        // ── Other Banks ──────────────────────────────────────
        "from:yesbank",
        "from:indusind",
        "from:idfcfirst",
        "from:federalbank",
        "from:rblbank",
        "from:aubank",
        "from:pnb",
        "from:bankofbaroda",
        "from:canarabank",
        "from:unionbank",
        // ── Subject keyword fallbacks ─────────────────────────
        "subject:debited",
        "subject:credited",
        "subject:transaction alert",
        "subject:payment confirmation",
        "subject:UPI transaction",
        "subject:INR debited",
        "subject:INR credited",
        "subject:account alert",
        "subject:card alert",
    ]

    func fetchBankEmails(store: TransactionStore, completion: @escaping (Int) -> Void) {
        guard isConnected else {
            DispatchQueue.main.async { self.fetchStatus = "Not connected to Gmail" }
            completion(0); return
        }

        DispatchQueue.main.async {
            self.isFetching  = true
            self.fetchStatus = "Fetching emails..."
        }

        validToken { [weak self] token in
            guard let self, let token else {
                DispatchQueue.main.async {
                    self?.isFetching  = false
                    self?.fetchStatus = "Token expired — please reconnect"
                }
                completion(0); return
            }

            // Simple broad query that catches all bank transaction emails
            // Gmail API works best with shorter queries
            let query = "subject:debited OR subject:credited OR subject:transaction OR from:axisbank OR from:icicibank OR from:hdfcbank OR from:sbi.co.in OR from:kotak"

            let encoded = query.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""

            // Only fetch last 30 days emails
            let thirtyDaysAgo = Int(Date().addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970)
            let urlStr = "\(self.gmailAPI)/users/me/messages?q=\(encoded)%20after:\(thirtyDaysAgo)&maxResults=50"

            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = "Invalid URL"
                }
                completion(0); return
            }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
                guard let self else { return }

                // Debug: print response
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    if let messages = json["messages"] as? [[String: Any]] {
                        DispatchQueue.main.async {
                            self.fetchStatus = "Found \(messages.count) emails, parsing..."
                        }
                        self.processMessages(
                            messages: messages,
                            token:    token,
                            store:    store,
                            completion: completion
                        )
                    } else {
                        // No messages found
                        DispatchQueue.main.async {
                            self.isFetching  = false
                            self.fetchStatus = "No bank emails found in last 30 days"
                        }
                        completion(0)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isFetching  = false
                        self.fetchStatus = "Error connecting to Gmail"
                    }
                    completion(0)
                }
            }.resume()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Process Each Email
    // ─────────────────────────────────────────────────────────
    // Call this to re-scan all emails (useful when parser is updated)
    func resetProcessedEmails() {
        // Clear all processed email flags
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("gmail_processed_") {
            defaults.removeObject(forKey: key)
        }
        DispatchQueue.main.async {
            self.fetchStatus = "Cache cleared — tap Fetch to reimport"
        }
    }

    private func processMessages(
        messages:   [[String: Any]],
        token:      String,
        store:      TransactionStore,
        completion: @escaping (Int) -> Void
    ) {
        let group   = DispatchGroup()
        var count   = 0
        let lock    = NSLock()
        let parser  = EmailParserService.shared

        for message in messages {
            guard let msgID = message["id"] as? String else { continue }

            // Skip already processed
            let processedKey = "gmail_processed_\(msgID)"
            if UserDefaults.standard.bool(forKey: processedKey) { continue }

            group.enter()
            let url = URL(string: "\(gmailAPI)/users/me/messages/\(msgID)?format=full")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let emailContent = self.extractEmailContent(from: json)
                let sender       = self.extractSender(from: json)
                let subject      = self.extractSubject(from: json)
                let dateMs       = json["internalDate"] as? String ?? "0"
                let date         = Date(timeIntervalSince1970:
                                        (Double(dateMs) ?? 0) / 1000)

                // Try to parse as transaction
                let fullText = "\(subject)\n\(emailContent)"
                if let txn = parser.parse(
                    emailBody: fullText,
                    sender: sender,
                    date: date
                ) {
                    DispatchQueue.main.async {
                        store.addTransaction(txn)
                    }
                    lock.lock(); count += 1; lock.unlock()
                    UserDefaults.standard.set(true, forKey: processedKey)
                }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isFetching    = false
            self.lastFetchDate = Date()
            self.importedCount += count
            self.fetchStatus   = count > 0
                ? "✅ Imported \(count) transactions from Gmail"
                : "✅ No new transactions found"
            completion(count)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Extract Email Parts
    // ─────────────────────────────────────────────────────────
    private func extractEmailContent(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any] else { return "" }

        // Try body directly
        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String {
            return decodeBase64(data)
        }

        // Try parts
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                let mimeType = part["mimeType"] as? String ?? ""
                if mimeType == "text/plain" || mimeType == "text/html" {
                    if let body = part["body"] as? [String: Any],
                       let data = body["data"] as? String {
                        return decodeBase64(data)
                    }
                }
                // Nested parts
                if let subParts = part["parts"] as? [[String: Any]] {
                    for subPart in subParts {
                        if let body = subPart["body"] as? [String: Any],
                           let data = body["data"] as? String {
                            return decodeBase64(data)
                        }
                    }
                }
            }
        }
        return ""
    }

    private func extractSender(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]]
        else { return "" }
        return headers.first(where: { ($0["name"] as? String) == "From" })?["value"] as? String ?? ""
    }

    private func extractSubject(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]]
        else { return "" }
        return headers.first(where: { ($0["name"] as? String) == "Subject" })?["value"] as? String ?? ""
    }

    private func decodeBase64(_ string: String) -> String {
        let base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return "" }
        // Strip HTML tags if present
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
    }
}
