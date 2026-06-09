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
    /// dois (ex: lista de Transações), mas com peso visual reduzido. Cor vem
    /// do **ícone** (semântica do glyph, ex: heart=vermelho), não do `kind` —
    /// dá identidade própria pra cada categoria no donut/lista.
    private func iconOnlyBody(for category: Category) -> some View {
        let size: CGFloat = 24
        let color = tint(for: category, icon: icon)
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                if let icon {
                    Image(systemName: icon.systemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color.gradient)
                        .padding(size * 0.25)
                }
            }
    }

    private func pillBody(for category: Category) -> some View {
        let color = tint(for: category, icon: icon)
        return HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon.systemImage)
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color.gradient)
            }
            Text(category.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    /// Cor do badge: preferir `icon.color` (semântica do glyph) e cair pra
    /// cor do `kind` se a categoria não tem ícone (subcategoria órfã, dado
    /// corrompido). Mantém o badge sempre tingido com algo.
    private func tint(for category: Category, icon: CategoryIcon?) -> Color {
        if let icon { return icon.color }
        switch category.kind {
        case .expense: return .expense
        case .income: return .income
        case .transfer: return .transfer
        }
    }
}
