import Foundation
import UIKit

// MARK: - Gmail Service
class GmailService: ObservableObject {

    static let shared = GmailService()

    private var clientID: String {
        UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""
    }
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

    var isConfigured: Bool {
        let id = UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""
        return !id.isEmpty && id != "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    }

    func saveClientID(_ id: String) {
        UserDefaults.standard.set(id.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: "gmail_client_id")
        DispatchQueue.main.async {
            self.fetchStatus = "Client ID saved ✅"
        }
    }

    func savedClientID() -> String {
        UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""
    }

    private init() {
        isConnected = accessToken != nil && refreshToken != nil
        userEmail   = UserDefaults.standard.string(forKey: "gmail_user_email") ?? ""
    }

    // ─────────────────────────────────────────────────────────
    // MARK: OAuth
    // ─────────────────────────────────────────────────────────
    func startLogin() {
        guard isConfigured else {
            DispatchQueue.main.async {
                self.fetchStatus = "⚠️ Please enter Google Client ID first"
            }
            return
        }
        var c = URLComponents(string: authEndpoint)!
        c.queryItems = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: scope),
            URLQueryItem(name: "access_type",   value: "offline"),
            URLQueryItem(name: "prompt",        value: "consent"),
        ]
        guard let url = c.url else { return }
        UIApplication.shared.open(url)
    }

    func handleCallback(url: URL) {
        guard let c    = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = c.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        exchangeToken(code: code)
    }

    private func exchangeToken(code: String) {
        guard let url = URL(string: tokenEndpoint) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = ["code": code, "client_id": clientID,
                        "redirect_uri": redirectURI, "grant_type": "authorization_code"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            DispatchQueue.main.async {
                if let a = json["access_token"]  as? String { self.accessToken  = a }
                if let r = json["refresh_token"] as? String { self.refreshToken = r }
                if let e = json["expires_in"]    as? Double { self.tokenExpiry  = Date().addingTimeInterval(e - 60) }
                self.isConnected = true
                self.fetchStatus = "Connected ✅"
                self.fetchUserEmail()
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

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let r = refreshToken, let url = URL(string: tokenEndpoint) else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = ["refresh_token": r, "client_id": clientID, "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String
            else { completion(false); return }
            self.accessToken = token
            if let e = json["expires_in"] as? Double { self.tokenExpiry = Date().addingTimeInterval(e - 60) }
            completion(true)
        }.resume()
    }

    private func validToken(completion: @escaping (String?) -> Void) {
        if let ex = tokenExpiry, Date() < ex, let t = accessToken { completion(t); return }
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
    // MARK: Fetch — Last 2 Months, Smart Filter
    // ─────────────────────────────────────────────────────────
    func fetchBankEmails(store: TransactionStore, completion: @escaping (Int) -> Void) {
        guard isConnected else {
            DispatchQueue.main.async { self.fetchStatus = "Not connected to Gmail" }
            completion(0); return
        }

        guard isConfigured else {
            DispatchQueue.main.async { self.fetchStatus = "⚠️ Enter Google Client ID first" }
            completion(0); return
        }

        let fmt = DateFormatter(); fmt.dateFormat = "dd MMM"
        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let today        = fmt.string(from: Date())
        let from         = fmt.string(from: twoMonthsAgo)

        DispatchQueue.main.async {
            self.isFetching  = true
            self.fetchStatus = "Scanning \(from) → \(today)..."
        }

        validToken { [weak self] token in
            guard let self, let token else {
                DispatchQueue.main.async {
                    self?.isFetching  = false
                    self?.fetchStatus = "Token expired — reconnect Gmail"
                }
                completion(0); return
            }

            // Domain-based sender filter — catches ALL emails from bank domains
            // More reliable than exact email addresses which can vary
            let senderDomains = [
                "axisbank.com",
                "icicibank.com",
                "hdfcbank.net",
                "hdfcbank.com",
                "sbi.co.in",
                "kotak.com",
                "yesbank.in",
                "indusind.com",
                "federalbank.co.in",
                "rblbank.com",
                "idfcfirstbank.com",
                "bandhanbank.com",
                "aubank.in",
            ]
            let fromQ = senderDomains.map { "from:@\($0)" }.joined(separator: " OR ")

            // Broad subject — catches ALL transaction formats
            let subjQ = "(subject:debited OR subject:credited OR subject:INR OR subject:\"transaction alert\" OR subject:\"debit alert\" OR subject:\"credit alert\" OR subject:\"was debited\" OR subject:\"was credited\" OR subject:\"amount debited\" OR subject:\"amount credited\" OR subject:\"credit transaction\" OR subject:\"debit transaction\")"

            // Only exclude obvious promotions
            let excludeQ = "-subject:\"save up to\" -subject:\"get up to\" -subject:\"pre-approved\" -subject:\"pre-qualified\" -subject:\"loan offer\" -category:promotions"

            let query   = "(\(fromQ)) \(subjQ) \(excludeQ) newer_than:62d"
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlStr  = "\(self.gmailAPI)/users/me/messages?q=\(encoded)&maxResults=100"

            DispatchQueue.main.async {
                self.fetchStatus = "Querying Gmail..."
            }

            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = "Invalid URL — check Client ID"
                }
                completion(0); return
            }

            self.fetchAllPages(url: url, token: token, accumulated: []) { [weak self] all in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.fetchStatus = "Found \(all.count) emails from bank senders..."
                }

                if all.isEmpty {
                    // Try fallback — broader search without sender filter
                    self.fetchWithFallback(token: token, store: store, completion: completion)
                } else {
                    self.processMessages(messages: all, token: token,
                                         store: store, completion: completion)
                }
            }
        }
    }

    // ── Fallback: search only by subject if sender filter returns nothing ──
    private func fetchWithFallback(token: String, store: TransactionStore,
                                   completion: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            self.fetchStatus = "Trying subject-only search..."
        }

        // No sender filter at all — just subject keywords
        // This catches banks not in our domain list
        let fallbackQuery = "(subject:debited OR subject:credited OR subject:INR OR subject:\"transaction alert\" OR subject:\"debit alert\" OR subject:\"credit alert\" OR subject:\"was debited\" OR subject:\"was credited\" OR subject:\"amount debited\" OR subject:\"amount credited\") newer_than:62d -category:promotions -subject:\"save up to\" -subject:\"pre-approved\""

        let encoded = fallbackQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr  = "\(self.gmailAPI)/users/me/messages?q=\(encoded)&maxResults=100"

        guard let url = URL(string: urlStr) else { completion(0); return }

        fetchAllPages(url: url, token: token, accumulated: []) { [weak self] all in
            guard let self else { return }

            DispatchQueue.main.async {
                self.fetchStatus = "Subject search found \(all.count) emails..."
            }

            if all.isEmpty {
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = "❌ No transaction emails found — make sure bank emails are in this Gmail account"
                }
                completion(0)
            } else {
                self.processMessages(messages: all, token: token,
                                     store: store, completion: completion)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Pagination
    // ─────────────────────────────────────────────────────────
    private func fetchAllPages(url: URL, token: String,
                               accumulated: [[String: Any]],
                               completion: @escaping ([[String: Any]]) -> Void) {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(accumulated); return }

            let msgs     = json["messages"] as? [[String: Any]] ?? []
            let combined = accumulated + msgs
            DispatchQueue.main.async { self.fetchStatus = "Found \(combined.count) emails..." }

            if let next = json["nextPageToken"] as? String, !msgs.isEmpty {
                var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                var items = c.queryItems ?? []
                items.removeAll { $0.name == "pageToken" }
                items.append(URLQueryItem(name: "pageToken", value: next))
                c.queryItems = items
                if let nextURL = c.url {
                    self.fetchAllPages(url: nextURL, token: token, accumulated: combined, completion: completion)
                    return
                }
            }
            completion(combined)
        }.resume()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Process Messages
    // ─────────────────────────────────────────────────────────
    private func processMessages(messages: [[String: Any]], token: String,
                                 store: TransactionStore, completion: @escaping (Int) -> Void) {
        let group  = DispatchGroup()
        var parsed: [Transaction] = []
        var skipped = 0
        var declined = 0
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
                guard let self, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let body    = self.extractContent(from: json)
                let sender  = self.extractSender(from: json)
                let subject = self.extractSubject(from: json)
                let dateMs  = json["internalDate"] as? String ?? "0"
                let date    = Date(timeIntervalSince1970: (Double(dateMs) ?? 0) / 1000)

                // Check for declined first
                let bl = body.lowercased()
                let sl = subject.lowercased()
                let declineWords = ["has been declined","was declined","transaction declined",
                                    "payment declined","been declined","not successful",
                                    "unsuccessful","transaction failed","payment failed",
                                    "domestic online transactions is disabled",
                                    "enable the service","enable the facility",
                                    "insufficient funds","rejected","not authorised",
                                    "not authorized","unable to process"]
                let isDeclined = declineWords.contains { sl.contains($0) || bl.contains($0) }
                if isDeclined {
                    lock.lock(); declined += 1; lock.unlock()
                    return
                }

                // Try to parse — EmailParserService does its own validation
                if let txn = parser.parse(emailBody: subject + "\n" + body,
                                          sender: sender, date: date) {
                    lock.lock(); parsed.append(txn); lock.unlock()
                } else {
                    lock.lock(); skipped += 1; lock.unlock()
                }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            store.addTransactions(parsed)
            let count = parsed.count
            self.isFetching    = false
            self.lastFetchDate = Date()
            self.importedCount += count
            if count > 0 {
                self.fetchStatus = "✅ \(count) transactions imported (\(declined) declined, \(skipped) other skipped)"
            } else if declined > 0 {
                self.fetchStatus = "⚠️ Found \(messages.count) emails but all were declined/unreadable (\(declined) declined)"
            } else {
                self.fetchStatus = "⚠️ Found \(messages.count) emails but could not parse any transactions — check email format"
            }
            completion(count)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Smart Filter — skip promos
    // ─────────────────────────────────────────────────────────
    private func isTransactionEmail(subject: String, body: String) -> Bool {
        let s = subject.lowercased()
        let b = body.lowercased()

        // Hard reject — DECLINED / FAILED transactions (scan full body)
        let declineWords = [
            "has been declined", "was declined", "transaction declined",
            "payment declined", "declined on", "been declined",
            "not successful", "unsuccessful", "transaction failed",
            "payment failed", "could not be processed", "not processed",
            "insufficient funds", "insufficient balance",
            "rejected", "not authorised", "not authorized",
            "transaction blocked", "unable to process",
            "domestic online transactions is disabled",
            "enable the service", "enable the facility",
            "we regret to inform"
        ]
        for kw in declineWords {
            if s.contains(kw) || b.contains(kw) { return false }
        }

        // Hard reject — clear promotional subjects
        let promoSubjects = ["save up to","get up to","cashback offer","pre-approved",
                             "pre-qualified","loan offer","upgrade your card","apply now",
                             "limited time","exclusive offer","special offer","earn up to",
                             "lucky draw","no cost emi","festive offer","refer and earn",
                             "activate now","click here to apply"]
        for kw in promoSubjects { if s.contains(kw) { return false } }

        // Must have amount
        let hasAmount = b.contains("inr ") || b.contains("inr.") ||
                        b.contains("rs. ") || b.contains("rs ")  || b.contains("₹") ||
                        s.contains("inr")  || s.contains("debited") || s.contains("credited")
        guard hasAmount else { return false }

        // Must have debit or credit indicator
        let hasDebit  = ["debited","debit","withdrawn","purchase","payment",
                         "used for","auto debit","emi","pos"].contains { b.contains($0) || s.contains($0) }
        let hasCredit = ["credited","credit","received","deposited","refund",
                         "cashback","salary","neft cr","imps cr","upi cr",
                         "money received","amount credited"].contains { b.contains($0) || s.contains($0) }

        return hasDebit || hasCredit
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Email Content Helpers
    // ─────────────────────────────────────────────────────────
    private func extractContent(from json: [String: Any]) -> String {
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
        let b64 = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return "" }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                  .replacingOccurrences(of: "\\s+",    with: " ", options: .regularExpression)
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetProcessedEmails() {
        DispatchQueue.main.async {
            self.fetchStatus = "Ready — tap Fetch to re-scan last 2 months"
        }
    }
}
