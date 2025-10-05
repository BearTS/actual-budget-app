import SwiftUI
import Charts

struct AllTransactionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var transactions: [Transaction] = []
    @State private var accounts: [Account] = []
    @State private var payeesById: [String: Payee] = [:]
    @State private var categoriesById: [String: String] = [:]
    @State private var balancesById: [String: Int] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var onBudgetOnly: Bool = true
    @State private var filterGranularity: Granularity = .day
    @State private var filterValue: Int = 30
    
    @State private var activeSheet: SheetType?

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Days", week = "Weeks", month = "Months", year = "Years"
        var id: String { rawValue }
    }

    var filteredTransactions: [Transaction] {
        let onBudgetAccountIds = Set(accounts.filter { !$0.offbudget }.map { $0.id })
        let allAccountIds = Set(accounts.map { $0.id })
        let targetAccountIds = onBudgetOnly ? onBudgetAccountIds : allAccountIds
        
        return transactions
            .filter { targetAccountIds.contains($0.account) }
            .sorted { $0.date > $1.date }
    }

    private var listTransactions: [Transaction] {
        let since = sinceDateString()
        return filteredTransactions
            .filter { $0.date >= since }
            .filter { !isTransferToOnBudget($0) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                filtersBar
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())

                ForEach(listTransactions, id: \.id) { tx in
                    TransactionRow(
                        transaction: tx,
                        accounts: accounts,
                        payeesById: payeesById,
                        categoriesById: categoriesById,
                        currencyCode: appState.currencyCode,
                        onEdit: { t in activeSheet = .edit(t) },
                        onDelete: { t in Task { await delete(t) } }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("All Transactions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .add
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await load() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await load() } })
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func delete(_ tx: Transaction) async {
        guard let id = tx.id else { return }
        await MainActor.run {
            transactions.removeAll { $0.id == id }
        }
        do {
            try await client().deleteTransaction(transactionId: id)
        } catch {
            AppLogger.shared.log(error: error, context: "AllTransactionsView.delete")
            await MainActor.run { errorMessage = error.localizedDescription }
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
                Text(accounts.first { $0.id == tx.account }?.name ?? "Unknown Account")
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
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

    private var filtersBar: some View {
        GlassCard(cornerRadius: 0) {
            VStack(spacing: 16) {
                Toggle("On-budget only", isOn: $onBudgetOnly)
                    .tint(AppTheme.accent)
                
                Picker("Range", selection: $filterGranularity) {
                    ForEach(Granularity.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                
                Stepper("Last \(filterValue) \(filterGranularity.rawValue)", value: $filterValue, in: 1...365)
            }
            .foregroundColor(.primary)
        }
        .padding(.bottom)
    }

    private func isTransferToOnBudget(_ tx: Transaction) -> Bool {
        if let payeeId = tx.payee, let p = payeesById[payeeId], let destId = p.transfer_acct {
            if let dest = accounts.first(where: { $0.id == destId }) {
                return !dest.offbudget
            }
        }
        return false
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
        isLoading = true
        defer { isLoading = false }
        do {
            let since = sinceDateString()
            async let accs = try client().fetchAccounts()
            async let payees = try client().fetchPayees()
            async let cats = try client().fetchCategories()
            let (accountsList, payeesList, categories) = try await (accs, payees, cats)
            let mappingCats = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
            let mappingPayees = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
            let perAccountTxs = try await withThrowingTaskGroup(of: [Transaction].self) { group -> [[Transaction]] in
                for acc in accountsList {
                    group.addTask { try await client().fetchTransactions(accountId: acc.id, since: since) }
                }
                var results: [[Transaction]] = []
                for try await list in group { results.append(list) }
                return results
            }
            
            await MainActor.run {
                self.accounts = accountsList
                self.categoriesById = mappingCats
                self.payeesById = mappingPayees
                self.transactions = perAccountTxs.flatMap { $0 }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func sinceDateString() -> String {
        let cal = Calendar.current
        let now = Date()
        let fromDate: Date
        switch filterGranularity {
        case .day: fromDate = cal.date(byAdding: .day, value: -filterValue, to: now) ?? now
        case .week: fromDate = cal.date(byAdding: .weekOfYear, value: -filterValue, to: now) ?? now
        case .month: fromDate = cal.date(byAdding: .month, value: -filterValue, to: now) ?? now
        case .year: fromDate = cal.date(byAdding: .year, value: -filterValue, to: now) ?? now
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: fromDate)
    }

    private func formattedSignedAmount(_ amount: Int?) -> String {
        CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func payeeText(_ tx: Transaction) -> String {
        if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
        if let n = tx.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }
}