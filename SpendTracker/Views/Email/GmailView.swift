import SwiftUI

// MARK: - Gmail View
struct GmailView: View {
    @EnvironmentObject var store:  TransactionStore
    @StateObject private var gmail = GmailService.shared
    @State private var showManualImport = false
    @State private var showSetupGuide   = false
    @State private var fetchCount       = 0
    @State private var showFetchResult  = false

    var body: some View {
        NavigationView {
            List {

                // ── Connection Status ─────────────────────────
                Section {
                    if gmail.isConnected {
                        connectedView
                    } else {
                        notConnectedView
                    }
                }

                // ── Actions (when connected) ──────────────────
                if gmail.isConnected {
                    Section(header: Text("Import")) {
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
                                    Text(gmail.isFetching ? "Scanning..." : "Fetch Bank Emails")
                                    Text("Last 2 months only")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(gmail.isFetching)

                        Button(action: rescanAllEmails) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Re-scan Last 2 Months")
                                    Text("Clears cache and re-imports")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
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
                        bankList
                    }

                    Section {
                        Button(role: .destructive,
                               action: { gmail.disconnect() }) {
                            Label("Disconnect Gmail",
                                  systemImage: "xmark.circle")
                        }
                    }
                }

                // ── Setup Guide ───────────────────────────────
                Section {
                    Button(action: { showSetupGuide = true }) {
                        Label("Gmail Setup Guide",
                              systemImage: "questionmark.circle")
                            .foregroundColor(Color(hex: "#6C63FF"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gmail Import")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showManualImport) {
                ManualEmailImportView()
            }
            .sheet(isPresented: $showSetupGuide) {
                GmailSetupGuideView()
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

    // ── Connected View ────────────────────────────────────────
    private var connectedView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Gmail Connected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(gmail.userEmail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // ── Not Connected View ────────────────────────────────────
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "#6C63FF"))

            VStack(spacing: 6) {
                Text("Connect Gmail")
                    .font(.headline)
                Text("Automatically import bank transaction emails")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { gmail.startLogin() }) {
                HStack {
                    Image(systemName: "envelope.fill")
                    Text("Connect with Gmail")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "#6C63FF"))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Text("Only reads emails — never sends or modifies")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // ── Bank List ─────────────────────────────────────────────
    private var bankList: some View {
        VStack(alignment: .leading, spacing: 6) {
            let banks = [
                ("HDFC Bank",  "alerts@hdfcbank.net"),
                ("ICICI Bank", "credit_cards@icicibank.com"),
                ("SBI",        "sbiatm@sbi.co.in"),
                ("Axis Bank",  "alerts@axisbank.com"),
                ("Kotak",      "noreply@kotak.com"),
                ("All Banks",  "Subject keywords"),
            ]
            ForEach(banks, id: \.0) { bank in
                HStack {
                    Text(bank.0)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(bank.1)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // ── Fetch Emails ──────────────────────────────────────────
    private func rescanAllEmails() {
        gmail.resetProcessedEmails()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            fetchEmails()
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
                        Text("4. Bundle ID: com.munibk.spendtracker")
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
