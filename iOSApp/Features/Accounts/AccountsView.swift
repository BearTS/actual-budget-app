import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var accounts: [Account] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var balancesById: [String: Int] = [:]

    private var onBudget: [Account] {
        let list = accounts.filter { !$0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var offBudget: [Account] {
        let list = accounts.filter { $0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    GlassCard(cornerRadius: 15) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Total Balance")
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            Text(formattedAmount(totalAll()))
                                .font(AppTheme.Fonts.body.monospacedDigit())
                                .foregroundColor(.primary)
                        }
                    }
                    if !onBudget.isEmpty {
                        accountSection(title: "On-Budget", accounts: onBudget)
                    }
                    if !offBudget.isEmpty {
                        accountSection(title: "Off-Budget", accounts: offBudget)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .task { await softReload() }
        .refreshable { await hardReload() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
            Button("View Logs") {
                AppLogger.shared.log("User tapped View Logs from Accounts error", level: .info, context: "AccountsView")
                errorMessage = nil
                NotificationCenter.default.post(name: NSNotification.Name("OpenLogsView"), object: nil)
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingCreate) {
            CreateAccountSheet { name, offbudget in
                Task { await createAccount(name: name, offbudget: offbudget) }
            }
            .presentationDetents([.height(250)])
        }
    }

    private func accountSection(title: String, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(AppTheme.Fonts.title)
                    .foregroundColor(.primary)
                Spacer()
                Text(formattedAmount(totalFor(accounts: accounts)))
                    .font(AppTheme.Fonts.body.monospacedDigit())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal)

            ForEach(accounts) { account in
                NavigationLink(destination: TransactionsView(account: account)) {
                    GlassCard(cornerRadius: 15) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                    .font(AppTheme.Fonts.headline)
                                    .foregroundColor(.primary)
                                Text(account.closed ? "Closed" : "Active")
                                    .font(AppTheme.Fonts.footnote)
                                    .foregroundStyle(account.closed ? .yellow : .secondary)
                            }
                            Spacer()
                            Text(formattedAmount(balancesById[account.id]))
                                .font(AppTheme.Fonts.body.monospacedDigit())
                                .foregroundColor(.primary)
                        }
                    }
                    .task { await loadBalanceIfNeeded(account) }
                }
                .buttonStyle(.plain)
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

    private func hardReload() async { await load(clearBalances: true) }
    private func softReload() async { await load(clearBalances: false) }

    private func load(clearBalances: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await client().fetchAccounts()
            await MainActor.run {
                self.accounts = list
                if clearBalances { self.balancesById.removeAll() }
            }
            await withTaskGroup(of: Void.self) { group in
                for acc in list {
                    group.addTask { await self.loadBalanceIfNeeded(acc) }
                }
            }
        } catch {
            AppLogger.shared.log(error: error, context: "AccountsView.load")
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func loadBalanceIfNeeded(_ account: Account) async {
        if balancesById[account.id] != nil { return }
        do {
            let bal = try await fetchBalance(accountId: account.id)
            await MainActor.run { balancesById[account.id] = bal }
        } catch {
            // ignore per-row errors
        }
    }

    private func fetchBalance(accountId: String) async throws -> Int {
        if appState.isDemoMode {
            // Compute a fake balance by summing generated demo transactions
            let since = demoSinceDateString(daysBack: 120)
            let txs = DemoDataService.shared.generateTransactions(for: accountId, since: since)
            return txs.compactMap { $0.amount }.reduce(0, +)
        } else {
            let url = APIEndpoints.accountBalance(base: try APIEndpoints.baseURL(from: appState.baseURLString), syncId: appState.syncId, accountId: accountId)
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(appState.apiKey, forHTTPHeaderField: "x-api-key")
            if !appState.budgetEncryptionPassword.isEmpty { req.setValue(appState.budgetEncryptionPassword, forHTTPHeaderField: "budget-encryption-password") }
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                NetworkLogger.logHTTPError(method: "GET", url: url, baseURLString: appState.baseURLString, status: http.statusCode, body: data)
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(APIResponse<Int>.self, from: data)
            return decoded.data
        }
    }

    private func formattedAmount(_ amount: Int?) -> String {
        return CurrencyFormatter.shared.format(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func demoSinceDateString(daysBack: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func totalFor(accounts: [Account]) -> Int {
        accounts.map { balancesById[$0.id] ?? 0 }.reduce(0, +)
    }

    private func totalAll() -> Int {
        totalFor(accounts: self.accounts)
    }

    private func createAccount(name: String, offbudget: Bool) async {
        do {
            _ = try await client().createAccount(name: name, offbudget: offbudget)
            await hardReload()
        } catch { await MainActor.run { errorMessage = error.localizedDescription } }
    }
}

private struct CreateAccountSheet: View {
    var onCreate: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var offbudget: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section(header: Text("Account Details")) {
                        TextField("Name", text: $name)
                        Toggle("Off-budget account", isOn: $offbudget)
                    }
                    .listRowBackground(Color.primary.opacity(0.05))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, offbudget)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .tint(AppTheme.accent)
        }
    }
}

