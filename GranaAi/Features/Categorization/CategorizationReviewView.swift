import SwiftUI

/// Tela de revisão das sugestões da IA.
///
/// Visual segue o mesmo padrão do `OFXReviewStepView`: `Form { Section }`
/// nativo com **uma única row** contendo `ScrollView { LazyVStack { ... } }`.
/// Assim ganhamos:
/// - Visual de card grouped idêntico à `AccountInfoCard` (Form `.grouped`).
/// - Virtualização real das sugestões via `LazyVStack` (mesmo com 500+ rows).
///
/// Dois modos:
/// - `.modal`: NavigationStack próprio + toolbar com Fechar/Confirmar tudo.
/// - `.wizard(onImport:onBack:)`: bottom bar com Voltar/Importar.
struct CategorizationReviewView: View {
    enum Mode {
        case modal
        case wizard(
            onImport: @MainActor () async -> Void,
            onBack: @MainActor () -> Void,
            onClose: @MainActor () -> Void
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CategorizationStore
    var mode: Mode = .modal

    var body: some View {
        switch mode {
        case .modal:
            NavigationStack {
                content
                    .navigationTitle("Revisar categorizações")
                    .navigationSubtitle(statusSubtitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fechar") { dismiss() }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task {
                                    await store.confirmAll()
                                    dismiss()
                                }
                            } label: {
                                Text("Confirmar tudo")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.suggestions.allSatisfy { $0.isReviewed })
                        }
                    }
            }
            .frame(minWidth: 700, minHeight: 600)
        case let .wizard(onImport, onBack, onClose):
            VStack(spacing: 0) {
                content
                    .navigationSubtitle(statusSubtitle)
                wizardBottomBar(onImport: onImport, onBack: onBack, onClose: onClose)
            }
        }
    }

    // MARK: - Form (núcleo)

    @ViewBuilder
    private var content: some View {
        if store.suggestions.isEmpty {
            emptyState
        } else {
            // Mesma estrutura do `TransactionsListCard` em ImportView:
            // Form { Section { ScrollView { LazyVStack { ... } } } }.
            // Form materializa só UMA row (o ScrollView); a LazyVStack
            // virtualiza as sugestões — handle de 500+ sem travar.
            Form {
                Section {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            summaryRow
                            Divider()
                            ForEach(groupedSections, id: \.bucket) { section in
                                if showsBucketSubheaders {
                                    bucketSubheader(section.bucket, count: section.indices.count)
                                }
                                ForEach(section.indices, id: \.self) { idx in
                                    CategorizationRowView(store: store, index: idx)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                    Divider()
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text(headerTitle)
                }
            }
            .formStyle(.grouped)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .frame(maxHeight: .infinity)
        }
    }

    /// Linha de resumo logo abaixo do header — mesmo tratamento visual da
    /// `TransactionsSelectionRow` do import. Aqui não há checkbox (revisão
    /// é caso a caso, não em lote) — só o texto de progresso.
    private var summaryRow: some View {
        HStack(spacing: 12) {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private var summaryText: String {
        let total = store.suggestions.count
        let reviewed = store.suggestions.filter(\.isReviewed).count
        return "\(reviewed) de \(total) revisadas"
    }

    /// Quando há mais de um bucket presente, exibimos sub-header dentro do
    /// scroll por bucket. Single bucket: header da Section já carrega o nome
    /// (ex: "Confiança baixa") e sub-header vira redundante.
    private var showsBucketSubheaders: Bool {
        groupedSections.count > 1
    }

    /// Título do Form Section. Quando há um único bucket, vira o nome dele
    /// ("Confiança baixa"); senão fica genérico ("Sugestões").
    private var headerTitle: String {
        if !showsBucketSubheaders, let only = groupedSections.first {
            return sectionTitle(only.bucket)
        }
        return "Sugestões"
    }

    private func bucketSubheader(
        _ bucket: CategorizationSuggestion.ConfidenceBucket,
        count: Int
    ) -> some View {
        HStack {
            Text(sectionTitle(bucket))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    /// Status detalhado da categorização vira o `navigationSubtitle` do sheet
    /// (mesmo lugar que o filename ocupa em `OFXReviewStepView`). Liberta o
    /// espaço dentro do card pro conteúdo principal.
    private var statusSubtitle: String {
        switch store.status {
        case .idle:
            return ""
        case let .classifying(_, _, message):
            return message
        case let .ready(total, fromCache, fromAI, fallback):
            return "\(total) transações · \(fromCache) via cache · \(fromAI) via IA · \(fallback) não classificadas"
        case let .failed(message):
            return message
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .classifying = store.status {
            VStack(spacing: 12) {
                ProgressView()
                Text("Categorizando…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Nada para revisar",
                systemImage: AppIcon.success.systemImage,
                description: Text("Não há sugestões pendentes.")
            )
        }
    }

    // MARK: - Bottom bar (wizard)

    private func wizardBottomBar(
        onImport: @escaping @MainActor () async -> Void,
        onBack: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> some View {
        // Caption omitida — stats de revisão vivem no `summaryRow` da lista.
        BottomActionBar {
            Button("Fechar") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Voltar") { onBack() }
            Button {
                Task { await onImport() }
            } label: {
                Text("Importar \(store.suggestions.count) \(store.suggestions.count == 1 ? "transação" : "transações")")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.suggestions.isEmpty || isClassifying)
        }
    }

    private var isClassifying: Bool {
        if case .classifying = store.status { return true }
        return false
    }

    // MARK: - Agrupamento

    private struct BucketSection {
        let bucket: CategorizationSuggestion.ConfidenceBucket
        let indices: [Int]
    }

    private var groupedSections: [BucketSection] {
        let thresholds = store.thresholds
        var low: [Int] = []
        var medium: [Int] = []
        var high: [Int] = []
        for (idx, suggestion) in store.suggestions.enumerated() {
            switch suggestion.bucket(
                autoApproved: thresholds.autoApproved,
                reviewRequired: thresholds.reviewRequired
            ) {
            case .low: low.append(idx)
            case .medium: medium.append(idx)
            case .high: high.append(idx)
            }
        }
        var sections: [BucketSection] = []
        if !low.isEmpty { sections.append(BucketSection(bucket: .low, indices: low)) }
        if !medium.isEmpty { sections.append(BucketSection(bucket: .medium, indices: medium)) }
        if !high.isEmpty { sections.append(BucketSection(bucket: .high, indices: high)) }
        return sections
    }

    private func sectionTitle(_ bucket: CategorizationSuggestion.ConfidenceBucket) -> String {
        switch bucket {
        case .high: "Confiança alta"
        case .medium: "Confiança média"
        case .low: "Confiança baixa"
        }
    }
}

#Preview {
    CategorizationReviewView(store: CategorizationStore(container: AppContainer.placeholder()))
}
