import Foundation
import UIKit

// MARK: - Gmail Service
class GmailService: ObservableObject {

    static let shared = GmailService()

    private let clientID      = "396449652721-030jr599hc1r67sj22hngg0imt4pha0s.apps.googleusercontent.com"
    private let redirectURI   = "com.yourname.spendtracker:/oauth2callback"
    private let scope         = "https://www.googleapis.com/auth/gmail.readonly"
    private let authEndpoint  = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let gmailAPI      = "https://gmail.googleapis.com/gmail/v1"

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

    // ─────────────────────────────────────────────────────────
    // MARK: OAuth
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

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: tokenEndpoint) else { return }
        var req        = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["code": code, "client_id": clientID,
                    "redirect_uri": redirectURI, "grant_type": "authorization_code"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
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
                self.fetchStatus = "Connected ✅"
                self.fetchUserEmail()
            }
        }.resume()
    }

    func disconnect() {
        accessToken  = nil; refreshToken = nil; tokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: "gmail_user_email")
        DispatchQueue.main.async {
            self.isConnected = false; self.userEmail = ""; self.fetchStatus = "Disconnected"
        }
    }

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refresh = refreshToken, let url = URL(string: tokenEndpoint) else {
            completion(false); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String
            else { completion(false); return }
            self.accessToken = token
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
        refreshAccessToken { [weak self] ok in completion(ok ? self?.accessToken : nil) }
    }

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

    // ─────────────────────────────────────────────────────────
    // MARK: Smart Bank Query
    // Only fetches TRANSACTION alerts — ignores offers/promotions
    // Uses Gmail's -category:promotions to exclude marketing emails
    // ─────────────────────────────────────────────────────────
    private func buildBankQuery(fromTimestamp: Int) -> String {
        // Exact known transaction alert senders
        let senders = [
            "alerts@axisbank.com",
            "noreply@axisbank.com",
            "credit_cards@icicibank.com",
            "autoemail@icicibank.com",
            "alerts@hdfcbank.net",
            "noreply@hdfcbank.com",
            "sbiatm@sbi.co.in",
            "noreply@sbi.co.in",
            "noreply@kotak.com",
            "alerts@kotak.com",
            "noreply@yesbank.in",
            "alerts@indusind.com",
            "alerts@federalbank.co.in",
            "alerts@rblbank.com",
            "alerts@idfcfirstbank.com",
            "donotreply@icicibank.com",
            "notify@axisbank.com",
        ]
        let fromQuery = senders.map { "from:\($0)" }.joined(separator: " OR ")

        // Subject must contain transaction keywords
        // This filters out promotional emails from same senders
        let subjectQuery = "(subject:debited OR subject:credited OR subject:\"transaction alert\" OR subject:\"debit alert\" OR subject:\"credit alert\" OR subject:\"account alert\" OR subject:\"payment\" OR subject:\"INR\" OR subject:\"used for\")"

        // Exclude promotional / offer emails explicitly
        let excludeQuery = "-subject:offer -subject:\"save up to\" -subject:\"get up to\" -subject:\"cashback offer\" -subject:\"reward\" -subject:\"pre-approved\" -subject:\"pre-qualified\" -subject:\"loan offer\" -subject:\"credit card offer\" -subject:\"upgrade\" -category:promotions -category:social"

        return "(\(fromQuery)) \(subjectQuery) \(excludeQuery) after:\(fromTimestamp)"
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Intelligent Transaction Filter
    // Second layer — checks email body before parsing
    // Rejects emails that don't look like real transactions
    // ─────────────────────────────────────────────────────────
    private func isTransactionEmail(subject: String, body: String) -> Bool {
        let s = subject.lowercased()
        let b = body.lowercased()

        // ── Hard reject — promotional keywords ───────────────
        let promoKeywords = [
            "save up to", "get up to", "offer", "cashback offer",
            "pre-approved", "pre-qualified", "loan offer", "upgrade your card",
            "apply now", "limited time", "exclusive offer", "special offer",
            "reward points", "earn up to", "win", "lucky draw",
            "no cost emi", "0% emi", "zero cost emi",
            "festive offer", "sale", "discount up to",
            "refer and earn", "invite", "register now",
            "click here to apply", "activate now",
        ]
        for kw in promoKeywords {
            if s.contains(kw) || b.prefix(200).description.contains(kw) { return false }
        }

        // ── Must have transaction amount ──────────────────────
        let hasAmount = b.contains("inr ") || b.contains("rs.") ||
                        b.contains("rs ") || b.contains("₹") ||
                        b.contains("debited") || b.contains("credited")
        guard hasAmount else { return false }

        // ── Must have transaction-specific words ──────────────
        let txnWords = [
            "debited", "credited", "transaction", "payment",
            "a/c", "account", "card", "upi", "imps", "neft",
            "amount debited", "amount credited", "has been used",
            "was debited", "was credited", "purchase"
        ]
        return txnWords.contains(where: { b.contains($0) })
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch — Last 2 Months Only
    // ─────────────────────────────────────────────────────────
    func fetchBankEmails(store: TransactionStore, completion: @escaping (Int) -> Void) {
        guard isConnected else {
            DispatchQueue.main.async { self.fetchStatus = "Not connected to Gmail" }
            completion(0); return
        }

        DispatchQueue.main.async {
            self.isFetching  = true
            self.fetchStatus = "Scanning last 2 months for transactions..."
        }

        validToken { [weak self] token in
            guard let self, let token else {
                DispatchQueue.main.async {
                    self?.isFetching  = false
                    self?.fetchStatus = "Token expired — reconnect Gmail"
                }
                completion(0); return
            }

            // Exactly 2 months ago from today
            let twoMonthsAgo = Calendar.current.date(
                byAdding: .month, value: -2, to: Date()
            ) ?? Date()
            let fromTS  = Int(twoMonthsAgo.timeIntervalSince1970)
            let query   = self.buildBankQuery(fromTimestamp: fromTS)
            let encoded = query.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""

            let urlStr = "\(self.gmailAPI)/users/me/messages?q=\(encoded)&maxResults=100"
            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = "Invalid URL"
                }
                completion(0); return
            }

            self.fetchAllPages(url: url, token: token, accumulated: []) { [weak self] allMessages in
                guard let self else { return }
                if allMessages.isEmpty {
                    DispatchQueue.main.async {
                        self.isFetching  = false
                        self.fetchStatus = "No transaction emails found in last 2 months"
                    }
                    completion(0)
                } else {
                    DispatchQueue.main.async {
                        self.fetchStatus = "Found \(allMessages.count) emails — filtering..."
                    }
                    self.processMessages(
                        messages:   allMessages,
                        token:      token,
                        store:      store,
                        completion: completion
                    )
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Pagination
    // ─────────────────────────────────────────────────────────
    private func fetchAllPages(
        url:         URL,
        token:       String,
        accumulated: [[String: Any]],
        completion:  @escaping ([[String: Any]]) -> Void
    ) {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(accumulated); return }

            let pageMessages = json["messages"] as? [[String: Any]] ?? []
            let combined     = accumulated + pageMessages

            DispatchQueue.main.async { self.fetchStatus = "Found \(combined.count) emails..." }

            if let nextToken = json["nextPageToken"] as? String, !pageMessages.isEmpty {
                var comps  = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                var items  = comps.queryItems ?? []
                items.removeAll { $0.name == "pageToken" }
                items.append(URLQueryItem(name: "pageToken", value: nextToken))
                comps.queryItems = items
                if let nextURL = comps.url {
                    self.fetchAllPages(url: nextURL, token: token,
                                       accumulated: combined, completion: completion)
                    return
                }
            }
            completion(combined)
        }.resume()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Process — with smart filtering
    // ─────────────────────────────────────────────────────────
    private func processMessages(
        messages:   [[String: Any]],
        token:      String,
        store:      TransactionStore,
        completion: @escaping (Int) -> Void
    ) {
        let group  = DispatchGroup()
        var parsed: [Transaction] = []
        var skipped = 0
        let lock   = NSLock()
        let parser = EmailParserService.shared

        for message in messages {
            guard let msgID = message["id"] as? String else { continue }

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

                let body    = self.extractEmailContent(from: json)
                let sender  = self.extractSender(from: json)
                let subject = self.extractSubject(from: json)
                let dateMs  = json["internalDate"] as? String ?? "0"
                let date    = Date(timeIntervalSince1970: (Double(dateMs) ?? 0) / 1000)

                // ── Smart filter: skip promo/junk emails ──────
                guard self.isTransactionEmail(subject: subject, body: body) else {
                    lock.lock(); skipped += 1; lock.unlock()
                    return
                }

                let full = subject + "\n" + body
                if let txn = parser.parse(emailBody: full, sender: sender, date: date) {
                    lock.lock(); parsed.append(txn); lock.unlock()
                } else {
                    lock.lock(); skipped += 1; lock.unlock()
                }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            store.addTransactions(parsed)
            let count          = parsed.count
            self.isFetching    = false
            self.lastFetchDate = Date()
            self.importedCount += count
            self.fetchStatus   = count > 0
                ? "✅ \(count) transactions imported (\(skipped) non-transaction emails skipped)"
                : "✅ No new transactions found (\(skipped) promotional emails filtered out)"
            completion(count)
        }
    }

    func resetProcessedEmails() {
        DispatchQueue.main.async {
            self.fetchStatus = "Ready — tap Fetch to scan last 2 months"
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Email Extraction Helpers
    // ─────────────────────────────────────────────────────────
    private func extractEmailContent(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any] else { return "" }
        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String { return decodeBase64(data) }
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                let mime = part["mimeType"] as? String ?? ""
                if mime == "text/plain" || mime == "text/html" {
                    if let body = part["body"] as? [String: Any],
                       let data = body["data"] as? String { return decodeBase64(data) }
                }
                if let subs = part["parts"] as? [[String: Any]] {
                    for sub in subs {
                        if let body = sub["body"] as? [String: Any],
                           let data = body["data"] as? String { return decodeBase64(data) }
                    }
                }
            }
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

    private func decodeBase64(_ string: String) -> String {
        let b64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return "" }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+",    with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
