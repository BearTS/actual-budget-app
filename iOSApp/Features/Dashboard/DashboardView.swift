import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: String] = [:]
    @State private var payeesById: [String: Payee] = [:]
    @State private var transactions: [Transaction] = []
    @State private var errorMessage: String?
    
    @State private var activeSheet: SheetType?

    var onBudgetAccounts: [Account] { accounts.filter { !$0.offbudget } }
    private var recentFive: [Transaction] { recentNonTransferOnBudget().prefix(5).map { $0 } }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section {
                    VStack(spacing: 24) {
                        Text("Overview")
                            .font(AppTheme.Fonts.largeTitle)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Spent This Month")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(.secondary)
                                Text(formatMoney(spentThisMonth()))
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                metricCard(title: "Spent Today", value: spentToday())
                                metricCard(title: "Spent Last Month", value: spentLastMonth())
                                metricCard(title: "On-budget Accounts", value: onBudgetAccounts.count, isMoney: false)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section(header:
                    HStack {
                        Text("Recent Activity")
                            .font(AppTheme.Fonts.title)
                            .foregroundColor(.primary)
                        Spacer()
                        NavigationLink("View All") { AllTransactionsView() }
                            .foregroundColor(AppTheme.accent)
                    }
                ) {
                    if recentFive.isEmpty {
                        GlassCard {
                            Text("No recent transactions to show.")
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(recentFive, id: \.id) { tx in
                            TransactionRow(
                                transaction: tx,
                                accounts: accounts,
                                payeesById: payeesById,
                                categoriesById: categoriesById,
                                currencyCode: appState.currencyCode,
                                onEdit: { t in activeSheet = .edit(t) },
                                onDelete: { t in Task { await delete(t) } }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    Button {
                        activeSheet = .add
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Transaction")
                        }
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationBarHidden(true)
        .task { await load() }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await load() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await load() } })
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
            Button("View Logs") {
                AppLogger.shared.log("User tapped View Logs from Dashboard error", level: .info, context: "DashboardView")
                errorMessage = nil
                NotificationCenter.default.post(name: NSNotification.Name("OpenLogsView"), object: nil)
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }

    private var recentTransactionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(AppTheme.Fonts.title)
                    .foregroundColor(.primary)
                Spacer()
                NavigationLink("View All") { AllTransactionsView() }
                    .foregroundColor(AppTheme.accent)
            }
            
            let recent = recentNonTransferOnBudget().prefix(5)
            
            if recent.isEmpty {
                 GlassCard {
                     Text("No recent transactions to show.")
                         .font(AppTheme.Fonts.body)
                         .foregroundStyle(.secondary)
                         .frame(maxWidth: .infinity, minHeight: 100)
                 }
            } else {
                VStack(spacing: 12) {
                    ForEach(recent, id: \.id) { tx in
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
                }
            }
            
            Button {
                activeSheet = .add
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Transaction")
                }
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(.top)
        }
    }
    
    private func transactionRow(_ tx: Transaction) -> some View {
        HStack {
            Image(systemName: (tx.amount ?? 0) < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor((tx.amount ?? 0) < 0 ? .secondary : AppTheme.positive)
            
            VStack(alignment: .leading) {
                Text(payeeText(tx))
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                Text(tx.date)
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatMoney(abs(tx.amount ?? 0)))
                .font(AppTheme.Fonts.body.monospacedDigit())
                .foregroundColor((tx.amount ?? 0) < 0 ? .primary : AppTheme.positive)
        }
        .padding()
        .background(.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func metricCard(title: String, value: Int, isMoney: Bool = true) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
                Text(isMoney ? formatMoney(value) : String(value))
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(.primary)
            }
            .frame(width: 140, alignment: .leading)
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
            async let payees = try client().fetchPayees()
            let (accList, catList, payeeList) = try await (accs, cats, payees)
            let since = firstOfThisMonthMinus(days: 31)
            let txs = try await withThrowingTaskGroup(of: [Transaction].self) { group -> [[Transaction]] in
                for acc in accList { group.addTask { try await client().fetchTransactions(accountId: acc.id, since: since) } }
                var results: [[Transaction]] = []
                for try await list in group { results.append(list) }
                return results
            }
            await MainActor.run {
                accounts = accList
                 self.transactions = txs.flatMap { $0 }
                categoriesById = Dictionary(uniqueKeysWithValues: catList.map { ($0.id, $0.name) })
                payeesById = Dictionary(uniqueKeysWithValues: payeeList.map { ($0.id, $0) })
                SharedDataManager.shared.save(spentToday: self.spentToday(), currencyCode: self.appState.currencyCode)
                transactions = txs.flatMap { $0 }
            }
        } catch {
            AppLogger.shared.log(error: error, context: "DashboardView.load")
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func spentToday() -> Int {
        let today = format(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let todays = transactions.filter { $0.date == today && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -todays.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func spentThisMonth() -> Int {
        let (start, end) = monthRange(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func spentLastMonth() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let (start, end) = monthRange(date: lastMonthDate)
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func isTransfer(_ tx: Transaction) -> Bool {
        if tx.transfer_id != nil { return true }
        if let payeeId = tx.payee, let p = payeesById[payeeId], p.transfer_acct != nil { return true }
        return false
    }

    private func recentNonTransferOnBudget() -> [Transaction] {
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        return transactions.filter { onBudgetIds.contains($0.account) && !isTransfer($0) }.sorted { $0.date > $1.date }
    }
    
    private func monthRange(date: Date) -> (String, String) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: date)
        let startDate = cal.date(from: comps) ?? date
        let endDate = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? date
        return (format(date: startDate), format(date: endDate))
    }

    private func firstOfThisMonthMinus(days: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let since = cal.date(byAdding: .day, value: -days, to: start) ?? start
        return format(date: since)
    }

    private func format(date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    private func payeeText(_ tx: Transaction) -> String {
        if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
        if let n = tx.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }

    private func delete(_ tx: Transaction) async {
        guard let txId = tx.id else { return }
        // Optimistically remove from local list
        await MainActor.run {
            transactions.removeAll { $0.id == txId }
        }
        do {
            try await client().deleteTransaction(transactionId: txId)
        } catch {
            AppLogger.shared.log(error: error, context: "DashboardView.delete")
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}