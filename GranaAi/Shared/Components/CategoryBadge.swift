import SwiftUI

/// Pill com ícone + nome da categoria. Usado tanto na linha da lista de
/// transações quanto na coluna "Categoria" da `Table` do macOS.
struct CategoryBadge: View {
    let category: Category?
    let icon: CategoryIcon?

    var body: some View {
        if let category {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon.systemImage)
                        .font(.caption)
                        .foregroundStyle(tint(for: category.kind))
                }
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(tint(for: category.kind))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint(for: category.kind).opacity(0.15))
            .clipShape(Capsule())
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tint(for kind: CategoryKind) -> Color {
        switch kind {
        case .expense:  return .expense
        case .income:   return .income
        case .transfer: return .transfer
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        CategoryBadge(
            category: Category(
                id: UUID(), parentId: nil,
                name: "Alimentação e Supermercado",
                kind: .expense, slug: "alimentacao-e-supermercado", createdAt: Date()
            ),
            icon: .utensils
        )
        CategoryBadge(
            category: Category(
                id: UUID(), parentId: nil,
                name: "Renda e Pagamentos",
                kind: .income, slug: "renda-e-pagamentos", createdAt: Date()
            ),
            icon: .dollarSign
        )
        CategoryBadge(category: nil, icon: nil)
    }
    .padding()
}
