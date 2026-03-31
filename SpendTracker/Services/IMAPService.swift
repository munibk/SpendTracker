import Foundation
import Network
import Security

// MARK: - Keychain Helper
// Stores IMAP credentials securely. No extra entitlements needed for
// kSecClassGenericPassword — available to all iOS apps by default.
private enum Keychain {
    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "SpendTrackerIMAP",
            kSecAttrAccount: key,
            kSecValueData:   data,
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let q: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      "SpendTrackerIMAP",
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
              let data  = ref as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(_ key: String) {
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "SpendTrackerIMAP",
            kSecAttrAccount: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - IMAP Service
// Connects to Gmail via IMAP using email + App Password.
// No Google Cloud project or Client ID required.
// User generates an App Password at:
//   myaccount.google.com → Security → 2-Step Verification → App Passwords
//
// Credentials are stored in the iOS Keychain (never UserDefaults).
// Same EmailParserService + CCBillService pipeline as the OAuth Gmail flow.

class IMAPService: ObservableObject {

    static let shared = IMAPService()

    // MARK: Published State (mirrors GmailService interface for UI parity)
    @Published var isConnected:         Bool   = false
    @Published var userEmail:           String = ""
    @Published var isFetching:          Bool   = false
    @Published var fetchStatus:         String = "Not connected"
    @Published var lastFetchDate:       Date?  = nil
    @Published var importedCount:       Int    = 0
    @Published var fetchProgress:       Double = 0
    @Published var totalEmailCount:     Int    = 0
    @Published var processedEmailCount: Int    = 0

    private let imapHost: String   = "imap.gmail.com"
    private let imapPort: UInt16   = 993

    // MARK: - Persistence
    var configuredStartYear: Int {
        get {
            let y = UserDefaults.standard.integer(forKey: "imap_start_year")
            return y > 2015 ? y : Calendar.current.component(.year, from: Date()) - 2
        }
        set { UserDefaults.standard.set(newValue, forKey: "imap_start_year") }
    }

    private var incrementalAfterEpoch: TimeInterval {
        get { UserDefaults.standard.double(forKey: "imap_incremental_after") }
        set { UserDefaults.standard.set(newValue, forKey: "imap_incremental_after") }
    }

    private init() {
        userEmail   = Keychain.read("imap_email") ?? ""
        isConnected = !userEmail.isEmpty && Keychain.read("imap_password") != nil
        let epoch   = UserDefaults.standard.double(forKey: "imap_incremental_after")
        if epoch > 0 { lastFetchDate = Date(timeIntervalSince1970: epoch) }
    }

    // MARK: - Credentials
    func saveCredentials(email: String, appPassword: String) {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let p = appPassword.replacingOccurrences(of: " ", with: "")
                           .trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(e, forKey: "imap_email")
        Keychain.save(p, forKey: "imap_password")
        DispatchQueue.main.async {
            self.userEmail   = e
            self.isConnected = true
            self.fetchStatus = "Signed in as \(e)"
        }
    }

    func disconnect() {
        Keychain.delete("imap_email")
        Keychain.delete("imap_password")
        incrementalAfterEpoch = 0
        DispatchQueue.main.async {
            self.isConnected = false
            self.userEmail   = ""
            self.fetchStatus = "Disconnected"
        }
    }

    // MARK: - Verify credentials (test connection without saving)
    func testConnection(email: String, appPassword: String,
                        completion: @escaping (Bool, String) -> Void) {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let p = appPassword.replacingOccurrences(of: " ", with: "")

        DispatchQueue.main.async { self.fetchStatus = "Verifying credentials…" }

        DispatchQueue.global(qos: .userInitiated).async {
            let session = IMAPSession(host: self.imapHost, port: self.imapPort)
            if let err = session.openSync() {
                completion(false, "Connection error: \(err)"); return
            }
            if let err = session.loginSync(user: e, pass: p) {
                session.close()
                completion(false, err); return
            }
            session.close()
            completion(true, "✅ Connected as \(e)")
        }
    }

    // MARK: - Fetch Bank Emails
    func fetchBankEmails(store: TransactionStore,
                         fullRescan: Bool = false,
                         completion: @escaping (Int) -> Void) {
        guard let email    = Keychain.read("imap_email"),
              let password = Keychain.read("imap_password") else {
            DispatchQueue.main.async { self.fetchStatus = "Not signed in — add App Password first" }
            completion(0); return
        }

        DispatchQueue.main.async {
            self.isFetching          = true
            self.fetchStatus         = "Connecting to Gmail…"
            self.fetchProgress       = 0
            self.totalEmailCount     = 0
            self.processedEmailCount = 0
        }

        let query = buildSearchQuery(fullRescan: fullRescan)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let session = IMAPSession(host: self.imapHost, port: self.imapPort)

            if let err = session.openSync() {
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = "Connection failed: \(err)"
                }
                completion(0); return
            }

            if let err = session.loginSync(user: email, pass: password) {
                session.close()
                DispatchQueue.main.async {
                    self.isFetching  = false
                    self.fetchStatus = err
                }
                completion(0); return
            }

            DispatchQueue.main.async { self.fetchStatus = "Searching for bank emails…" }

            if let err = session.selectInboxSync() {
                session.close()
                DispatchQueue.main.async { self.isFetching = false; self.fetchStatus = err }
                completion(0); return
            }

            let allUIDs = session.searchSync(query: query)
            let newUIDs = allUIDs.filter {
                !UserDefaults.standard.bool(forKey: "imap_processed_\($0)")
            }

            guard !newUIDs.isEmpty else {
                session.close()
                self.incrementalAfterEpoch = Date().timeIntervalSince1970
                DispatchQueue.main.async {
                    self.isFetching    = false
                    self.fetchProgress = 1
                    self.fetchStatus   = "✅ No new emails since last sync (\(allUIDs.count) already processed)"
                }
                completion(0); return
            }

            DispatchQueue.main.async {
                self.totalEmailCount = newUIDs.count
                self.fetchStatus     = "Found \(newUIDs.count) new emails, fetching…"
            }

            let parser   = EmailParserService.shared
            var imported = 0
            let batchSize = 20

            for batchStart in stride(from: 0, to: newUIDs.count, by: batchSize) {
                let batch  = Array(newUIDs[batchStart ..< min(batchStart + batchSize, newUIDs.count)])
                let emails = session.fetchSync(uids: batch)

                for email in emails {
                    let full = email.subject + "\n" + email.body
                    let txns = parser.parseAll(emailBody: full, sender: email.from, date: email.date)
                    if !txns.isEmpty {
                        DispatchQueue.main.async { txns.forEach { store.addTransaction($0) } }
                        imported += txns.count
                    }
                    CCBillService.shared.processEmail(
                        subject: email.subject, body: email.body, date: email.date)
                    UserDefaults.standard.set(true, forKey: "imap_processed_\(email.uid)")
                }

                let done = min(batchStart + batchSize, newUIDs.count)
                DispatchQueue.main.async {
                    self.processedEmailCount = done
                    self.fetchProgress       = Double(done) / Double(newUIDs.count)
                    self.fetchStatus         = "Processing \(done) of \(newUIDs.count)…"
                }
            }

            session.close()

            self.incrementalAfterEpoch = Date().timeIntervalSince1970
            DispatchQueue.main.async {
                self.isFetching     = false
                self.fetchProgress  = 1
                self.lastFetchDate  = Date()
                self.importedCount += imported
                self.fetchStatus = imported > 0
                    ? "✅ Imported \(imported) new transactions"
                    : "✅ Checked \(newUIDs.count) emails — no transactions found"
            }
            completion(imported)
        }
    }

