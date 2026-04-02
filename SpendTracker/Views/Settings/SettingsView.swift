import SwiftUI

// MARK: - Settings View (Ultra Lightweight)
struct SettingsView: View {
    @EnvironmentObject var store:      TransactionStore
    @EnvironmentObject var smsService: SMSReaderService
    @State private var showClearAlert  = false
    @State private var showAddBudget   = false
    @State private var txnCount:   Int = 0
    @State private var monthCount: Int = 0
    @State private var firebaseProjectID: String = ""
    @State private var firebaseAPIKey:    String = ""
    @State private var firebaseSaved:     Bool   = false

    var body: some View {
        NavigationView {
            List {

                // ── SMS ───────────────────────────
                Section(header: Text("SMS Monitoring")) {
                    Toggle(isOn: $smsService.isMonitoring) {
                        Label("Auto Sync",
                              systemImage: "arrow.clockwise.circle")
                    }
                    .onChange(of: smsService.isMonitoring) { val in
                        val ? smsService.startMonitoring()
                            : smsService.stopMonitoring()
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(smsService.syncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // ── Budgets ───────────────────────
                Section(header: Text("Budgets")) {
                    ForEach(
                        store.budgets
                            .sorted(by: { $0.value > $1.value }),
                        id: \.key
                    ) { cat, amt in
                        NavigationLink(
                            destination: BudgetDetailView(category: cat)
                        ) {
                            HStack {
                                Image(systemName: cat.icon)
                                    .foregroundColor(cat.color)
                                    .frame(width: 22)
                                Text(cat.rawValue)
                                Spacer()
                                Text("₹\(Int(amt))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Button(action: { showAddBudget = true }) {
                        Label("Add Budget", systemImage: "plus.circle")
                    }
                }

                // ── Stats ─────────────────────────
                Section(header: Text("Data")) {
                    HStack {
                        Text("All Transactions")
                        Spacer()
                        Text("\(txnCount)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("This Month")
                        Spacer()
                        Text("\(monthCount)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Storage")
                        Spacer()
                        Text(FirestoreService.shared.firebaseUID != nil ? "Local + Firebase" : "Local Only")
                            .font(.caption)
                            .foregroundColor(FirestoreService.shared.firebaseUID != nil ? .green : .secondary)
                    }
                    Button(role: .destructive,
                           action: { showClearAlert = true }) {
                        Label("Clear All Data", systemImage: "trash")
                    }
                }

                // ── Firebase Sync ─────────────────
                Section(header: Text("Cloud Sync (Firebase)")) {
                    if FirestoreService.shared.firebaseUID != nil {
                        HStack {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundColor(.green)
                            Text("Syncing to Firebase")
                                .foregroundColor(.green)
                        }
                    }
                    TextField("Firebase Project ID", text: $firebaseProjectID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Web API Key", text: $firebaseAPIKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button(action: saveFirebaseConfig) {
                        Label(firebaseSaved ? "Saved ✅" : "Save Config",
                              systemImage: firebaseSaved ? "checkmark.circle" : "icloud.and.arrow.up")
                    }
                    .disabled(firebaseProjectID.isEmpty || firebaseAPIKey.isEmpty)
                }

                // ── About ─────────────────────────
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Banks")
                        Spacer()
                        Text("25+ supported").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Privacy")
                        Spacer()
                        Text(FirestoreService.shared.firebaseUID != nil
                             ? "Your Firebase only"
                             : "No data uploaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .onAppear { loadCounts() }
            .alert("Clear All Data?", isPresented: $showClearAlert) {
                Button("Clear", role: .destructive) {
                    store.clearAllData()
                    loadCounts()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all transactions. Cannot be undone.")
            }
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView()
            }
        }
    }

    private func loadCounts() {
        txnCount   = store.transactions.count
        monthCount = store.transactions(for: Date()).count
        firebaseProjectID = UserDefaults.standard.string(forKey: "firestore_project_id") ?? ""
        firebaseAPIKey    = UserDefaults.standard.string(forKey: "firestore_api_key") ?? ""
    }

    private func saveFirebaseConfig() {
        let pid = firebaseProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = firebaseAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty, !key.isEmpty else { return }
        UserDefaults.standard.set(pid, forKey: "firestore_project_id")
        UserDefaults.standard.set(key, forKey: "firestore_api_key")
        withAnimation { firebaseSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.firebaseSaved = false }
        }
    }
}

// MARK: - Budget Detail
struct BudgetDetailView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    let category: SpendCategory
    @State private var text = ""

    var body: some View {
        Form {
            Section(header: Text("Category")) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(category.color)
                    Text(category.rawValue)
                }
            }

            Section(header: Text("Monthly Limit")) {
                HStack {
                    Text("₹")
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                }
            }

            Section {
                Button("Save") {
                    if let val = Double(text), val > 0 {
                        store.setBudget(val, for: category)
                    }
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.blue)
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            text = String(Int(store.budgets[category] ?? 0))
        }
    }
}

// MARK: - Add Budget
struct AddBudgetView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    @State private var category = SpendCategory.food
    @State private var text     = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section(header: Text("Monthly Limit")) {
                    HStack {
                        Text("₹")
                        TextField("0", text: $text)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let val = Double(text), val > 0 {
                            store.setBudget(val, for: category)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}
