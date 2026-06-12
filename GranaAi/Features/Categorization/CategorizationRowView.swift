import SwiftUI

/// Row da tela de revisão de categorizações.
///
/// Layout alinhado com `TransactionRow.importPreview` (mesma altura, mesmo
/// padding, mesma posição de logo banco/descrição/data/valor). A diferença
/// fica no miolo: aqui as duas chips de categoria são **editáveis** via
/// `Menu`, e a badge de status à direita carrega o % de confiança da IA.
///
/// **`Menu` em vez de `Picker`:** `Picker` materializa todas as opções
/// imediatamente — com 15 categorias × 2 pickers × N rows, são 30N+ `Text`
/// views instanciados na construção da lista. Em listas com 100+ sugestões
/// isso trava o scroll. `Menu` só constrói o conteúdo quando o usuário
/// abre, reduzindo o custo por row em ordem de magnitude.
struct CategorizationRowView: View {
    @Bindable var store: CategorizationStore
    let index: Int

    private var suggestion: CategorizationSuggestion {
        store.suggestions[index]
    }

    var body: some View {
        // **Layout proporcional:** colunas fixas (ícone, valor/data, badge)
        // ocupam seu tamanho natural; descrição, categoria e subcategoria
        // dividem o espaço restante **igualmente** via `maxWidth: .infinity`.
        // SwiftUI não tem equivalente direto ao `Expanded(flex: N)` do Flutter
        // pra ratios assimétricos (2:1:1) sem `Layout` custom — o `minWidth`
        // baseline diferenciado dá prioridade visual à descrição em larguras
        // apertadas, mas em larguras confortáveis as três crescem na mesma
        // proporção.
        HStack(alignment: .center, spacing: 12) {
            if let kind = store.institutionKind(forAccountId: suggestion.transactionAccountId) {
                InstitutionIcon(kind: kind, size: 24)
            }

            Text(suggestion.transactionDescription)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                .help(suggestion.transactionDescription)

            categoryMenu
            subcategoryMenu

            VStack(alignment: .trailing, spacing: 2) {
                Text(suggestion.transactionAmount.formatted(.currency(code: "BRL")))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(amountColor)
                Text(Self.dateFormatter.string(from: suggestion.transactionOccurredAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .trailing)

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

    /// Convenção visual: só receita destaca (verde). Despesa neutra, transfer
    /// cinza. Igual `TransactionRow` — pra listas onde quase tudo é despesa,
    /// pintar tudo de vermelho deixa de informar nada.
    private var amountColor: Color {
        guard let category = store.category(for: suggestion.categoryId) else {
            return .primary
        }
        switch category.kind {
        case .income: return .income
        case .transfer: return .transfer
        case .expense: return .primary
        }
    }

    // MARK: - Menus

    private var categoryMenu: some View {
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
        .frame(minWidth: 130, maxWidth: .infinity)
        .help(rootName)
    }

    private var subcategoryMenu: some View {
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
        .frame(minWidth: 110, maxWidth: .infinity)
        .help(subName ?? "Sem subcategoria")
    }

    private var rootName: String {
        store.category(for: suggestion.categoryId)?.name ?? "Categoria"
    }

    private var subName: String? {
        guard let subId = suggestion.subcategoryId else { return nil }
        return store.category(for: subId)?.name
    }

    /// Mesmo formato dd/MM/yyyy usado pela `TransactionRow` no import — pra
    /// data alinhar visualmente entre as duas telas do wizard.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

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