    func resetProcessedEmails() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("imap_processed_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        incrementalAfterEpoch = 0
        DispatchQueue.main.async {
            self.fetchProgress       = 0
            self.processedEmailCount = 0
            self.totalEmailCount     = 0
            self.fetchStatus         = "Cache cleared — tap Fetch to re-import all history"
        }
    }

    // MARK: - Search Query (Gmail X-GM-RAW syntax)
    private func buildSearchQuery(fullRescan: Bool) -> String {
        let senders = [
            "from:alerts@hdfcbank.net",
            "from:noreply@hdfcbank.com",
            "from:credit_cards@icicibank.com",
            "from:autoemail@icicibank.com",
            "from:donotreply@icicibank.com",
            "from:alerts@icicibank.com",
            "from:alerts@axisbank.com",
            "from:noreply@axisbank.com",
            "from:notify@axisbank.com",
            "from:noreply@kotak.com",
            "from:alerts@kotak.com",
            "from:noreply@yesbank.in",
            "from:alerts@indusind.com",
            "subject:\"transaction alert\"",
            "subject:debited",
            "subject:credited",
            "subject:\"credit card statement\"",
            "subject:\"payment received\"",
        ].joined(separator: " OR ")

        let datePart: String
        if fullRescan || incrementalAfterEpoch == 0 {
            datePart = "after:\(configuredStartYear)/01/01"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy/MM/dd"
            fmt.timeZone   = TimeZone(identifier: "UTC")
            datePart = "after:\(fmt.string(from: Date(timeIntervalSince1970: incrementalAfterEpoch)))"
        }
        return "(\(senders)) \(datePart)"
    }
}

