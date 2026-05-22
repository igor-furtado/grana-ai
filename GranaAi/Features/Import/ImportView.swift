import SwiftUI
import UniformTypeIdentifiers

/// Wizard de importação OFX apresentado como **sheet modal** sobre a tela de
/// Transações (e a partir da tela de Histórico de Importações). Não vive
/// na navegação principal — sempre é triggerado pelo usuário via botão
/// "Importar OFX".
///
/// **Por que `@State` pra `ImportStore`:** store é local à apresentação, não
/// faz sentido subir pra `AppEnvironment`. Quando o modal é fechado, o store
/// some junto — cada nova abertura começa em `.idle`.
struct ImportView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var store: ImportStore?
    @State private var fileImporterShown = false

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    wizard(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { initialize() }
                }
            }
            .navigationTitle("Importar extrato")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 620)
    }

    private func initialize() {
        let s = ImportStore(container: environment.container)
        store = s
        Task { await s.loadInitialData() }
    }

    @ViewBuilder
    private func wizard(store: ImportStore) -> some View {
        switch store.phase {
        case .idle:
            IdleStepView(fileImporterShown: $fileImporterShown, store: store)
        case .loading(let progress):
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(progress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ofxReview:
            OFXReviewStepView(store: store)
        case .categorizing:
            CategorizingStepView(store: store)
        case .reviewingCategorization:
            // Tela de revisão como step do wizard, com botões "Voltar" e
            // "Importar". `onImport` chama `finalizeImport` que commita
            // atomicamente; `onBack` volta pro preview sem mexer no banco.
            CategorizationReviewView(
                store: store.categorization,
                mode: .wizard(
                    onImport: { await store.finalizeImport() },
                    onBack: { store.backToPreviewFromReview() }
                )
            )
        case .confirming:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Importando…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let batchIds, let rowCount):
            DoneStepView(store: store, batchIds: batchIds, rowCount: rowCount, dismiss: dismiss)
        case .failed(let message):
            FailedStepView(store: store, message: message)
        }
    }
}

/// Step intermediário: AI rodando antes do commit. Mostra o status detalhado
/// do `CategorizationStore` (cache hits, chamada à IA, fallback).
private struct CategorizingStepView: View {
    @Bindable var store: ImportStore

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            statusText
            Button("Cancelar") { store.backToPreviewFromReview() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Só renderiza os sub-estados que o usuário consegue ler antes de o
    /// `awaitCategorizationCompletion` trocar a `phase` — `.ready` e `.failed`
    /// transicionam direto pra `.reviewingCategorization`, então nunca aparecem
    /// aqui.
    @ViewBuilder
    private var statusText: some View {
        switch store.categorization.status {
        case .idle:
            Text("Preparando categorização…").foregroundStyle(.secondary)
        case .classifying(_, _, let message):
            Text(message).foregroundStyle(.secondary)
        case .ready, .failed:
            EmptyView()
        }
    }
}

// MARK: - Idle (file picker)

private struct IdleStepView: View {
    @Binding var fileImporterShown: Bool
    let store: ImportStore

    var body: some View {
        ContentUnavailableView {
            Label("Importar extrato", systemImage: AppIcon.importFile.systemImage)
        } description: {
            Text("Selecione um arquivo **OFX**. A conta e o banco são detectados automaticamente; transações duplicadas (mesmo FITID) são marcadas no preview.")
        } actions: {
            Button("Escolher arquivo") { fileImporterShown = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(
            isPresented: $fileImporterShown,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await store.loadFile(url: url) }
                }
            case .failure(let err):
                store.reportFileImportFailure(err)
            }
        }
    }
}

// MARK: - OFX review (multi-account)

private struct OFXReviewStepView: View {
    @Bindable var store: ImportStore

