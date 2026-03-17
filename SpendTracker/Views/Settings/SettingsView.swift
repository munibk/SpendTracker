import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var store: TransactionStore
    @EnvironmentObject var smsService: SMSReaderService
    @State private var showBudgetEditor = false
    @State private var showClearConfirm = false
    @State private var showAbout = false
    
    var body: some View {
        NavigationView {
            Form {
                // SMS Sync
                Section(header: Text("SMS Monitoring")) {
                    HStack {
                        Label("Background Sync", systemImage: "arrow.clockwise.circle.fill")
                        Spacer()
                        Toggle("", isOn: $smsService.isMonitoring)
                            .onChange(of: smsService.isMonitoring) { val in
                                if val { smsService.startMonitoring() }
                                else { smsService.stopMonitoring() }
                            }
                    }
                    if let last = smsService.lastSyncDate {
                        Label("Last Sync: \(last.formatted(.relative(presentation: .numeric)))", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { smsService.fetchNewMessages() }) {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                }
                
                // Budgets
                Section(header: Text("Monthly Budgets")) {
                    ForEach(store.budgets.sorted(by: { $0.value > $1.value }), id: \.key) { cat, budget in
                        NavigationLink(destination: BudgetEditorView(category: cat)) {
                            HStack {
                                Image(systemName: cat.icon).foregroundColor(cat.color)
                                Text(cat.rawValue)
                                Spacer()
                                Text("₹\(Int(budget))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Button("Add Budget") { showBudgetEditor = true }
                }
                
                // Data
                Section(header: Text("Data")) {
                    HStack {
                        Label("Total Transactions", systemImage: "list.bullet")
                        Spacer()
                        Text("\(store.transactions.count)")
                            .foregroundColor(.secondary)
                    }
                    Button(role: .destructive, action: { showClearConfirm = true }) {
                        Label("Clear All Data", systemImage: "trash.fill")
                    }
                }
                
                // About
                Section(header: Text("About")) {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Storage", systemImage: "internaldrive")
                        Spacer()
                        Text("Local Only").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Privacy", systemImage: "lock.shield.fill")
                        Spacer()
                        Text("No data leaves device").foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showBudgetEditor) {
                AddBudgetView()
            }
            .alert("Clear All Data?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    store.transactions.removeAll()
                    store.monthlyReports.removeAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all transactions and reports.")
            }
        }
    }
}

// Budget Editor
struct BudgetEditorView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    let category: SpendCategory
    @State private var budgetText: String = ""
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: category.icon).foregroundColor(category.color)
                    Text(category.rawValue)
                }
                HStack {
                    Text("₹")
                    TextField("Monthly Budget", text: $budgetText)
                        .keyboardType(.numberPad)
                }
            }
        }
        .navigationTitle("Edit Budget")
        .onAppear { budgetText = String(Int(store.budgets[category] ?? 0)) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    if let val = Double(budgetText) {
                        store.setBudget(val, for: category)
                    }
                    dismiss()
                }
            }
        }
    }
}

struct AddBudgetView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    @State private var category: SpendCategory = .food
    @State private var budgetText: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(SpendCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                HStack {
                    Text("₹")
                    TextField("Amount", text: $budgetText).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add Budget")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let val = Double(budgetText) { store.setBudget(val, for: category) }
                        dismiss()
                    }
                }
            }
        }
    }
}