// MARK: - IMAP Session
// Synchronous IMAP-over-TLS client using Network.framework NWConnection.
// All methods block the calling thread — must be called from a background queue.
// Uses a dedicated callback queue for NWConnection to avoid semaphore deadlocks.

private class IMAPSession {

    private let connection:  NWConnection
    private let callbackQ  = DispatchQueue(label: "imap.callback")
    private var recvBuf    = Data()
    private var tagCounter = 0

    struct FetchedEmail {
        let uid:     String
        let from:    String
        let subject: String
        let date:    Date
        let body:    String
    }

    init(host: String, port: UInt16) {
        let tlsOpts = NWProtocolTLS.Options()
        let tcpOpts = NWProtocolTCP.Options()
        tcpOpts.connectionTimeout = 30
        let params = NWParameters(tls: tlsOpts, tcp: tcpOpts)
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params
        )
    }

    func close() { connection.cancel() }

    // MARK: - Public Commands

    func openSync() -> String? {
        let sem = DispatchSemaphore(value: 0)
        var connErr: String?

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                sem.signal()
            case .failed(let err):
                connErr = err.localizedDescription
                sem.signal()
            case .cancelled:
                connErr = "Connection cancelled"
                sem.signal()
            default: break
            }
        }
        connection.start(queue: callbackQ)
        sem.wait()

        if let e = connErr { return e }

        // Read and verify IMAP greeting: "* OK Gimap ready"
        let greeting = readImapLine()
        return greeting.hasPrefix("* OK") ? nil : "Unexpected server greeting"
    }

    func loginSync(user: String, pass: String) -> String? {
        let tag = nextTag()
        // Quote credentials to safely handle special characters in passwords
        let cmd = "\(tag) LOGIN \"\(user)\" \"\(escapeIMAP(pass))\""
        sendSync(cmd)
        let resp = readTaggedResponse(tag)
        if resp.contains("\(tag) OK") { return nil }
        if resp.lowercased().contains("authentication") ||
           resp.lowercased().contains("invalid credentials") ||
           resp.contains("\(tag) NO") {
            return "Authentication failed — App Password may be wrong or 2FA not enabled on this Google account"
        }
        return "Login failed — check your email and App Password"
    }

    func selectInboxSync() -> String? {
        let tag = nextTag()
        sendSync("\(tag) SELECT INBOX")
        let resp = readTaggedResponse(tag)
        return resp.contains("\(tag) OK") ? nil : "INBOX not accessible"
    }

    // Uses Gmail's X-GM-RAW extension for full Gmail search syntax
    func searchSync(query: String) -> [String] {
        let tag = nextTag()
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        sendSync("\(tag) SEARCH X-GM-RAW \"\(escaped)\"")
        let resp = readTaggedResponse(tag)

        for line in resp.components(separatedBy: "\r\n") {
            if line.hasPrefix("* SEARCH") {
                let uids = line.dropFirst(8)
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                    .filter { !$0.isEmpty }
                return uids
            }
        }
        return []
    }

    // Fetches full RFC5322 messages for the given UIDs without marking as read
    func fetchSync(uids: [String]) -> [FetchedEmail] {
        guard !uids.isEmpty else { return [] }
        let tag  = nextTag()
        let list = uids.joined(separator: ",")
        sendSync("\(tag) UID FETCH \(list) BODY.PEEK[]")
        return readFetchResponse(tag: tag)
    }

    // MARK: - Send / Receive Primitives

    private func sendSync(_ command: String) {
        let sem  = DispatchSemaphore(value: 0)
        let data = (command + "\r\n").data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in sem.signal() })
        sem.wait()
    }

    private func recvChunk() -> Data {
        let sem   = DispatchSemaphore(value: 0)
        var chunk = Data()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
            chunk = data ?? Data()
            sem.signal()
        }
        sem.wait()
        return chunk
    }

    // Read one IMAP line (up to CRLF), refilling recvBuf from the socket as needed
    private func readImapLine() -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let r = recvBuf.range(of: crlf) {
                let line = String(data: recvBuf[..<r.lowerBound], encoding: .utf8)
                          ?? String(data: recvBuf[..<r.lowerBound], encoding: .isoLatin1)
                          ?? ""
                recvBuf.removeSubrange(..<r.upperBound)
                return line
            }
            let chunk = recvChunk()
            if chunk.isEmpty { return "" }
            recvBuf.append(chunk)
        }
    }

    // Read exactly `n` bytes from the socket (for IMAP literal data)
    private func readExactBytes(_ n: Int) -> Data {
        while recvBuf.count < n {
            let chunk = recvChunk()
            if chunk.isEmpty { break }
            recvBuf.append(chunk)
        }
        let count  = min(n, recvBuf.count)
        let result = Data(recvBuf.prefix(count))
        recvBuf.removeFirst(count)
        return result
    }

    // Read all response lines up to the final tagged OK/NO/BAD line.
    // Handles IMAP literal strings {N} embedded in the response.
    private func readTaggedResponse(_ tag: String) -> String {
        var accumulated = ""
        while true {
            let line = readImapLine()
            if let literalSize = extractLiteralSize(from: line) {
                // Literal follows immediately — read N bytes then continue
                accumulated += line + "\r\n"
                let litData  = readExactBytes(literalSize)
                accumulated += String(data: litData, encoding: .utf8)
                             ?? String(data: litData, encoding: .isoLatin1)
                             ?? ""
            } else {
                accumulated += line + "\r\n"
                if line.hasPrefix(tag + " OK") ||
                   line.hasPrefix(tag + " NO") ||
                   line.hasPrefix(tag + " BAD") { break }
            }
        }
        return accumulated
    }

    // Specialised reader for UID FETCH responses — builds FetchedEmail objects
    // incrementally as each message's literal data arrives, rather than
    // accumulating everything into one huge string.
    private func readFetchResponse(tag: String) -> [FetchedEmail] {
        var emails: [FetchedEmail] = []
        var currentUID = ""

        while true {
            let line = readImapLine()

            // Extract UID from "* N FETCH (UID XXXX BODY[] {N}"
            if line.contains("FETCH") && line.contains("UID") {
                if let uid = extractUID(from: line) { currentUID = uid }
            }

            if let literalSize = extractLiteralSize(from: line) {
                // This is the start of a raw RFC5322 message
                let rawData = readExactBytes(literalSize)
                let rawStr  = String(data: rawData, encoding: .utf8)
                            ?? String(data: rawData, encoding: .isoLatin1)
                            ?? ""
                if let email = parseRFC5322(uid: currentUID, raw: rawStr) {
                    emails.append(email)
                }
                currentUID = ""
            }

            if line.hasPrefix(tag + " OK") ||
               line.hasPrefix(tag + " NO") ||
               line.hasPrefix(tag + " BAD") { break }
        }
        return emails
    }

    // MARK: - Helpers

    private func nextTag() -> String {
        tagCounter += 1
        return "T\(String(format: "%03d", tagCounter))"
    }

    private func extractLiteralSize(from line: String) -> Int? {
        guard line.hasSuffix("}"),
              let open = line.lastIndex(of: "{") else { return nil }
        let inside = line[line.index(after: open) ..< line.index(before: line.endIndex)]
        return Int(inside)
    }

    private func extractUID(from line: String) -> String? {
        guard let r = line.range(of: #"UID\s+(\d+)"#, options: .regularExpression),
              let nr = line.range(of: #"\d+"#, options: .regularExpression, range: r)
        else { return nil }
        return String(line[nr])
    }

    private func escapeIMAP(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - RFC5322 / MIME Parser
// Decodes a raw email message into the fields needed by EmailParserService.

private func parseRFC5322(uid: String, raw: String) -> IMAPSession.FetchedEmail? {
    let (headerBlock, bodyBlock) = splitHeadersBody(raw)
    guard !headerBlock.isEmpty else { return nil }

    let from        = extractHeader(headerBlock, "From")
    let subject     = decodeMIMEWords(extractHeader(headerBlock, "Subject"))
    let dateStr     = extractHeader(headerBlock, "Date")
    let date        = parseRFC2822Date(dateStr) ?? Date()
    let contentType = extractHeader(headerBlock, "Content-Type")
    let encoding    = extractHeader(headerBlock, "Content-Transfer-Encoding").lowercased()

    let body: String
    let ctLower = contentType.lowercased()
    if ctLower.hasPrefix("multipart/") {
        body = extractMultipartTextBody(fullRaw: raw, contentType: contentType)
    } else if ctLower.hasPrefix("text/html") {
        body = stripHTML(decodeBodyEncoding(bodyBlock, encoding: encoding))
    } else {
        body = decodeBodyEncoding(bodyBlock, encoding: encoding)
    }

    // Only return emails that have at least some useful content
    guard !from.isEmpty || !subject.isEmpty else { return nil }

    return IMAPSession.FetchedEmail(
        uid:     uid,
        from:    from,
        subject: subject,
        date:    date,
        body:    body
    )
}

private func splitHeadersBody(_ raw: String) -> (headers: String, body: String) {
    if let r = raw.range(of: "\r\n\r\n") {
        return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
    }
    if let r = raw.range(of: "\n\n") {
        return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
    }
    return (raw, "")
}

private func extractHeader(_ headers: String, _ name: String) -> String {
    let lines = headers.components(separatedBy: "\n")
    for (i, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))
        let prefix  = name + ":"
        guard trimmed.uppercased().hasPrefix(prefix.uppercased()) else { continue }
        var value = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        // Fold continuation lines (start with space or tab)
        var j = i + 1
        while j < lines.count {
            let cont = lines[j].trimmingCharacters(in: .init(charactersIn: "\r"))
            guard cont.hasPrefix(" ") || cont.hasPrefix("\t") else { break }
            value += " " + cont.trimmingCharacters(in: .whitespaces)
            j += 1
        }
        return value
    }
    return ""
}

private func extractMultipartTextBody(fullRaw: String, contentType: String) -> String {
    // Extract boundary parameter from Content-Type header
    guard let boundary = extractMIMEParam(contentType, "boundary") else { return "" }

    let delimiter = "--" + boundary
    let parts     = fullRaw.components(separatedBy: delimiter)
    var plainText = ""
    var htmlText  = ""

    for part in parts where !part.hasPrefix("--") {
        let (partHeaders, partBody) = splitHeadersBody(part)
        let ct  = extractHeader(partHeaders, "Content-Type").lowercased()
        let enc = extractHeader(partHeaders, "Content-Transfer-Encoding").lowercased()
        let charset = extractMIMEParam(extractHeader(partHeaders, "Content-Type"), "charset") ?? "utf-8"

        if ct.hasPrefix("text/plain") && plainText.isEmpty {
            plainText = decodeBodyEncoding(partBody, encoding: enc, charset: charset)
        } else if ct.hasPrefix("text/html") && htmlText.isEmpty {
            htmlText  = stripHTML(decodeBodyEncoding(partBody, encoding: enc, charset: charset))
        } else if ct.hasPrefix("multipart/") {
            // Nested multipart — recurse
            let nested = extractMultipartTextBody(fullRaw: part, contentType: ct)
            if !nested.isEmpty { plainText = nested }
        }
    }
    return plainText.isEmpty ? htmlText : plainText
}

private func extractMIMEParam(_ header: String, _ param: String) -> String? {
    let parts = header.components(separatedBy: ";")
    for part in parts {
        let p = part.trimmingCharacters(in: .whitespaces)
        guard p.lowercased().hasPrefix(param.lowercased() + "=") else { continue }
        var value = String(p.dropFirst(param.count + 1))
            .trimmingCharacters(in: .init(charactersIn: "\" \t"))
        // Strip trailing quote
        if value.hasSuffix("\"") { value = String(value.dropLast()) }
        return value
    }
    return nil
}

private func decodeBodyEncoding(_ body: String, encoding: String, charset: String = "utf-8") -> String {
    let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
    switch encoding {
    case "base64":
        let cleaned = b.replacingOccurrences(of: "\r\n", with: "")
                       .replacingOccurrences(of: "\n",   with: "")
                       .replacingOccurrences(of: "\r",   with: "")
        if let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) {
            // Prefer UTF-8; fall back to Latin-1 for Indian bank emails
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? b
        }
        return b
    case "quoted-printable":
        return decodeQuotedPrintable(b)
    default:
        return b
    }
}

