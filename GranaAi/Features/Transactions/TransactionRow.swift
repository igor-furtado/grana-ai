import SwiftUI

/// Uma linha da lista de transações.
struct TransactionRow: View {
    let transaction: Transaction
    let category: Category?
    let account: Account?
    /// Ícone resolvido — subcategoria recebe o ícone do pai aqui
    /// (a `TransactionsView` busca via `TransactionStore.icon(for:)`).
    let icon: CategoryIcon?

    var body: some View {
        HStack(spacing: 12) {
            if let icon, let category {
                Image(systemName: icon.systemImage)
                    .font(.title3)
                    .foregroundStyle(categoryColor(for: category.kind))
                    .frame(width: 32, height: 32)
                    .background(categoryColor(for: category.kind).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let category {
                        Text(category.name)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor(for: category.kind).opacity(0.2))
                            .foregroundStyle(categoryColor(for: category.kind))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if let account {
                        Text(account.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // `.formatted(.currency(code: "BRL"))` é a forma idiomática:
                // formata respeitando o locale do usuário (separadores, etc.)
                // mas com o símbolo de moeda fixado em BRL.
                Text(transaction.amount.formatted(.currency(code: "BRL")))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(amountColor)

                Text(transaction.occurredAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var amountColor: Color {
        switch category?.kind {
        case .income:   .income
        case .transfer: .transfer
        default:        .primary
        }
    }

    private func categoryColor(for kind: CategoryKind) -> Color {
        switch kind {
        case .expense:  .expense
        case .income:   .income
        case .transfer: .transfer
        }
    }
}

#Preview {
    let now = Date()
    let category = Category(
        id: UUID(),
        parentId: nil,
        name: "Alimentação e Supermercado",
        kind: .expense,
        icon: .utensils,
        createdAt: now
    )
    let account = Account(
        id: UUID(),
        name: "Carteira",
        type: .wallet,
        initialBalance: 0,
        archived: false,
        createdAt: now,
        updatedAt: now
    )
    let transaction = Transaction(
        id: UUID(),
        accountId: account.id,
        categoryId: category.id,
        subcategoryId: nil,
        amount: 87.50,
        occurredAt: now,
        description: "Supermercado da esquina",
        notes: nil,
        createdAt: now,
        updatedAt: now
    )

    return List {
        TransactionRow(
            transaction: transaction,
            category: category,
            account: account,
            icon: .utensils
        )
    }
}
