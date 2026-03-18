import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var store:      TransactionStore
    @EnvironmentObject var smsService: SMSReaderService
    @State private var showAddBudget     = false
    @State private var showClearConfirm  = false
    @State private var editingCategory:  SpendCategory? = nil

    var body: some View {
        NavigationView {
            List {

                // ── SMS Sync ──────────────────────────────────────
                Section(header: Text("SMS Monitoring")) {
                    HStack {
                        Label("Background Sync", systemImage: "arrow.clockwise.circle.fill")
                        Spacer()
                        Toggle("", isOn: $smsService.isMonitoring)
                            .labelsHidden()
                            .onChange(of: smsService.isMonitoring) { val in
                                if val { smsService.startMonitoring() }
                                else   { smsService.stopMonitoring()  }
                            }
                    }

                    HStack {
                        Label("Status", systemImage: "info.circle")
                        Spacer()
                        Text(smsService.syncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let last = smsService.lastSyncDate {
                        HStack {
                            Label("Last Sync", systemImage: "clock")
                            Spacer()
                            Text(last.formatted(.relative(presentation: .numeric)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ── Budgets ───────────────────────────────────────
                Section(header: Text("Monthly Budgets")) {
                    ForEach(
                        store.budgets.sorted(by: { $0.value > $1.value }),
                        id: \.key
                    ) { cat, budget in
                        Button(action: { editingCategory = cat }) {
                            HStack {
                                Image(systemName: cat.icon)
                                    .foregroundColor(cat.color)
                                    .frame(width: 24)
                                Text(cat.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("₹\(Int(budget))")
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button(action: { showAddBudget = true }) {
                        Label("Add Budget", systemImage: "plus.circle")
                            .foregroundColor(Color(hex: "#6C63FF"))
                    }
                }

                // ── Stats ─────────────────────────────────────────
                Section(header: Text("Data")) {
                    HStack {
                        Label("Total Transactions", systemImage: "list.bullet")
                        Spacer()
                        Text("\(store.transactions.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("This Month", systemImage: "calendar")
                        Spacer()
                        Text("\(store.transactions(for: Date()).count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Storage", systemImage: "lock.shield.fill")
                        Spacer()
                        Text("Local Only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive, action: { showClearConfirm = true }) {
                        Label("Clear All Data", systemImage: "trash.fill")
                    }
                }

                // ── About ─────────────────────────────────────────
                Section(header: Text("About")) {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Banks Supported", systemImage: "building.columns.fill")
                        Spacer()
                        Text("25+").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Privacy", systemImage: "hand.raised.fill")
                        Spacer()
                        Text("No data uploaded").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")

            // Budget editor sheet
            .sheet(item: $editingCategory) { cat in
                BudgetEditorView(category: cat)
            }
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView()
            }
            .alert("Clear All Data?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    withAnimation {
                        store.clearAllData()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all transactions and reports. This cannot be undone.")
            }
        }
    }
}

// MARK: - Budget Editor
struct BudgetEditorView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    let category: SpendCategory
    @State private var budgetText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundColor(category.color)
                        Text(category.rawValue)
                    }
                }
                Section(header: Text("Monthly Limit")) {
                    HStack {
                        Text("₹")
                        TextField("Amount", text: $budgetText)
                            .keyboardType(.numberPad)
                    }
                }
                Section {
                    let spent = store.transactions(
                        for: category, month: Date()
                    ).reduce(0) { $0 + $1.amount }
                    HStack {
                        Text("Spent this month")
                        Spacer()
                        Text("₹\(Int(spent))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let val = Double(budgetText), val > 0 {
                            store.setBudget(val, for: category)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                budgetText = String(Int(store.budgets[category] ?? 0))
            }
        }
    }
}

// MARK: - Add Budget
struct AddBudgetView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    @State private var category:   SpendCategory = .food
    @State private var budgetText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section(header: Text("Monthly Limit")) {
                    HStack {
                        Text("₹")
                        TextField("Amount", text: $budgetText)
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
                        if let val = Double(budgetText), val > 0 {
                            store.setBudget(val, for: category)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(budgetText.isEmpty)
                }
            }
        }
    }
}

// Make SpendCategory conform to Identifiable for .sheet(item:)
// (already conforms via id: String { rawValue } in Transaction.swift)
