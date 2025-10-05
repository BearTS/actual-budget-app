import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    let accounts: [Account]
    let payeesById: [String: Payee]
    let categoriesById: [String: String]
    let currencyCode: String
    var onEdit: ((Transaction) -> Void)?
    var onDelete: ((Transaction) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: (transaction.amount ?? 0) < 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.title2)
                .foregroundColor((transaction.amount ?? 0) < 0 ? .secondary : AppTheme.positive)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText())
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                Text(secondaryText())
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.shared.formatSigned(transaction.amount ?? 0, currencyCode: currencyCode))
                    .font(AppTheme.Fonts.body.monospacedDigit())
                    .foregroundStyle((transaction.amount ?? 0) < 0 ? .primary : AppTheme.positive)
                Text(transaction.date)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onEdit?(transaction) }
        .contextMenu {
            if let onEdit { Button { onEdit(transaction) } label: { Label("Edit", systemImage: "pencil") } }
            if let onDelete { Button(role: .destructive) { onDelete(transaction) } label: { Label("Delete", systemImage: "trash") } }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete { Button(role: .destructive) { onDelete(transaction) } label: { Label("Delete", systemImage: "trash") } }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onEdit { Button { onEdit(transaction) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue) }
        }
    }

    private func primaryText() -> String {
        if let account = transferDestinationAccount(transaction) {
            return "Transfer to: \(account.name)"
        }
        if let payeeId = transaction.payee, let p = payeesById[payeeId] { return p.name }
        if let n = transaction.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }

    private func secondaryText() -> String {
        if let name = categoriesById[transaction.category ?? ""], !name.isEmpty {
            return name
        }
        if let accountName = accounts.first(where: { $0.id == transaction.account })?.name {
            return accountName
        }
        return ""
    }

    private func transferDestinationAccount(_ tx: Transaction) -> Account? {
        if let payeeId = tx.payee,
           let p = payeesById[payeeId],
           let destAcctId = p.transfer_acct {
            return accounts.first { $0.id == destAcctId }
        }
        return nil
    }
}