    private var totalSelected: Int {
        store.ofxResolutions.reduce(0) { $0 + $1.rows.filter(\.selected).count }
    }
    private var statementsWithAnySelected: Int {
        store.ofxResolutions.filter { $0.rows.contains(where: \.selected) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Conta de destino: renderizada FORA do List como `Form { Section }`
            // nativo, pra ter o visual exato das telas Nova conta / Nova
            // transação. Pode ser uma ou múltiplas (multi-statement OFX);
            // empilhadas verticalmente. Sem padding horizontal externo — o
            // Form `.grouped` já entrega seu próprio recuo lateral.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.ofxResolutions.indices, id: \.self) { idx in
                    AccountInfoCard(resolution: $store.ofxResolutions[idx])
                }
            }

            TransactionsListCard(
                resolutions: $store.ofxResolutions,
                showsBankInHeader: store.ofxResolutions.count > 1
            )

            BottomActionBar(caption: selectionCaption) {
                Button {
                    Task { await store.confirmOFXImport() }
                } label: {
                    Label(
                        "Avançar com \(totalSelected) \(totalSelected == 1 ? "transação" : "transações")",
                        systemImage: "chevron.right.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(totalSelected == 0)
            }
        }
        .navigationSubtitle(store.sourceURL?.lastPathComponent ?? "")
    }

    private var selectionCaption: String {
        "\(totalSelected) \(totalSelected == 1 ? "transação selecionada" : "transações selecionadas") em \(statementsWithAnySelected) \(statementsWithAnySelected == 1 ? "conta" : "contas")"
    }
}

/// Card de "Conta de destino" renderizado FORA do `List` — usa `Form { Section }`
/// nativo do macOS pra ter o visual grouped exato das telas Nova conta / Nova
/// transação. Conteúdo estático com poucas rows, então a falta de virtualização
/// do Form não é problema aqui (diferente do `TransactionsSection`, que precisa
/// do `List` virtualizado pela quantidade de transações).
///
/// Quando a conta vai ser criada (`isAccountNew`), o badge "Nova conta" aparece
/// no header da Section e os campos Nome/Tipo viram editáveis.
private struct AccountInfoCard: View {
    @Binding var resolution: OFXStatementResolution

