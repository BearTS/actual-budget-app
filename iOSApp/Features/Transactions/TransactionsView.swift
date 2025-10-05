import SwiftUI

struct TransactionsView: View {
    let account: Account
    @EnvironmentObject private var appState: AppState
    @State private var transactions: [Transaction] = []
    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: String] = [:]
    @State private var payeesById: [String: Payee] = [:]
    @State private var errorMessage: String?
    
    @State private var activeSheet: SheetType?

    var sortedTransactions: [Transaction] {
        transactions.sorted { ($0.date) > ($1.date) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                ForEach(sortedTransactions, id: \.id) { tx in
                    TransactionRow(
                        transaction: tx,
                        accounts: accounts,
                        payeesById: payeesById,
                        categoriesById: categoriesById,
                        currencyCode: appState.currencyCode,
                        onEdit: { t in activeSheet = .edit(t) },
                        onDelete: { t in Task { await delete(t) } }
                    )
                    .contextMenu { contextMenuItems(for: tx) }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .add
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
            Button("View Logs") {
                AppLogger.shared.log("User tapped View Logs from Transactions error", level: .info, context: "TransactionsView")
                errorMessage = nil
                NotificationCenter.default.post(name: NSNotification.Name("OpenLogsView"), object: nil)
            }
        } message: { Text(errorMessage ?? "") }
    }
    
    @ViewBuilder
    private func contextMenuItems(for tx: Transaction) -> some View {
        if let destAccount = transferDestinationAccount(tx) {
            NavigationLink {
                TransactionsView(account: destAccount)
            } label: {
                Label("Go to Transfer Account", systemImage: "arrow.right.arrow.left.circle")
            }
        }
        
        Button(role: .destructive) {
            Task { await delete(tx) }
        } label: {
            Label("Delete Transaction", systemImage: "trash")
        }
    }
    
    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 16) {
             Image(systemName: (tx.amount ?? 0) < 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.title2)
                .foregroundColor((tx.amount ?? 0) < 0 ? .secondary : AppTheme.positive)

            VStack(alignment: .leading) {
                Text(payeeText(tx))
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                if let categoryName = categoryName(tx.category), !categoryName.isEmpty {
                    Text(categoryName)
                        .font(AppTheme.Fonts.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(formattedSignedAmount(tx.amount))
                    .font(AppTheme.Fonts.body.monospacedDigit())
                    .foregroundStyle((tx.amount ?? 0) < 0 ? .primary : AppTheme.positive)
                Text(tx.date)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func delete(_ tx: Transaction) async {
        guard let txId = tx.id else { return }
        transactions.removeAll { $0.id == txId }
        do {
            try await client().deleteTransaction(transactionId: txId)
            await loadAll()
        } catch {
            AppLogger.shared.log(error: error, context: "TransactionsView.delete")
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func transferDestinationAccount(_ tx: Transaction) -> Account? {
        if let payeeId = tx.payee,
           let p = payeesById[payeeId],
           let destAcctId = p.transfer_acct {
            return accounts.first { $0.id == destAcctId }
        }
        return nil
    }

    private func loadAll() async {
        do {
            async let accs = try client().fetchAccounts()
            async let cats = try client().fetchCategories()
            async let payees = try client().fetchPayees()
            async let txs = try client().fetchTransactions(accountId: account.id, since: defaultSinceDate())
            let (accountList, categories, payeesList, list) = try await (accs, cats, payees, txs)
            
            let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
            let payeeMap = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
            
            await MainActor.run {
                self.accounts = accountList
                categoriesById = catMap
                payeesById = payeeMap
                transactions = list
            }
        } catch {
            AppLogger.shared.log(error: error, context: "TransactionsView.loadAll")
            await MainActor.run { errorMessage = error.localizedDescription }
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
    
    private func formattedSignedAmount(_ amount: Int?) -> String {
        return CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func categoryName(_ id: String?) -> String? {
        guard let id else { return nil }
        return categoriesById[id]
    }

    private func payeeText(_ tx: Transaction) -> String {
        if let account = transferDestinationAccount(tx) {
            return "Transfer to: \(account.name)"
        }
        if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
        if let n = tx.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }
    
    private func defaultSinceDate() -> String {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "yyyy-MM-dd"; return f.string(from: start)
    }
}