import SwiftUI

// MARK: - Gmail View
struct GmailView: View {
    @EnvironmentObject var store:  TransactionStore
    @StateObject private var gmail = GmailService.shared
    @State private var showManualImport  = false
    @State private var showSetupGuide    = false
    @State private var fetchCount        = 0
    @State private var showFetchResult   = false
    @State private var showYearPicker    = false
    @State private var selectedStartYear = Calendar.current.component(.year, from: Date()) - 2
    @State private var clientIDText      = ""

    var body: some View {
        NavigationView {
            List {

                // ── One-time Client ID setup ───────────────────
                if !gmail.isConfigured {
                    Section(header: Text("One-time Setup")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter your Google OAuth Client ID once to enable Gmail sign-in.")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("xxxx.apps.googleusercontent.com", text: $clientIDText)
                                .font(.caption)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                            Button(action: saveClientID) {
                                Label("Save Client ID", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(clientIDText.isEmpty ? Color.gray : Color(hex: "#6C63FF"))
                                    .cornerRadius(8)
                            }
                            .disabled(clientIDText.isEmpty)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        Button(action: { showSetupGuide = true }) {
                            Label("How to get a Client ID", systemImage: "questionmark.circle")
                                .font(.caption).foregroundColor(Color(hex: "#6C63FF"))
                        }
                    }
                }

                // ── Sign in with Google ────────────────────────
                if gmail.isConfigured && !gmail.isConnected {
                    Section {
                        Button(action: { gmail.startLogin() }) {
                            HStack(spacing: 14) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                                    .frame(width: 36, height: 36)
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        Text("Read-only access — SpendTracker never sends emails or modifies your inbox.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                // ── Connected state ────────────────────────────
                if gmail.isConnected {
                    Section {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "checkmark.circle.fill")
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
                    }

                    Section(header: Text("Import")) {
                        Button(action: fetchEmails) {
                            HStack {
                                if gmail.isFetching {
                                    ProgressView().scaleEffect(0.8).frame(width: 20)
                                } else {
                                    Image(systemName: "envelope.badge")
                                        .foregroundColor(Color(hex: "#6C63FF")).frame(width: 20)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gmail.isFetching ? "Scanning emails…" : "Fetch New Emails")
                                    Text(fetchSubtitle).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(gmail.isFetching)

                        if gmail.isFetching && gmail.totalEmailCount > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: gmail.fetchProgress).tint(Color(hex: "#6C63FF"))
                                Text("\(gmail.processedEmailCount) of \(gmail.totalEmailCount) emails processed")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        Button(action: rescanAllEmails) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.orange).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Re-scan All History")
                                    Text("Re-imports from \(gmail.configuredStartYear) onwards")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(gmail.isFetching)

                        Button(action: {
                            selectedStartYear = gmail.configuredStartYear
                            showYearPicker    = true
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("History Start Year")
                                    Text("Currently: \(gmail.configuredStartYear)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .disabled(gmail.isFetching)

                        Button(action: { showManualImport = true }) {
                            Label("Paste Email Manually", systemImage: "doc.text")
                        }
                    }

                    Section(header: Text("Status")) {
                        HStack {
                            Text("Status"); Spacer()
                            Text(gmail.fetchStatus)
                                .font(.caption).foregroundColor(.secondary)
                                .lineLimit(2).multilineTextAlignment(.trailing)
                        }
                        if let last = gmail.lastFetchDate {
                            HStack {
                                Text("Last Fetched"); Spacer()
                                Text(last.formatted(.relative(presentation: .numeric)))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Text("Total Imported"); Spacer()
                            Text("\(gmail.importedCount)").foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Bank Email Filters")) {
                        Text("Automatically detects emails from:")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(["HDFC Bank", "ICICI Bank", "SBI", "Axis Bank",
                                 "Kotak Bank", "Yes Bank", "IndusInd Bank"], id: \.self) { bank in
                            Text(bank).font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button(role: .destructive, action: { gmail.disconnect() }) {
                            Label("Disconnect Gmail", systemImage: "xmark.circle")
                        }
                    }
                }

                // ── Setup Guide ────────────────────────────────
                Section {
                    Button(action: { showSetupGuide = true }) {
                        Label("Gmail Setup Guide", systemImage: "questionmark.circle")
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
            .sheet(isPresented: $showYearPicker) {
                YearPickerSheet(selectedYear: $selectedStartYear) { year in
                    gmail.configuredStartYear = year
                }
            }
            .alert("Fetch Complete", isPresented: $showFetchResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fetchCount > 0
                     ? "Found \(fetchCount) emails with transactions. Check your Dashboard!"
                     : "No new bank transactions found in Gmail.")
            }
        }
    }

    // MARK: - Helpers

    private var fetchSubtitle: String {
        if let last = gmail.lastFetchDate {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return "Last fetched \(fmt.localizedString(for: last, relativeTo: Date()))"
        }
        return "First run — fetches from \(gmail.configuredStartYear) onwards"
    }

    private func saveClientID() {
        gmail.saveClientID(clientIDText)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { clientIDText = "" }
    }

    private func fetchEmails() {
        gmail.fetchBankEmails(store: store) { count in
            fetchCount      = count
            showFetchResult = true
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
                                 ? "-â‚¹\(Int(txn.amount))"
                                 : "+â‚¹\(Int(txn.amount))")
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
                                result.contains("âœ…") ? .green : .red
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
            result     = "âŒ Could not parse. Make sure it's a bank transaction email."
            showResult = true
        }
    }

    private func saveParsed() {
        guard let txn = parsed else { return }
        store.addTransaction(txn)
        result     = "âœ… Transaction saved!"
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

                Section(header: Text("Step 1 â€” Google Cloud Console")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Go to console.cloud.google.com")
                        Text("2. Create a new project named 'SpendTracker'")
                        Text("3. Go to APIs & Services â†’ Enable APIs")
                        Text("4. Search 'Gmail API' â†’ Enable it")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Step 2 â€” OAuth Credentials")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Go to APIs & Services â†’ Credentials")
                        Text("2. Create Credentials â†’ OAuth Client ID")
                        Text("3. Application type: iOS")
                        Text("4. Bundle ID: com.yourname.spendtracker")
                        Text("5. Copy the Client ID")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("Step 3 â€” Add to App")) {
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

                Section(header: Text("Step 4 â€” Connect in App")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open SpendTracker â†’ Gmail tab")
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
