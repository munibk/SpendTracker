import SwiftUI

// MARK: - Add Transaction View
struct AddTransactionView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    
    @State private var amount: String = ""
    @State private var merchant: String = ""
    @State private var category: SpendCategory = .others
    @State private var type: TransactionType = .debit
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var bankName: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    HStack {
                        Text("₹")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                    }
                    
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    TextField("Merchant / Description", text: $merchant)
                    
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Optional") {
                    TextField("Bank Name", text: $bankName)
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(amount.isEmpty || Double(amount) == nil)
                }
            }
        }
    }
    
    private func save() {
        guard let amountVal = Double(amount) else { return }
        let txn = Transaction(
            date: date,
            amount: amountVal,
            type: type,
            category: category,
            merchant: merchant.isEmpty ? "Manual Entry" : merchant,
            bankName: bankName.isEmpty ? "Manual" : bankName,
            isManual: true,
            note: note.isEmpty ? nil : note
        )
        store.addTransaction(txn)
        dismiss()
    }
}

// MARK: - Edit Transaction View
struct EditTransactionView: View {
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    
    let transaction: Transaction
    
    @State private var amount: String
    @State private var merchant: String
    @State private var category: SpendCategory
    @State private var type: TransactionType
    @State private var date: Date
    @State private var note: String
    
    init(transaction: Transaction) {
        self.transaction = transaction
        _amount = State(initialValue: String(transaction.amount))
        _merchant = State(initialValue: transaction.merchant)
        _category = State(initialValue: transaction.category)
        _type = State(initialValue: transaction.type)
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Transaction") {
                    HStack {
                        Text("₹")
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    TextField("Merchant", text: $merchant)
                    
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Details") {
                    Text("Bank: \(transaction.bankName)")
                        .foregroundColor(.secondary)
                    if let last4 = transaction.accountLast4 {
                        Text("Account: ••••\(last4)").foregroundColor(.secondary)
                    }
                    if transaction.cardType != .none {
                        HStack {
                            Text("Card Type:")
                            Spacer()
                            Text(transaction.cardType.rawValue)
                                .foregroundColor(
                                    transaction.cardType == .credit
                                    ? Color(hex: "#E74C3C")
                                    : Color(hex: "#E67E22")
                                )
                                .fontWeight(.semibold)
                        }
                    }
                    if let upi = transaction.upiId {
                        Text("UPI: \(upi)").foregroundColor(.secondary).font(.caption)
                    }
                    TextField("Note", text: $note)
                }
                
                Section {
                    Text(transaction.smsBody)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Original SMS")
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func save() {
        guard let amountVal = Double(amount) else { return }
        var updated = transaction
        updated.amount = amountVal
        updated.merchant = merchant
        updated.category = category
        updated.type = type
        updated.date = date
        updated.note = note.isEmpty ? nil : note
        store.updateTransaction(updated)
        
        // Save category override for future
        CategoryService.shared.setOverride(merchant: merchant, category: category)
        
        dismiss()
    }
}

// MARK: - Manual SMS Import View
struct ManualSMSImportView: View {
    @EnvironmentObject var smsService: SMSReaderService
    @EnvironmentObject var store: TransactionStore
    @Environment(\.dismiss) var dismiss
    
    @State private var smsText: String = ""
    @State private var parsedTransaction: Transaction? = nil
    @State private var showResult = false
    @State private var resultMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste your bank SMS below")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $smsText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    
                    Text("Example: \"HDFC Bank: Rs.500.00 debited from A/c XX1234 on 15-01-24 at SWIGGY. Avl bal: Rs.10,234.56\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding()
                
                if let txn = parsedTransaction {
                    // Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Parsed Transaction")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: txn.category.icon)
                                .foregroundColor(txn.category.color)
                            VStack(alignment: .leading) {
                                Text(txn.merchant)
                                    .fontWeight(.medium)
                                Text(txn.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(txn.type == .debit ? "-₹\(Int(txn.amount))" : "+₹\(Int(txn.amount))")
                                .fontWeight(.bold)
                                .foregroundColor(txn.type.color)
                        }
                        
                        HStack {
                            if let last4 = txn.accountLast4 { Text("Acct: ••\(last4)").font(.caption2) }
                            Spacer()
                            Text(txn.bankName).font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        
                        Button(action: {
                            store.addTransaction(txn)
                            resultMessage = "✅ Transaction saved!"
                            showResult = true
                            smsText = ""
                            parsedTransaction = nil
                        }) {
                            Label("Save Transaction", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#6C63FF"))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                if showResult {
                    Text(resultMessage)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding()
                }
                
                Button(action: parseSMS) {
                    Label("Parse SMS", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(!smsText.isEmpty ? Color(hex: "#6C63FF") : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(smsText.isEmpty)
                
                Spacer()
            }
            .navigationTitle("Import SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func parseSMS() {
        showResult = false
        if let txn = smsService.importManualSMS(smsText) {
            parsedTransaction = txn
            // Remove from store (it was added), we show preview first
            store.deleteTransaction(id: txn.id)
        } else {
            resultMessage = "❌ Could not parse this SMS. Is it a bank transaction SMS?"
            showResult = true
            parsedTransaction = nil
        }
    }
}
