import SwiftUI

/// Pill com ícone + nome da categoria. Usado tanto na linha da lista de
/// transações quanto na coluna "Categoria" da `Table` do macOS.
struct CategoryBadge: View {
    let category: Category?
    let icon: CategoryIcon?
    /// Quando `true`, esconde o nome e renderiza só o ícone dentro do pill.
    /// Caller costuma adicionar `.help(category.name)` por fora pra tooltip.
    var iconOnly: Bool = false

    var body: some View {
        if let category {
            if iconOnly {
                iconOnlyBody(for: category)
            } else {
                pillBody(for: category)
            }
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Quadrado 24pt com cantos arredondados — mesma silhueta do
    /// `InstitutionIcon` pra alinhar verticalmente em tabelas que misturam os
    /// dois (ex: lista de Transações), mas com peso visual reduzido: fundo
    /// na cor da categoria com opacidade baixa e ícone na cor sólida.
    /// Logo de banco é identidade de marca (deve dominar); categoria é dado
    /// auxiliar, não pode competir.
    private func iconOnlyBody(for category: Category) -> some View {
        let size: CGFloat = 24
        let color = tint(for: category.kind)
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                if let icon {
                    Image(systemName: icon.systemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(color)
                        .padding(size * 0.25)
                }
            }
    }

    private func pillBody(for category: Category) -> some View {
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
    }

    private func tint(for kind: CategoryKind) -> Color {
        switch kind {
        case .expense: return .expense
        case .income: return .income
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
