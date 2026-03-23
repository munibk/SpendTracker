import Foundation
import UIKit

// MARK: - Gmail Service
// Uses Gmail REST API (OAuth2) to fetch bank transaction emails
class GmailService: ObservableObject {

    static let shared = GmailService()

    // ── OAuth Config ──────────────────────────────────────
    private var clientID: String {
        UserDefaults.standard.string(forKey: "gmail_client_id") ?? "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    }
    private let redirectURI   = "com.yourname.spendtracker:/oauth2callback"
    private let scope         = "https://www.googleapis.com/auth/gmail.readonly"
    private let authEndpoint  = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let gmailAPI      = "https://gmail.googleapis.com/gmail/v1"

    // ── State ─────────────────────────────────────────────
    @Published var isConnected:   Bool   = false
    @Published var userEmail:     String = ""
    @Published var isFetching:    Bool   = false
    @Published var fetchStatus:   String = "Not connected"
    @Published var lastFetchDate: Date?  = nil
    @Published var importedCount: Int    = 0

    private var accessToken: String? {
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

    // ── Client ID management ──────────────────────────────
    var isConfigured: Bool {
        let id = UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""
        return !id.isEmpty && !id.hasPrefix("YOUR_GOOGLE")
    }

    func saveClientID(_ id: String) {
        UserDefaults.standard.set(id.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: "gmail_client_id")
        DispatchQueue.main.async { self.fetchStatus = "Client ID saved ✅" }
    }

    func savedClientID() -> String {
        UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""
    }

    // ─────────────────────────────────────────────────────
    // MARK: OAuth2 Login
    // ─────────────────────────────────────────────────────
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

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: tokenEndpoint) else { return }
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["code": code, "client_id": clientID,
                    "redirect_uri": redirectURI, "grant_type": "authorization_code"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            DispatchQueue.main.async {
                if let a = json["access_token"]  as? String { self.accessToken  = a }
                if let r = json["refresh_token"] as? String { self.refreshToken = r }
                if let e = json["expires_in"]    as? Double {
                    self.tokenExpiry = Date().addingTimeInterval(e - 60)
                }
                self.isConnected = true
                self.fetchUserEmail()
                self.fetchStatus = "Connected ✅"
            }
        }.resume()
    }

