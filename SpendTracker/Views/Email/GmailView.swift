import SwiftUI

// MARK: - Gmail View
struct GmailView: View {
    @EnvironmentObject var store:  TransactionStore
    @StateObject private var gmail = GmailService.shared
    @StateObject private var imap  = IMAPService.shared
    @AppStorage("email_method") private var emailMethod = "imap"   // "imap" | "oauth"
    @State private var showManualImport = false
    @State private var showSetupGuide   = false
    @State private var fetchCount       = 0
    @State private var showFetchResult  = false
    @State private var clientIDText     = ""
    @State private var showClientIDSaved  = false
    @State private var showYearPicker      = false
    @State private var selectedStartYear   = Calendar.current.component(.year, from: Date()) - 2

    // IMAP-specific state
    @State private var imapEmail       = ""
    @State private var imapPassword    = ""
    @State private var imapVerifying   = false
    @State private var imapVerifyMsg   = ""
    @State private var showIMAPPassword = false

    var body: some View {
        NavigationView {
            List {

                // ── Method Picker ─────────────────────────────
                Section {
                    Picker("Connection Method", selection: $emailMethod) {
                        Label("App Password", systemImage: "key.fill")
                            .tag("imap")
                        Label("Google OAuth", systemImage: "g.circle.fill")
                            .tag("oauth")
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if emailMethod == "imap" {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                            Text("Recommended — works with any shared IPA, no Google Cloud setup needed")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                            Text("Advanced — requires a Google Cloud project and Client ID")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                // ─────────────────────────────────────────────
                // MARK: IMAP / App Password Method
                // ─────────────────────────────────────────────
                if emailMethod == "imap" {

                    if imap.isConnected {
                        // ── Connected ────────────────────────
                        Section {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(Color.green.opacity(0.15)).frame(width: 44, height: 44)
                                    Image(systemName: "key.fill").foregroundColor(.green).font(.title2)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("App Password Connected").font(.subheadline).fontWeight(.semibold)
                                    Text(imap.userEmail).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }

                        Section(header: Text("Import")) {
                            Button(action: imapFetchEmails) {
                                HStack {
                                    if imap.isFetching {
                                        ProgressView().scaleEffect(0.8).frame(width: 20)
                                    } else {
                                        Image(systemName: "envelope.badge")
                                            .foregroundColor(Color(hex: "#6C63FF")).frame(width: 20)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(imap.isFetching ? "Scanning emails…" : "Fetch New Emails")
                                        Text(imapFetchSubtitle).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .disabled(imap.isFetching)

                            if imap.isFetching && imap.totalEmailCount > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: imap.fetchProgress).tint(Color(hex: "#6C63FF"))
                                    Text("\(imap.processedEmailCount) of \(imap.totalEmailCount) emails processed")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }

                            Button(action: imapRescanAll) {
                                HStack {
                                    Image(systemName: "arrow.clockwise.circle").foregroundColor(.orange).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Full Re-scan All History")
                                        Text("Re-imports from \(imap.configuredStartYear) onwards")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .disabled(imap.isFetching)

                            Button(action: {
                                selectedStartYear = imap.configuredStartYear
                                showYearPicker    = true
                            }) {
                                HStack {
                                    Image(systemName: "calendar").foregroundColor(.secondary).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("History Start Year")
                                        Text("Currently: \(imap.configuredStartYear)").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .disabled(imap.isFetching)

                            Button(action: { showManualImport = true }) {
                                Label("Paste Email Manually", systemImage: "doc.text")
                            }
                        }

                        Section(header: Text("Status")) {
                            HStack {
                                Text("Status"); Spacer()
                                Text(imap.fetchStatus).font(.caption).foregroundColor(.secondary)
                                    .lineLimit(2).multilineTextAlignment(.trailing)
                            }
                            if let last = imap.lastFetchDate {
                                HStack {
                                    Text("Last Fetched"); Spacer()
                                    Text(last.formatted(.relative(presentation: .numeric)))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            HStack {
                                Text("Total Imported"); Spacer()
                                Text("\(imap.importedCount)").foregroundColor(.secondary)
                            }
                        }

                        Section {
                            Button(role: .destructive, action: { imap.disconnect() }) {
                                Label("Remove App Password", systemImage: "xmark.circle")
                            }
                        }

                    } else {
                        // ── Sign-in form ─────────────────────
                        Section(header: Text("Gmail Account")) {
                            TextField("your@gmail.com", text: $imapEmail)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()

                            HStack {
                                Group {
                                    if showIMAPPassword {
                                        TextField("App Password (16 chars)", text: $imapPassword)
                                    } else {
                                        SecureField("App Password (16 chars)", text: $imapPassword)
                                    }
                                }
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                Button(action: { showIMAPPassword.toggle() }) {
                                    Image(systemName: showIMAPPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !imapVerifyMsg.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: imapVerifyMsg.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(imapVerifyMsg.contains("✅") ? .green : .red)
                                    Text(imapVerifyMsg).font(.caption).foregroundColor(.secondary)
                                }
                            }

                            Button(action: verifyAndConnectIMAP) {
                                HStack {
                                    if imapVerifying { ProgressView().scaleEffect(0.8) }
                                    Text(imapVerifying ? "Verifying…" : "Verify & Connect")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                                .padding(10)
                                .background(imapEmail.isEmpty || imapPassword.isEmpty
                                            ? Color.gray : Color(hex: "#6C63FF"))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(imapEmail.isEmpty || imapPassword.isEmpty || imapVerifying)
                            .buttonStyle(.plain)
                        }

                        Section(header: Text("How to get an App Password")) {
                            VStack(alignment: .leading, spacing: 10) {
                                stepRow(n: "1", text: "Go to myaccount.google.com")
                                stepRow(n: "2", text: "Security → 2-Step Verification → App Passwords")
                                stepRow(n: "3", text: "Select app: Mail  |  Select device: iPhone")
                                stepRow(n: "4", text: "Copy the 16-character password shown")
                                stepRow(n: "5", text: "Paste it above (spaces are ignored)")
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield.fill").foregroundColor(Color(hex: "#2ECC71"))
                                    Text("Stored securely in iOS Keychain — never leaves your device")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 6)
                        }
                    }

                // ─────────────────────────────────────────────
                // MARK: OAuth Method (existing flow)
                // ─────────────────────────────────────────────
                } else {
                    if gmail.isConfigured {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Client ID Configured")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(gmail.savedClientID().prefix(30) + "...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button(action: { clientIDText = gmail.savedClientID() }) {
                            Label("Change Client ID", systemImage: "pencil")
                                .foregroundColor(Color(hex: "#6C63FF"))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your Google OAuth Client ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("xxxxx.apps.googleusercontent.com",
                                     text: $clientIDText)
                                .font(.caption)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                            Button(action: saveClientID) {
                                Label("Save Client ID", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(clientIDText.isEmpty
                                                ? Color.gray
                                                : Color(hex: "#6C63FF"))
                                    .cornerRadius(8)
                            }
                            .disabled(clientIDText.isEmpty)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }

                    // Show text field to change if configured
                    if gmail.isConfigured && !clientIDText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("xxxxx.apps.googleusercontent.com",
                                     text: $clientIDText)
                                .font(.caption)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                            Button(action: saveClientID) {
                                Label("Update Client ID", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(Color(hex: "#6C63FF"))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }

                    if showClientIDSaved {
                        Text("✅ Client ID saved successfully!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Button(action: { showSetupGuide = true }) {
                        Label("How to get Client ID?",
                              systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#6C63FF"))
                    }
                }

                // ── Connection Status & OAuth Actions ─────────
                if emailMethod == "oauth" {
                Section {
                    if gmail.isConnected {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.green).font(.title2)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Google Account Connected")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text(gmail.userEmail)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        Button(action: { gmail.startLogin() }) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue).frame(width: 20)
                                Text("Sign in with Google").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ── Actions (when connected) ──────────────────
                if gmail.isConnected {
                    Section(header: Text("Import")) {
                        // Incremental fetch — only new emails since last run
                        Button(action: fetchEmails) {
                            HStack {
                                if gmail.isFetching {
                                    ProgressView().scaleEffect(0.8).frame(width: 20)
                                } else {
                                    Image(systemName: "envelope.badge")
                                        .foregroundColor(Color(hex: "#6C63FF"))
                                        .frame(width: 20)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gmail.isFetching ? "Scanning emails..." : "Fetch New Emails")
                                    Text(fetchSubtitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(gmail.isFetching)

                        // Live progress bar
                        if gmail.isFetching && gmail.totalEmailCount > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: gmail.fetchProgress)
                                    .tint(Color(hex: "#6C63FF"))
                                Text("\(gmail.processedEmailCount) of \(gmail.totalEmailCount) emails processed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        // Full re-scan from configured start year
                        Button(action: rescanAllEmails) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Re-scan All History")
                                    Text("Re-imports from \(gmail.configuredStartYear) onwards")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(gmail.isFetching)

                        // Year picker for history start
                        Button(action: {
                            selectedStartYear = gmail.configuredStartYear
                            showYearPicker    = true
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("History Start Year")
                                    Text("Currently: \(gmail.configuredStartYear)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .disabled(gmail.isFetching)

                        Button(action: { showManualImport = true }) {
                            Label("Paste Email Manually",
                                  systemImage: "doc.text")
                        }
                    }

                    Section(header: Text("Status")) {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(gmail.fetchStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                        if let last = gmail.lastFetchDate {
                            HStack {
                                Text("Last Fetched")
                                Spacer()
                                Text(last.formatted(
                                    .relative(presentation: .numeric)
                                ))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Text("Total Imported")
                            Spacer()
                            Text("\(gmail.importedCount)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Bank Email Filters")) {
                        Text("Automatically detects emails from:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(["HDFC Bank", "ICICI Bank", "SBI", "Axis Bank",
                                 "Kotak Bank", "Yes Bank", "IndusInd Bank"], id: \.self) { bank in
                            Text(bank)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button(role: .destructive,
                               action: { gmail.disconnect() }) {
                            Label("Disconnect Gmail",
                                  systemImage: "xmark.circle")
                        }
                    }
                } // end OAuth `if gmail.isConnected`

                } // end `if emailMethod == "oauth"`

                // ── Setup Guide (always visible) ──────────────
                Section {
                    Button(action: { showSetupGuide = true }) {
                        Label(emailMethod == "imap" ? "App Password Help" : "Gmail Setup Guide",
                              systemImage: "questionmark.circle")
                            .foregroundColor(Color(hex: "#6C63FF"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Email Import")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showManualImport) {
                ManualEmailImportView()
            }
            .sheet(isPresented: $showSetupGuide) {
                GmailSetupGuideView()
            }
            .sheet(isPresented: $showYearPicker) { [self] in
                YearPickerSheet(selectedYear: $selectedStartYear) { year in
                    if emailMethod == "imap" {
                        imap.configuredStartYear = year
                    } else {
                        gmail.configuredStartYear = year
                    }
                }
            }
            .alert("Fetch Complete",
                   isPresented: $showFetchResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fetchCount > 0
                     ? "Found \(fetchCount) emails with transactions. Check your Dashboard!"
                     : "No new bank transactions found in Gmail.")
            }
        }
    }

    // MARK: - IMAP Helpers

    private var imapFetchSubtitle: String {
        if let last = imap.lastFetchDate {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return "Last fetched \(fmt.localizedString(for: last, relativeTo: Date()))"
        }
        return "First run — fetches from \(imap.configuredStartYear) onwards"
    }

    private func verifyAndConnectIMAP() {
        imapVerifying = true
        imapVerifyMsg = ""
        imap.testConnection(email: imapEmail, appPassword: imapPassword) { success, msg in
            DispatchQueue.main.async {
                self.imapVerifying = false
                self.imapVerifyMsg = success ? "" : msg
                if success {
                    self.imap.saveCredentials(email: self.imapEmail,
                                             appPassword: self.imapPassword)
                    self.imapEmail    = ""
                    self.imapPassword = ""
                }
            }
        }
    }

    private func imapFetchEmails() {
        imap.fetchBankEmails(store: store) { count in
            fetchCount      = count
            showFetchResult = true
        }
    }

    private func imapRescanAll() {
        imap.resetProcessedEmails()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            imap.fetchBankEmails(store: store, fullRescan: true) { count in
                fetchCount      = count
                showFetchResult = true
            }
        }
    }

    private func stepRow(n: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color(hex: "#6C63FF"))
                .clipShape(Circle())
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - OAuth Helpers

    private var fetchSubtitle: String {
        if let last = gmail.lastFetchDate {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return "Last fetched \(fmt.localizedString(for: last, relativeTo: Date()))"
        }
        return "First run — fetches from \(gmail.configuredStartYear) onwards"
    }

    // ── OAuth Actions ─────────────────────────────────────────
    private func saveClientID() {
        gmail.saveClientID(clientIDText)
        showClientIDSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showClientIDSaved = false
            clientIDText = ""
        }
    }

    private func rescanAllEmails() {
        gmail.resetProcessedEmails()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            gmail.fetchBankEmails(store: store, fullRescan: true) { count in
                fetchCount      = count
                showFetchResult = true
            }
        }
    }

    private func fetchEmails() {
        gmail.fetchBankEmails(store: store) { count in
            fetchCount      = count
            showFetchResult = true
        }
    }
}

// MARK: - Manual Email Import
struct ManualEmailImportView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    @State private var emailText  = ""
    @State private var sender     = ""
    @State private var result     = ""
    @State private var showResult = false
    @State private var parsed: Transaction? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Sender Email (Optional)")) {
                    TextField("e.g. alerts@hdfcbank.net", text: $sender)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Section(header: Text("Paste Email Content")) {
                    TextEditor(text: $emailText)
                        .frame(minHeight: 150)

                    Text("Copy the email body from your Gmail app and paste here")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let txn = parsed {
                    Section(header: Text("Parsed Transaction")) {
                        HStack {
                            Image(systemName: txn.category.icon)
                                .foregroundColor(txn.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(txn.merchant)
                                    .fontWeight(.medium)
                                Text(txn.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(txn.type == .debit
                                 ? "-₹\(Int(txn.amount))"
                                 : "+₹\(Int(txn.amount))")
                                .fontWeight(.bold)
                                .foregroundColor(txn.type.color)
                        }

                        Button(action: saveParsed) {
                            Label("Save Transaction",
                                  systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }

                if showResult {
                    Section {
                        Text(result)
                            .foregroundColor(
                                result.contains("✅") ? .green : .red
                            )
                    }
                }

                Section {
                    Button(action: parseEmail) {
                        Label("Parse Email", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Color(hex: "#6C63FF"))
                    }
                    .disabled(emailText.isEmpty)
                }
            }
            .navigationTitle("Import Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func parseEmail() {
        showResult = false
        parsed     = nil
        let txn = EmailParserService.shared.parse(
            emailBody: emailText,
            sender:    sender.isEmpty ? "BANK" : sender,
            date:      Date()
        )
        if let txn {
            parsed = txn
        } else {
            result     = "❌ Could not parse. Make sure it's a bank transaction email."
            showResult = true
        }
    }

    private func saveParsed() {
        guard let txn = parsed else { return }
        store.addTransaction(txn)
        result     = "✅ Transaction saved!"
        showResult = true
        parsed     = nil
        emailText  = ""
    }
}

// MARK: - Setup Guide
struct GmailSetupGuideView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What You Need")) {
                    Label("Free Google Account", systemImage: "checkmark.circle")
                    Label("Google Cloud Console access (free)",
                          systemImage: "checkmark.circle")
                    Label("5 minutes setup time",
                          systemImage: "checkmark.circle")
                }

                Section(header: Text("Step 1 — Google Cloud Console")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Go to console.cloud.google.com")
                        Text("2. Create a new project named 'SpendTracker'")
                        Text("3. Go to APIs & Services → Enable APIs")
                        Text("4. Search 'Gmail API' → Enable it")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Step 2 — OAuth Credentials")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Go to APIs & Services → Credentials")
                        Text("2. Create Credentials → OAuth Client ID")
                        Text("3. Application type: iOS")
                        Text("4. Bundle ID: com.yourname.spendtracker")
                        Text("5. Copy the Client ID")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Step 3 — Add to App")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open GmailService.swift")
                        Text("2. Find: YOUR_GOOGLE_CLIENT_ID")
                        Text("3. Replace with your Client ID")
                        Text("4. Rebuild and reinstall app")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Step 4 — Connect in App")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open SpendTracker → Gmail tab")
                        Text("2. Tap 'Connect with Gmail'")
                        Text("3. Sign in with Google")
                        Text("4. Allow readonly access")
                        Text("5. Tap 'Fetch Bank Emails Now'")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Privacy")) {
                    Text("SpendTracker only requests READ-ONLY access to your Gmail. It never sends emails, never modifies anything, and all data stays on your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gmail Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Year Picker Sheet
struct YearPickerSheet: View {
    @Binding var selectedYear: Int
    @Environment(\.dismiss) var dismiss
    let onSave: (Int) -> Void

    private let years: [Int] = {
        let current = Calendar.current.component(.year, from: Date())
        return Array(2015...current).reversed()
    }()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Choose how far back to scan your Gmail for bank transaction emails.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Picker("Start Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)

                Text("Emails from January \(selectedYear) onwards will be scanned on Full Re-scan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("History Start Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(selectedYear)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
