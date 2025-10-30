import SwiftUI

struct TransactionEditor: View {
    enum PayeeInputMode { case picker, custom }

    var transaction: Transaction?
    var initialAccountId: String?
    var onSave: (Transaction) -> Void
    
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: String] = [:]
    @State private var payees: [Payee] = []
    @State private var errorMessage: String?
    
    @State private var date: Date
    @State private var amountString: String
    @State private var isNegative: Bool
    @State private var selectedPayeeId: String
    @State private var selectedTransferId: String?
    @State private var customPayee: String
    @State private var payeeMode: PayeeInputMode
    @State private var notes: String
    @State private var categoryId: String?
    @State private var selectedAccountId: String

    init(transaction: Transaction?, initialAccountId: String?, onSave: @escaping (Transaction) -> Void) {
        self.transaction = transaction
        self.initialAccountId = initialAccountId
        self.onSave = onSave

        if let t = transaction {
            // Editing an existing transaction: Initialize state from the transaction object
            _date = State(initialValue: Self.parseDate(t.date) ?? Date())
            _amountString = State(initialValue: Self.formatAmountForDisplay(abs(t.amount ?? 0)))
            _isNegative = State(initialValue: (t.amount ?? 0) < 0)
            
            if let payeeId = t.payee, !payeeId.isEmpty {
                _selectedPayeeId = State(initialValue: payeeId)
                _payeeMode = State(initialValue: .picker)
                _customPayee = State(initialValue: "")
            } else if let payeeName = t.payee_name, !payeeName.isEmpty {
                _customPayee = State(initialValue: payeeName)
                _payeeMode = State(initialValue: .custom)
                _selectedPayeeId = State(initialValue: "")
            } else {
                _payeeMode = State(initialValue: .picker)
                _selectedPayeeId = State(initialValue: "")
                _customPayee = State(initialValue: "")
            }
            
            _notes = State(initialValue: t.notes ?? "")
            _categoryId = State(initialValue: t.category)
            _selectedAccountId = State(initialValue: t.account)
            _selectedTransferId = State(initialValue: t.transfer_id)
        } else {
            // Creating a new transaction: Initialize with default values
            _date = State(initialValue: Date())
            _amountString = State(initialValue: "0.00")
            _isNegative = State(initialValue: true)
            _selectedPayeeId = State(initialValue: "")
            _customPayee = State(initialValue: "")
            _payeeMode = State(initialValue: .picker)
            _notes = State(initialValue: "")
            _categoryId = State(initialValue: nil)
            _selectedAccountId = State(initialValue: initialAccountId ?? "")
            _selectedTransferId = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                
                if accounts.isEmpty && errorMessage == nil {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    formContent
                }
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .task { await load() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(AppTheme.accent)
    }
    
    private var formContent: some View {
        Form {
            Section("Account") {
                Picker("Account", selection: $selectedAccountId) {
                    ForEach(accounts, id: \.id) { acc in
                        Text(acc.name + (acc.offbudget ? " (Off-Budget)" : "")).tag(acc.id)
                    }
                }
            }
            .listRowBackground(Color.primary.opacity(0.05))
            
            Section("Details") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                
                HStack {
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    
                    Picker("Type", selection: $isNegative) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                
                Picker("Payee", selection: $payeeMode) {
                    Text("Choose").tag(PayeeInputMode.picker)
                    Text("Custom").tag(PayeeInputMode.custom)
                }
                .pickerStyle(.segmented)

                if payeeMode == .picker {
                    Picker("Payee", selection: $selectedPayeeId) {
                        Text("None").tag("")
                        ForEach(payees, id: \.id) { payee in
                            Text(payee.name).tag(payee.id)
                        }
                    }
                    .onChange(of: selectedPayeeId) { oldValue, newValue in
                        selectedTransferId = payees.first(where: { $0.id == newValue })?.transfer_acct
                    }
                } else {
                    TextField("Payee Name", text: $customPayee)
                }
                
                Picker("Category", selection: $categoryId) {
                    Text("None").tag(String?.none)
                    ForEach(categoriesById.sorted { $0.value < $1.value }, id: \.key) { key, value in
                        Text(value).tag(String?.some(key))
                    }
                }
                
                TextField("Notes", text: $notes)
            }
            .listRowBackground(Color.primary.opacity(0.05))
        }
        .scrollContentBackground(.hidden)
    }
    
    private func buildTransaction() -> Transaction {
        let units = parseAmountFromDisplay(amountString)
        let signed = isNegative ? -abs(units) : abs(units)
        
        let payeeId: String? = payeeMode == .picker ? (selectedPayeeId.isEmpty ? nil : selectedPayeeId) : nil
        let payeeName: String? = payeeMode == .custom ? (customPayee.isEmpty ? nil : customPayee) : nil
        
        return Transaction(
            id: transaction?.id,
            account: selectedAccountId,
            date: Self.formatDate(date),
            amount: signed,
            payee: payeeId,
            payee_name: payeeName,
            imported_payee: nil,
            category: categoryId,
            notes: notes.isEmpty ? nil : notes,
            imported_id: nil,
            transfer_id: selectedTransferId,
            cleared: false, subtransactions: nil
        )
    }

    private func save() {
        Task {
            do {
                let built = buildTransaction()
                if let id = built.id {
                    try await client().updateTransaction(transactionId: id, transaction: built)
                } else {
                    try await client().createTransaction(accountId: built.account, transaction: built, runTransfers: (built.transfer_id != nil))
                }
                onSave(built)
                dismiss()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
    
    private func client() throws -> ActualAPIClient {
        try ActualAPIClient(
            baseURLString: appState.baseURLString,
            apiKey: appState.apiKey,
            syncId: appState.syncId,
            budgetEncryptionPassword: appState.budgetEncryptionPassword,
            isDemoMode: appState.isDemoMode
        )
    }

    private func load() async {
        do {
            async let accs = try client().fetchAccounts()
            async let cats = try client().fetchCategories()
            async let pays = try client().fetchPayees()
            let (a, c, p) = try await (accs, cats, pays)
            await MainActor.run {
                accounts = a.filter { !$0.closed }
                categoriesById = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0.name) })
                payees = p.sorted { $0.name < $1.name }
                
                if transaction == nil && selectedAccountId.isEmpty {
                    selectedAccountId = initialAccountId ?? accounts.first?.id ?? ""
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private static func parseDate(_ str: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: str)
    }
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    private static func formatAmountForDisplay(_ amount: Int) -> String {
        String(format: "%.2f", Double(amount) / 100.0)
    }
    private func parseAmountFromDisplay(_ display: String) -> Int {
        Int((Double(display.replacingOccurrences(of: ",", with: ".")) ?? 0.0) * 100)
    }
}