    func disconnect() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: "gmail_user_email")
        DispatchQueue.main.async {
            self.isConnected = false; self.userEmail = ""; self.fetchStatus = "Disconnected"
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Token Refresh
    // ─────────────────────────────────────────────────────
    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refresh = refreshToken, let url = URL(string: tokenEndpoint) else {
            completion(false); return
        }
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data,
                  let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String
            else { completion(false); return }
            self.accessToken = access
            if let e = json["expires_in"] as? Double {
                self.tokenExpiry = Date().addingTimeInterval(e - 60)
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

    // ─────────────────────────────────────────────────────
    // MARK: Fetch User Email
    // ─────────────────────────────────────────────────────
    private func fetchUserEmail() {
        validToken { [weak self] token in
            guard let self, let token else { return }
            var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data,
                      let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let email = json["emailAddress"] as? String else { return }
                DispatchQueue.main.async {
                    self.userEmail = email
                    UserDefaults.standard.set(email, forKey: "gmail_user_email")
                }
            }.resume()
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Fetch Bank Emails (v21 logic)
    // ─────────────────────────────────────────────────────
    private let bankQueries: [String] = [
        "from:alerts@hdfcbank.net",
        "from:noreply@hdfcbank.com",
        "from:credit_cards@icicibank.com",
        "from:autoemail@icicibank.com",
        "from:donotreply@icicibank.com",
        "from:sbiatm@sbi.co.in",
        "from:noreply@sbi.co.in",
        "from:alerts@axisbank.com",
        "from:noreply@axisbank.com",
        "from:notify@axisbank.com",
        "from:noreply@kotak.com",
        "from:alerts@kotak.com",
        "from:noreply@yesbank.in",
        "from:alerts@indusind.com",
        "subject:transaction alert",
        "subject:debited",
        "subject:credited",
        "subject:\"was debited\"",
        "subject:\"was credited\"",
        "subject:\"credit transaction alert\"",
        "subject:\"debit transaction alert\"",
        "subject:INR",
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

            // Wrap in parens + restrict to last 62 days so cached emails are never re-fetched
            let query   = "(" + self.bankQueries.joined(separator: " OR ") + ") newer_than:62d"
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlStr  = "\(self.gmailAPI)/users/me/messages?q=\(encoded)&maxResults=100"

            guard let url = URL(string: urlStr) else { completion(0); return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let self, let data,
                      let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let messages = json["messages"] as? [[String: Any]]
                else {
                    DispatchQueue.main.async {
                        self?.isFetching  = false
                        self?.fetchStatus = "No bank emails found"
                    }
                    completion(0); return
                }

                DispatchQueue.main.async {
                    self.fetchStatus = "Found \(messages.count) emails, parsing..."
                }
                self.processMessages(messages: messages, token: token,
                                     store: store, completion: completion)
            }.resume()
        }
    }

    // Re-scan: clear processed cache
    func resetProcessedEmails() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("gmail_processed_") {
            defaults.removeObject(forKey: key)
        }
        DispatchQueue.main.async { self.fetchStatus = "Cache cleared — tap Fetch to reimport" }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Process Messages
    // ─────────────────────────────────────────────────────
    private func processMessages(messages: [[String: Any]], token: String,
                                 store: TransactionStore, completion: @escaping (Int) -> Void) {
        let group   = DispatchGroup()
        var count   = 0
        var skipped = 0
        let lock    = NSLock()
        let parser  = EmailParserService.shared

        for message in messages {
            guard let msgID = message["id"] as? String else { continue }

            let processedKey = "gmail_processed_\(msgID)"
            if UserDefaults.standard.bool(forKey: processedKey) {
                lock.lock(); skipped += 1; lock.unlock()
                continue
            }

            group.enter()
            let url = URL(string: "\(gmailAPI)/users/me/messages/\(msgID)?format=full")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let body    = self.extractEmailContent(from: json)
                let sender  = self.extractSender(from: json)
                let subject = self.extractSubject(from: json)
                let dateMs  = json["internalDate"] as? String ?? "0"
                let date    = Date(timeIntervalSince1970: (Double(dateMs) ?? 0) / 1000)
                let full    = subject + "\n" + body

                // Mark as processed regardless of parse result.
                // Non-transaction emails that matched the query (e.g. account summaries)
                // would otherwise be retried on every fetch and keep count at 0.
                // The user can tap "Re-scan" to clear the cache and retry everything.
                UserDefaults.standard.set(true, forKey: processedKey)

                if let txn = parser.parse(emailBody: full, sender: sender, date: date) {
                    DispatchQueue.main.async { store.addTransaction(txn) }
                    lock.lock(); count += 1; lock.unlock()
                }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isFetching    = false
            self.lastFetchDate = Date()
            self.importedCount += count
            if count > 0 {
                self.fetchStatus = "✅ Imported \(count) new transactions from Gmail"
            } else if skipped == messages.count {
                self.fetchStatus = "✅ All \(skipped) emails already imported — tap Re-scan to force re-import"
            } else {
                self.fetchStatus = "✅ Checked \(messages.count) emails — no transaction emails found"
            }
            completion(count)
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Email Extraction
    // Recursively walks the MIME tree.
    // Priority: text/plain > text/html > any nested text.
    // This handles all common Gmail structures:
    //   multipart/alternative → [text/plain, text/html]
    //   multipart/mixed → [multipart/alternative, image/inline, ...]
    //   multipart/related → [text/html, image/inline, ...]
    // ─────────────────────────────────────────────────────
    private func extractEmailContent(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any] else { return "" }
        return extractTextFromPart(payload)
    }

    private func extractTextFromPart(_ part: [String: Any]) -> String {
        let mime = part["mimeType"] as? String ?? ""

        // ── Direct text part ──────────────────────────────
        if mime == "text/plain" {
            if let body = part["body"] as? [String: Any],
               let data = body["data"] as? String {
                return decodeBase64(data, isHTML: false)
            }
            return ""
        }
        if mime == "text/html" {
            if let body = part["body"] as? [String: Any],
               let data = body["data"] as? String {
                return decodeBase64(data, isHTML: true)
            }
            return ""
        }

        // ── Multipart: recurse into children ──────────────
        guard let parts = part["parts"] as? [[String: Any]] else { return "" }

        // For multipart/alternative prefer text/plain first
        if mime == "multipart/alternative" {
            for sub in parts where (sub["mimeType"] as? String) == "text/plain" {
                let t = extractTextFromPart(sub)
                if !t.isEmpty { return t }
            }
        }
        // Fallback: first child that yields non-empty text
        for sub in parts {
            let t = extractTextFromPart(sub)
            if !t.isEmpty { return t }
        }
        return ""
    }

    private func extractSender(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else { return "" }
        return headers.first { ($0["name"] as? String) == "From" }?["value"] as? String ?? ""
    }

    private func extractSubject(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else { return "" }
        return headers.first { ($0["name"] as? String) == "Subject" }?["value"] as? String ?? ""
    }

    private func decodeBase64(_ string: String, isHTML: Bool = false) -> String {
        let b64 = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return "" }
        var raw = String(data: data, encoding: .utf8) ?? ""
        guard !raw.isEmpty else { return "" }
        guard isHTML else { return raw }

        // ── HTML → plain text ──────────────────────────────
        // Step 1: convert block-level tags to newlines BEFORE stripping all tags.
        // <br>, </p>, </tr> etc. represent line breaks — if replaced with a space
        // the multi-line patterns (e.g. "Amount Credited:\nINR 1.00") never match.
        let blockTags = ["</tr>", "</p>", "<br/>", "<br />", "<br>",
                         "</div>", "</li>", "</td>"]
        for tag in blockTags {
            raw = raw.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // Step 2: strip all remaining tags
        raw = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return raw
    }
}
