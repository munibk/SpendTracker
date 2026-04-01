import AuthenticationServices
import Foundation
import UIKit

// MARK: - Gmail Service
// Uses Gmail REST API (OAuth2) to fetch bank transaction emails
class GmailService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

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
    private var authSession: ASWebAuthenticationSession?

    // ── State ─────────────────────────────────────────────
    @Published var isConnected:   Bool   = false
    @Published var userEmail:     String = ""
    @Published var isFetching:    Bool   = false
    @Published var fetchStatus:   String = "Not connected"
    @Published var lastFetchDate: Date?  = nil
    @Published var importedCount: Int       = 0
    @Published var fetchProgress: Double    = 0      // 0.0 – 1.0
    @Published var totalEmailCount: Int     = 0
    @Published var processedEmailCount: Int = 0

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
        super.init()
        isConnected = accessToken != nil && refreshToken != nil
        userEmail   = UserDefaults.standard.string(forKey: "gmail_user_email") ?? ""
        // Restore "last fetched" display from persisted epoch
        let epoch = UserDefaults.standard.double(forKey: "gmail_incremental_after")
        if epoch > 0 { lastFetchDate = Date(timeIntervalSince1970: epoch) }
    }

    // Start year for full-history scan (user-configurable, defaults to 2 years ago)
    var configuredStartYear: Int {
        get {
            let y = UserDefaults.standard.integer(forKey: "gmail_start_year")
            return y > 2015 ? y : Calendar.current.component(.year, from: Date()) - 2
        }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_start_year") }
    }

    // Epoch seconds of last successful fetch (0 = never fetched)
    private var incrementalAfterEpoch: TimeInterval {
        get { UserDefaults.standard.double(forKey: "gmail_incremental_after") }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_incremental_after") }
    }

    // Gmail `after:` query — incremental by default, full rescan on first run or user request
    private func buildQuery(fullRescan: Bool = false) -> String {
        let base = "(" + bankQueries.joined(separator: " OR ") + ")"
        if fullRescan || incrementalAfterEpoch == 0 {
            return "\(base) after:\(configuredStartYear)/01/01"
        }
        let date = Date(timeIntervalSince1970: incrementalAfterEpoch)
        let fmt  = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        return "\(base) after:\(fmt.string(from: date))"
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
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "com.yourname.spendtracker"
        ) { [weak self] callbackURL, error in
            guard let self, error == nil, let callbackURL else { return }
            self.handleCallback(url: callbackURL)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func handleCallback(url: URL) {
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
        "from:alerts@icicibank.com",
        "from:noreply@icicibank.com",
        "from:sbiatm@sbi.co.in",
        "from:noreply@sbi.co.in",
        "from:alerts@axisbank.com",
        "from:noreply@axisbank.com",
        "from:notify@axisbank.com",
        "from:alerts@axis.bank.in",   // actual Axis Bank sender domain
        "from:noreply@kotak.com",
        "from:alerts@kotak.com",
        "from:noreply@yesbank.in",
        "from:alerts@indusind.com",
        "subject:transaction alert",
        "subject:debited",
        "subject:debit",          // catches "Debit transaction alert" (no trailing d)
        "subject:credited",
        "subject:credit",         // catches "Credit transaction alert"
        "subject:\"was debited\"",
        "subject:\"was credited\"",
        "subject:\"credit transaction alert\"",
        "subject:\"debit transaction alert\"",
        "subject:INR",
        // CC statement & payment confirmation emails
        "subject:\"credit card statement\"",
        "subject:\"payment received on your\"",
        "subject:\"payment received\" credit card",
    ]

    func fetchBankEmails(store: TransactionStore, fullRescan: Bool = false, completion: @escaping (Int) -> Void) {
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

            // Paginate through all matching emails (no fixed time limit).
            // Incremental: uses `after:` date from last fetch. Full rescan: uses configuredStartYear.
            let query = self.buildQuery(fullRescan: fullRescan)
            self.fetchAllMessageIDs(query: query, token: token) { [weak self] messages in
                guard let self else { return }
                if messages.isEmpty {
                    DispatchQueue.main.async {
                        self.isFetching  = false
                        self.fetchStatus = "No bank emails found"
                    }
                    completion(0); return
                }
                DispatchQueue.main.async {
                    self.totalEmailCount     = messages.count
                    self.processedEmailCount = 0
                    self.fetchProgress       = 0
                    self.fetchStatus = "Found \(messages.count) emails, processing..."
                }
                self.processMessages(messages: messages, token: token,
                                     store: store, completion: completion)
            }
        }
    }

    // Paginates through all Gmail results for the given query.
    // Gmail API max per page is 500; follows nextPageToken until exhausted.
    private func fetchAllMessageIDs(query: String, token: String,
                                    pageToken: String? = nil,
                                    accumulated: [[String: Any]] = [],
                                    completion: @escaping ([[String: Any]]) -> Void) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr  = "\(gmailAPI)/users/me/messages?q=\(encoded)&maxResults=500"
        if let pt = pageToken { urlStr += "&pageToken=\(pt)" }

        guard let url = URL(string: urlStr) else { completion(accumulated); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(accumulated); return }

            let newMessages = (json["messages"] as? [[String: Any]]) ?? []
            let all         = accumulated + newMessages
            let next        = json["nextPageToken"] as? String

            if let next, !next.isEmpty {
                // More pages available — keep fetching
                DispatchQueue.main.async {
                    self.fetchStatus = "Found \(all.count) emails, loading more..."
                }
                self.fetchAllMessageIDs(query: query, token: token,
                                        pageToken: next, accumulated: all,
                                        completion: completion)
            } else {
                completion(all)
            }
        }.resume()
    }

    // Full re-scan: clears processed-ID cache and resets incremental epoch
    func resetProcessedEmails() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("gmail_processed_") {
            defaults.removeObject(forKey: key)
        }
        incrementalAfterEpoch = 0   // forces next fetch to start from configuredStartYear
        DispatchQueue.main.async {
            self.fetchProgress       = 0
            self.processedEmailCount = 0
            self.totalEmailCount     = 0
            self.fetchStatus         = "Cache cleared — tap Fetch to re-import all history"
        }
    }

    // ─────────────────────────────────────────────────────
    // MARK: Process Messages
    // Fetches email bodies in batches of 5 concurrent requests to avoid
    // Gmail API rate limits while keeping processing fast.
    // Progress is reported live via @Published properties.
    // ─────────────────────────────────────────────────────
    private func processMessages(messages: [[String: Any]], token: String,
                                 store: TransactionStore, completion: @escaping (Int) -> Void) {
        let total   = messages.count
        var count   = 0
        var done    = 0
        let lock    = NSLock()
        let group   = DispatchGroup()
        let parser  = EmailParserService.shared

        // Semaphore caps simultaneous in-flight requests at 5.
        // Must be waited on from a background thread (not main).
        let semaphore = DispatchSemaphore(value: 5)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            for message in messages {
                guard let msgID = message["id"] as? String else { continue }

                // Skip already-processed emails without a network call
                let processedKey = "gmail_processed_\(msgID)"
                if UserDefaults.standard.bool(forKey: processedKey) {
                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    DispatchQueue.main.async {
                        self.processedEmailCount = d
                        self.fetchProgress       = Double(d) / Double(total)
                        self.fetchStatus         = "Processing \(d) of \(total)..."
                    }
                    continue
                }

                semaphore.wait()   // block until a slot is free (max 5 concurrent)
                group.enter()

                let url = URL(string: "\(self.gmailAPI)/users/me/messages/\(msgID)?format=full")!
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                    defer {
                        group.leave()
                        semaphore.signal()
                    }
                    guard let self, let data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return }

                    let body    = self.extractEmailContent(from: json)
                    let sender  = self.extractSender(from: json)
                    let subject = self.extractSubject(from: json)
                    let dateMs  = json["internalDate"] as? String ?? "0"
                    let date    = Date(timeIntervalSince1970: (Double(dateMs) ?? 0) / 1000)
                    let full    = subject + "\n" + body

                    // Mark processed regardless of parse result so non-transaction
                    // emails (e.g. account summaries) aren't retried every time.
                    UserDefaults.standard.set(true, forKey: processedKey)

                    let txns = parser.parseAll(emailBody: full, sender: sender, date: date)
                    if !txns.isEmpty {
                        DispatchQueue.main.async { txns.forEach { store.addTransaction($0) } }
                        lock.lock(); count += txns.count; lock.unlock()
                    }

                    // Track CC bill statement and payment-confirmation emails
                    CCBillService.shared.processEmail(subject: subject, body: body, date: date)

                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    DispatchQueue.main.async {
                        self.processedEmailCount = d
                        self.fetchProgress       = Double(d) / Double(total)
                        self.fetchStatus         = "Processing \(d) of \(total)..."
                    }
                }.resume()
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.isFetching          = false
                self.fetchProgress       = 1.0
                self.lastFetchDate       = Date()
                self.importedCount      += count
                // Persist for next incremental fetch
                self.incrementalAfterEpoch = Date().timeIntervalSince1970
                if count > 0 {
                    self.fetchStatus = "✅ Imported \(count) new transactions from Gmail"
                } else if done == total {
                    self.fetchStatus = "✅ All \(total) emails already processed — use Full Re-scan to retry"
                } else {
                    self.fetchStatus = "✅ Checked \(total) emails — no transaction emails found"
                }
                completion(count)
            }
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