    var body: some View {
        Form {
            Section {
                LabeledContent("Banco") {
                    Text(institutionDisplayName)
                }
                LabeledContent("Conta") {
                    Text(accountSummary)
                }
                if resolution.isAccountNew {
                    TextField("Nome", text: $resolution.account.name)
                    Picker("Tipo", selection: $resolution.account.type) {
                        ForEach(AccountType.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                } else {
                    LabeledContent("Tipo") {
                        Text(resolution.account.type.displayName)
                    }
                }
            } header: {
                HStack {
                    Text("Conta de destino")
                    Spacer()
                    if resolution.isAccountNew {
                        Text("Nova conta")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.success.opacity(0.15))
                            .foregroundStyle(.success)
                            .clipShape(Capsule())
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Form grouped scrolla por dentro; aqui o conteúdo é fixo, então
        // desabilita o scroll pra integrar com o `ScrollView`/layout pai.
        .scrollDisabled(true)
        // Altura do card é ditada pelo conteúdo (4–5 rows). `fixedSize` no
        // eixo vertical evita o Form esticar pra preencher espaço sobrando.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var institutionDisplayName: String {
        resolution.statement.institutionHeader.organization
            ?? resolution.institution.name
    }

    private var accountSummary: String {
        var parts: [String] = [resolution.account.accountNumber]
        if let branch = resolution.account.branchId, !branch.isEmpty {
            parts.append("Ag \(branch)")
        }
        parts.append("cód. \(resolution.institution.code)")
        return parts.joined(separator: " · ")
    }
}

/// Section de transações dentro do `List` (virtualizado). Sem pickers de
/// categoria — Fase 4 moveu categorização pro step seguinte.
///
/// `showsBankInHeader` adiciona o nome do banco no título quando há múltiplos
/// statements no mesmo arquivo, pra usuário saber a qual conta o bloco pertence.
/// Card de transações que usa `Form { Section }` com **uma única row**
/// contendo um `ScrollView { LazyVStack }`. O Form entrega o visual nativo de
/// card grouped (igual à `AccountInfoCard`); a LazyVStack interna mantém a
/// virtualização real das transações (só renderiza o viewport).
///
/// Sutileza: Form normalmente não virtualiza rows de uma Section, mas como
/// **temos uma única row** (o ScrollView), Form materializa só ela e a
/// laziness fica por conta da LazyVStack dentro do ScrollView.
private struct TransactionsListCard: View {
    @Binding var resolutions: [OFXStatementResolution]
    let showsBankInHeader: Bool

    private var totalRows: Int {
        resolutions.reduce(0) { $0 + $1.rows.count }
    }

    private var allSelected: Bool {
        let rows = resolutions.flatMap(\.rows)
        return !rows.isEmpty && rows.allSatisfy(\.selected)
    }

    var body: some View {
        Form {
            Section {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($resolutions) { $resolution in
                            if showsBankInHeader {
                                bankSubheader(for: resolution)
                            }
                            ForEach($resolution.rows) { $row in
                                OFXRowView(row: $row)
                                    .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                }
                // Remove o padding default que o Form coloca em torno da row
                // — assim a LazyVStack encosta nas bordas do card.
                .listRowInsets(EdgeInsets())
            } header: {
                HStack(spacing: 8) {
                    Text("Transações")
                    Spacer()
                    Text("\(totalRows)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    Toggle("", isOn: Binding(
                        get: { allSelected },
                        set: { toggleAll(to: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(allSelected ? "Desmarcar todas" : "Marcar todas")
                }
            }
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func bankSubheader(for resolution: OFXStatementResolution) -> some View {
        HStack {
            Text(bankName(for: resolution))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func bankName(for resolution: OFXStatementResolution) -> String {
        resolution.statement.institutionHeader.organization
            ?? resolution.institution.name
    }

    private func toggleAll(to value: Bool) {
        for resIdx in resolutions.indices {
            for rowIdx in resolutions[resIdx].rows.indices {
                resolutions[resIdx].rows[rowIdx].selected = value
            }
        }
    }
}

/// Row enxuta de transação no preview OFX.
///
/// Layout: `descrição (primary) + data·valor (caption) | badge duplicada | checkbox`.
/// Sem pickers de categoria (Fase 4 movido pro step `reviewingCategorization`).
/// Sem memo (ruído — quem quiser detalhe abre a transação depois de importar).
private struct OFXRowView: View {
    @Binding var row: OFXPreviewRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryDescription)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: row.derived.occurredAt))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(Self.currencyFormatter.string(from: row.derived.amount as NSDecimalNumber) ?? "")
                        .monospacedDigit()
                        .foregroundStyle(amountColor)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.isDuplicate {
                Text("Já importada")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.warning.opacity(0.18))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            Toggle("", isOn: $row.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
        .opacity(row.isDuplicate && !row.selected ? 0.55 : 1.0)
    }

    private var amountColor: Color {
        row.derived.amount < 0 ? .expense : .income
    }

    private var primaryDescription: String {
        // NAME geralmente é a contraparte ("Igor Talisson..."); MEMO traz
        // detalhe técnico ("Pix recebido: Cp :..."). Mostrar NAME — MEMO
        // some pra minimizar ruído visual.
        if let name = row.raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return row.derived.description
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()
}

// MARK: - Done / Failed

private struct DoneStepView: View {
    let store: ImportStore
    let batchIds: [UUID]
    let rowCount: Int
    let dismiss: DismissAction

    var body: some View {
        ContentUnavailableView {
            Label("Importação concluída", systemImage: AppIcon.completedSeal.systemImage)
        } description: {
            Text("\(rowCount) \(rowCount == 1 ? "transação importada" : "transações importadas") em \(batchIds.count) \(batchIds.count == 1 ? "lote" : "lotes"). Categorias já aplicadas conforme sua revisão.")
        } actions: {
            Button("Desfazer \(batchIds.count == 1 ? "este lote" : "todos os lotes")", role: .destructive) {
                Task {
                    for id in batchIds { await store.undo(batchId: id) }
                    dismiss()
                }
            }
            Button("Concluir") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct FailedStepView: View {
    let store: ImportStore
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Algo deu errado", systemImage: AppIcon.warning.systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Recomeçar") { store.cancel() }
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Importar") {
    ImportView()
        .environment(AppEnvironment())
}