private func decodeQuotedPrintable(_ input: String) -> String {
    var result = ""
    var i = input.startIndex
    while i < input.endIndex {
        if input[i] == "=" {
            let n1 = input.index(after: i)
            guard n1 < input.endIndex else { result.append(input[i]); break }
            // Soft line break: =\r\n or =\n
            if input[n1] == "\r" || input[n1] == "\n" {
                i = input.index(after: n1)
                if i < input.endIndex && input[n1] == "\r" && input[i] == "\n" {
                    i = input.index(after: i)
                }
                continue
            }
            let n2 = input.index(after: n1)
            if n2 < input.endIndex, let byte = UInt8(String(input[n1...n2]), radix: 16) {
                result.append(Character(UnicodeScalar(byte)))
                i = input.index(after: n2)
                continue
            }
        }
        result.append(input[i])
        i = input.index(after: i)
    }
    return result
}

// Decode RFC 2047 encoded words: =?charset?B/Q?text?=
private func decodeMIMEWords(_ input: String) -> String {
    let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return input }
    var result  = input
    let ns      = input as NSString
    for match in re.matches(in: input, range: NSRange(location: 0, length: ns.length)).reversed() {
        guard let encR  = Range(match.range(at: 2), in: input),
              let textR = Range(match.range(at: 3), in: input),
              let fullR = Range(match.range,          in: input) else { continue }
        let enc  = String(input[encR]).uppercased()
        let text = String(input[textR])
        var decoded = ""
        if enc == "B" {
            if let d = Data(base64Encoded: text) {
                decoded = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
            }
        } else if enc == "Q" {
            decoded = decodeQuotedPrintable(text.replacingOccurrences(of: "_", with: " "))
        }
        if !decoded.isEmpty { result = result.replacingCharacters(in: fullR, with: decoded) }
    }
    return result
}

private func stripHTML(_ html: String) -> String {
    var s = html
    for tag in ["</tr>", "</p>", "<br/>", "<br />", "<br>", "</div>", "</li>", "</td>"] {
        s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }
    return s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
}

private func parseRFC2822Date(_ dateStr: String) -> Date? {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    for f in [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss z",
    ] {
        fmt.dateFormat = f
        if let d = fmt.date(from: dateStr.trimmingCharacters(in: .whitespaces)) { return d }
    }
    return nil
}
