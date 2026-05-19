import SwiftUI

/// Row da tela de revisão. Layout enxuto, alinhado ao padrão Form:
///
/// - Descrição em corpo regular + meta (valor + data) em caption secundária,
///   uma linha só de hierarquia abaixo da descrição
/// - Direita: dois menus (raiz + sub) + badge de confiança
///
/// **`Menu` em vez de `Picker`:** `Picker` materializa todas as opções
/// imediatamente — com 15 categorias × 2 pickers × N rows, são 30N+ `Text`
/// views instanciados na construção da lista. Em listas com 100+ sugestões
/// isso trava o scroll. `Menu` só constrói o conteúdo quando o usuário
/// abre, reduzindo o custo por row em ordem de magnitude.
///
/// Sem botão de "confirmar" por row — confirmar é ação global no bottom bar
/// do wizard ("Importar") ou na toolbar do sheet ("Confirmar tudo").
struct CategorizationRowView: View {
    @Bindable var store: CategorizationStore
    let index: Int

    private var suggestion: CategorizationSuggestion {
        store.suggestions[index]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            descriptionColumn
            Spacer(minLength: 12)
            pickersColumn
            CategorizationConfidenceBadge(
                confidence: suggestion.confidence,
                bucket: suggestion.bucket(
                    autoApproved: store.thresholds.autoApproved,
                    reviewRequired: store.thresholds.reviewRequired
                )
            )
        }
        .opacity(suggestion.isReviewed ? 0.6 : 1.0)
    }

    // MARK: - Coluna esquerda

    @ViewBuilder
    private var descriptionColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(suggestion.transactionDescription)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(suggestion.transactionAmount.formatted(.currency(code: "BRL")))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                Text("·").foregroundStyle(.tertiary)
                Text(suggestion.transactionOccurredAt, format: .dateTime.day().month().year())
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountColor: Color {
        guard let category = store.category(for: suggestion.categoryId) else {
            return .secondary
        }
        switch category.kind {
        case .expense:  return .expense
        case .income:   return .income
        case .transfer: return .transfer
        }
    }

    // MARK: - Coluna direita (menus)

    @ViewBuilder
    private var pickersColumn: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.rootCategories) { category in
                    Button(category.name) {
                        Task {
                            await store.applyCorrection(
                                at: index,
                                correctedCategoryId: category.id,
                                correctedSubcategoryId: nil
                            )
                        }
                    }
                }
            } label: {
                menuLabel(text: rootName)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 190)

            Menu {
                Button("Nenhuma") {
                    Task {
                        await store.applyCorrection(
                            at: index,
                            correctedCategoryId: suggestion.categoryId,
                            correctedSubcategoryId: nil
                        )
                    }
                }
                ForEach(store.subcategories(of: suggestion.categoryId)) { sub in
                    Button(sub.name) {
                        Task {
                            await store.applyCorrection(
                                at: index,
                                correctedCategoryId: suggestion.categoryId,
                                correctedSubcategoryId: sub.id
                            )
                        }
                    }
                }
            } label: {
                menuLabel(text: subName ?? "—")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)
        }
    }

    private var rootName: String {
        store.category(for: suggestion.categoryId)?.name ?? "Categoria"
    }

    private var subName: String? {
        guard let subId = suggestion.subcategoryId else { return nil }
        return store.category(for: subId)?.name
    }

    /// Label estilizado igual ao `Picker .menu` mas leve — o conteúdo
    /// (lista de opções) só é construído quando o menu abre.
    private func menuLabel(text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: AppIcon.sort.systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
