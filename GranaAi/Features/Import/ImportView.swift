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
    /// Escopo: ciclo de vida desta instância da sheet. Garante que o file
    /// picker abre automaticamente só uma vez por abertura da modal — se o
    /// usuário cancelar o picker, o idle state fica disponível pra reabrir
    /// manualmente. Ao fechar e reabrir a modal, o `ImportView` é remontado e
    /// o flag reseta naturalmente, fazendo o picker abrir de novo na próxima
    /// sessão (comportamento desejado).
    @State private var pickerAutoTriggeredThisSession = false

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
        }
        // Sheet sem cap de altura crescia além da janela em telas pequenas.
        // Limita o tamanho mantendo um ideal confortável.
        .frame(
            minWidth: 700, idealWidth: 760, maxWidth: 900,
            minHeight: 540, idealHeight: 660, maxHeight: 760
        )
    }

    private func initialize() {
        let s = ImportStore(container: environment.container)
        store = s
        Task { await s.loadInitialData() }
    }

    private func wizard(store: ImportStore) -> some View {
        VStack(spacing: 0) {
            if let stepperIndex = Self.stepperIndex(for: store.phase) {
                WizardStepper(
                    steps: ["Revisar", "Categorizar", "Concluir"],
                    currentIndex: stepperIndex
                )
            }
            phaseContent(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Mapeia a `Phase` do wizard pro índice atual do stepper.
    /// `nil` = stepper escondido (idle, loading, failed).
    /// `steps.count` (3) = todos os steps marcados como concluídos.
    private static func stepperIndex(for phase: ImportStore.Phase) -> Int? {
        switch phase {
        case .idle, .loading, .failed:
            return nil
        case .ofxReview, .csvReview:
            return 0
        case .categorizing, .reviewingCategorization:
            return 1
        case .confirming:
            return 2
        case .done:
            return 3
        }
    }

    @ViewBuilder
    private func phaseContent(store: ImportStore) -> some View {
        switch store.phase {
        case .idle:
            IdleStepView(fileImporterShown: $fileImporterShown, store: store)
                .task {
                    guard !pickerAutoTriggeredThisSession else { return }
                    pickerAutoTriggeredThisSession = true
                    fileImporterShown = true
                }
        case let .loading(progress):
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(progress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ofxReview:
            OFXReviewStepView(store: store, dismiss: dismiss)
        case .csvReview:
            CSVReviewStepView(store: store, dismiss: dismiss)
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
                    onBack: { store.backToPreviewFromReview() },
                    onClose: { dismiss() }
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
        case let .done(batchIds, rowCount):
            DoneStepView(store: store, batchIds: batchIds, rowCount: rowCount, dismiss: dismiss)
        case let .failed(message):
            FailedStepView(store: store, message: message)
        }
    }
}

/// Step intermediário: AI rodando antes do commit.
///
/// **Barra determinada quando `total > 0`** (caso comum: já passou pela
/// checagem de cache e sabemos quantos itens vão ser classificados).
/// Fallback pra spinner indeterminado nos primeiros frames antes do
/// `.started` chegar do service.
private struct CategorizingStepView: View {
    @Bindable var store: ImportStore

    var body: some View {
        VStack(spacing: 16) {
            progressIndicator
                .frame(maxWidth: 320)
            statusText
            Button("Cancelar") { store.backToPreviewFromReview() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        switch store.categorization.status {
        case let .classifying(processed, total, _) where total > 0:
            ProgressView(value: Double(processed), total: Double(total))
                .progressViewStyle(.linear)
                .animation(.easeOut(duration: 0.25), value: processed)
        default:
            ProgressView()
                .progressViewStyle(.linear)
        }
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
        case let .classifying(_, _, message):
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
            Text(
                "Selecione um arquivo **OFX** (extrato bancário) ou **CSV** (fatura de cartão Inter). Você precisa ter a conta de destino cadastrada antes — em OFX o app tenta pré-selecionar a conta certa pela identidade bancária, mas você sempre pode trocar no preview."
            )
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
            case let .success(urls):
                if let url = urls.first {
                    Task { await store.loadFile(url: url) }
                }
            case let .failure(err):
                store.reportFileImportFailure(err)
            }
        }
    }
}

// MARK: - OFX review (multi-account)

private struct OFXReviewStepView: View {
    @Bindable var store: ImportStore
    let dismiss: DismissAction

    private var totalSelected: Int {
        store.ofxResolutions.reduce(0) { $0 + $1.rows.filter(\.selected).count }
    }

    private var allAccountsSelected: Bool {
        store.ofxResolutions.allSatisfy { $0.accountId != nil }
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
                    AccountInfoCard(store: store, statementIndex: idx)
                }
            }

            TransactionsListCard(
                resolutions: $store.ofxResolutions,
                showsBankInHeader: store.ofxResolutions.count > 1,
                bankKind: { accountId in bankKind(for: accountId) }
            )

            BottomActionBar(caption: selectionCaption) {
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avançar com \(totalSelected) \(totalSelected == 1 ? "transação" : "transações")") {
                    Task { await store.confirmOFXImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(totalSelected == 0 || !allAccountsSelected)
            }
        }
        .navigationSubtitle(store.sourceURL?.lastPathComponent ?? "")
    }

    /// Caption só pra bloqueios. Stats de seleção viraram redundância com o
    /// header da lista + o label do botão primário ("Avançar com N").
    private var selectionCaption: String? {
        allAccountsSelected ? nil : "Escolha a conta de destino de cada extrato"
    }

    /// Resolve o `InstitutionKind` da conta selecionada pra exibir o logo na
    /// row. Devolve `nil` se a conta ainda não foi escolhida ou a instituição
    /// não tem `kind` mapeado.
    private func bankKind(for accountId: UUID?) -> InstitutionKind? {
        guard let accountId,
              let account = store.accounts.first(where: { $0.id == accountId }),
              let institutionId = account.institutionId,
              let institution = store.institutions.first(where: { $0.id == institutionId })
        else { return nil }
        return institution.kind
    }
}

/// Card de "Conta de destino" renderizado FORA do `List` — usa `Form { Section }`
/// nativo do macOS pra ter o visual grouped exato das telas Nova conta / Nova
/// transação.
///
/// A partir da Fase 4.5 o import **não cria contas** — só seleciona uma
/// existente. Banco/Conta exibidos no card vêm do OFX (apenas leitura, ajudam
/// o usuário a identificar qual das contas cadastradas é). O picker é
/// obrigatório quando o auto-detect não acha; quando acha, vem pré-preenchido
/// com badge "Detectada".
private struct AccountInfoCard: View {
    @Bindable var store: ImportStore
    let statementIndex: Int

    private var resolution: OFXStatementResolution? {
        store.ofxResolutions.indices.contains(statementIndex)
            ? store.ofxResolutions[statementIndex]
            : nil
    }

    var body: some View {
        Form {
            Section {
                if let resolution {
                    LabeledContent("Banco (do extrato)") {
                        Text(resolution.ofxBankLabel)
                    }
                    LabeledContent("Conta (do extrato)") {
                        Text(resolution.ofxAccountLabel)
                    }
                    Picker(
                        "Conta de destino",
                        selection: Binding(
                            get: { resolution.accountId },
                            set: { newValue in
                                Task { await store.setOFXAccount(statementIndex: statementIndex, to: newValue) }
                            }
                        )
                    ) {
                        Text("Selecione…").tag(UUID?.none)
                        ForEach(availableAccounts) { account in
                            Text(label(for: account)).tag(UUID?.some(account.id))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Conta de destino")
                    Spacer()
                    if let resolution {
                        statusBadge(for: resolution)
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

    /// Contas elegíveis como destino do import. Arquivadas ficam fora de
    /// propósito — o usuário tirou do dia-a-dia e importar pra elas seria
    /// inesperado. Quem precisa importar tem que desarquivar primeiro.
    private var availableAccounts: [Account] {
        store.accounts
            .filter { !$0.archived }
            .sorted { label(for: $0).localizedCaseInsensitiveCompare(label(for: $1)) == .orderedAscending }
    }

    private func label(for account: Account) -> String {
        Account.displayName(for: account, institutions: store.institutions)
    }

    @ViewBuilder
    private func statusBadge(for resolution: OFXStatementResolution) -> some View {
        if resolution.accountId == nil {
            Text("Escolha")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.warning.opacity(0.18))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .textCase(nil)
        } else if resolution.wasAutoDetected {
            Text("Detectada")
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
    let bankKind: (UUID?) -> InstitutionKind?

    private var totalRows: Int {
        resolutions.reduce(0) { $0 + $1.rows.count }
    }

    private var selectedCount: Int {
        resolutions.reduce(0) { $0 + $1.rows.filter(\.selected).count }
    }

    private var duplicateCount: Int {
        resolutions.reduce(0) { $0 + $1.rows.filter(\.isDuplicate).count }
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
                        TransactionsSelectionRow(
                            summary: selectionSummary,
                            allSelected: allSelected,
                            onToggleAll: toggleAll(to:)
                        )
                        Divider()
                        ForEach($resolutions) { $resolution in
                            if showsBankInHeader {
                                bankSubheader(for: resolution)
                            }
                            let kind = bankKind(resolution.accountId)
                            ForEach($resolution.rows) { $row in
                                OFXRowView(row: $row, institutionKind: kind)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
                // Remove o padding default que o Form coloca em torno da row
                // — assim a LazyVStack encosta nas bordas do card.
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Transações")
            }
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

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
        resolution.ofxBankLabel
    }

    private func toggleAll(to value: Bool) {
        for resIdx in resolutions.indices {
            for rowIdx in resolutions[resIdx].rows.indices {
                resolutions[resIdx].rows[rowIdx].selected = value
            }
        }
    }

    private var selectionSummary: String {
        var parts = ["\(selectedCount) de \(totalRows) selecionadas"]
        if duplicateCount > 0 {
            parts.append("\(duplicateCount) \(duplicateCount == 1 ? "duplicada" : "duplicadas")")
        }
        return parts.joined(separator: " · ")
    }
}

/// Linha de controle de seleção que vai **dentro do scroll**, logo antes das
/// rows de transação. Fica abaixo do header `Section` (que tem só o título
/// "Transações") pra o checkbox master alinhar verticalmente com a coluna
/// de checkboxes das rows.
private struct TransactionsSelectionRow: View {
    let summary: String
    let allSelected: Bool
    let onToggleAll: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { allSelected },
                set: { onToggleAll($0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(allSelected ? "Desmarcar todas" : "Marcar todas")
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
}

/// Wrapper fino que mapeia `OFXPreviewRow` → `TransactionRow.importPreview`.
private struct OFXRowView: View {
    @Binding var row: OFXPreviewRow
    let institutionKind: InstitutionKind?

    var body: some View {
        // OFX mistura entradas e saídas no mesmo statement (PIX recebido +
        // débito da fatura, p.ex.); colorir por direção ajuda a ler. Sinal
        // do `derived.amount` vem direto do TRNTYPE do OFX.
        TransactionRow(
            selection: $row.selected,
            institutionKind: institutionKind,
            description: primaryDescription,
            memo: nil,
            date: row.derived.occurredAt,
            amount: row.derived.amount,
            amountKind: row.derived.amount < 0 ? .outgoing : .incoming,
            status: row.isDuplicate ? .duplicate : nil
        )
    }

    private var primaryDescription: String {
        // NAME geralmente é a contraparte ("Igor Talisson..."); MEMO traz
        // detalhe técnico ("Pix recebido: Cp :..."). Mostrar NAME — MEMO
        // some pra minimizar ruído visual.
        if let name = row.raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        return row.derived.description
    }
}

// MARK: - CSV review (fatura de cartão — Fase 4.5)

/// Tela de preview da fatura CSV importada. Diferença principal pro OFX:
/// uma única conta, picker manual (só contas-cartão), e info de quantas
/// linhas com valor negativo foram puladas (pagamentos + estornos).
private struct CSVReviewStepView: View {
    @Bindable var store: ImportStore
    let dismiss: DismissAction

    private var resolution: CSVStatementResolution? {
        store.csvResolution
    }

    private var creditCardAccounts: [Account] {
        store.accounts.filter { $0.type == .creditCard && !$0.archived }
    }

    private var totalSelected: Int {
        resolution?.selectedCount ?? 0
    }

    private var canConfirm: Bool {
        guard let resolution else { return false }
        guard totalSelected > 0 else { return false }
        return resolution.accountId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card "Conta de destino" + skipped negatives info.
            VStack(alignment: .leading, spacing: 0) {
                CSVAccountInfoCard(
                    store: store,
                    accounts: creditCardAccounts
                )
                if let skipped = resolution?.skippedNegativeCount, skipped > 0 {
                    skippedBanner(count: skipped)
                }
            }

            // Bind direto pela projeção do @Bindable. `Binding($optional)`
            // devolve `Binding<T>?` quando o subjacente é não-nil; sem isso
            // o getter capturava o snapshot local do `if let` e mutações em
            // loop liam dados velhos (só a última escrita ficava).
            if let resolutionBinding = Binding($store.csvResolution) {
                CSVTransactionsListCard(
                    resolution: resolutionBinding,
                    institutionKind: bankKind(for: resolutionBinding.wrappedValue.accountId)
                )
            }

            BottomActionBar(caption: selectionCaption) {
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avançar com \(totalSelected) \(totalSelected == 1 ? "transação" : "transações")") {
                    Task { await store.confirmCSVImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
        }
        .navigationSubtitle(resolution?.sourceFilename ?? "")
    }

    /// Caption só pra bloqueios — stats vivem no header da lista agora.
    private var selectionCaption: String? {
        guard let resolution else { return nil }
        return resolution.accountId == nil ? "Escolha a conta-cartão de destino" : nil
    }

    private func skippedBanner(count: Int) -> some View {
        Form {
            Section {
                Label {
                    Text(
                        "\(count) \(count == 1 ? "linha ignorada" : "linhas ignoradas") (valores negativos: pagamentos da fatura anterior + estornos). Pagamentos serão registrados como transferência no extrato bancário."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func bankKind(for accountId: UUID?) -> InstitutionKind? {
        guard let accountId,
              let account = store.accounts.first(where: { $0.id == accountId }),
              let institutionId = account.institutionId,
              let institution = store.institutions.first(where: { $0.id == institutionId })
        else { return nil }
        return institution.kind
    }
}

/// Card "Conta de destino" do fluxo CSV. Picker simples — só lista contas
/// do tipo "Cartão de Crédito" existentes. Quando não há nenhuma, o
/// `loadCSV` já bloqueia o import com `ImportError.noCreditCardAccount`.
private struct CSVAccountInfoCard: View {
    @Bindable var store: ImportStore
    let accounts: [Account]

    private var resolution: CSVStatementResolution? {
        store.csvResolution
    }

    var body: some View {
        Form {
            Section {
                Picker("Conta-cartão", selection: Binding(
                    get: { store.csvResolution?.accountId },
                    set: { newValue in
                        Task { await store.setCSVAccount(newValue) }
                    }
                )) {
                    Text("Selecione…").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(Account.displayName(for: account, institutions: store.institutions))
                            .tag(UUID?.some(account.id))
                    }
                }
            } header: {
                HStack {
                    Text("Conta de destino")
                    Spacer()
                    if resolution?.accountId == nil {
                        Text("Escolha")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.warning.opacity(0.18))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lista de transações do preview CSV — virtualizada via LazyVStack dentro
/// de uma Section. Mesma estrutura usada pelo OFX (`TransactionsListCard`),
/// mas com row própria.
private struct CSVTransactionsListCard: View {
    @Binding var resolution: CSVStatementResolution
    let institutionKind: InstitutionKind?

    private var allSelected: Bool {
        !resolution.rows.isEmpty && resolution.rows.allSatisfy(\.selected)
    }

    var body: some View {
        Form {
            Section {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TransactionsSelectionRow(
                            summary: selectionSummary,
                            allSelected: allSelected,
                            onToggleAll: { value in
                                for idx in resolution.rows.indices {
                                    resolution.rows[idx].selected = value
                                }
                            }
                        )
                        Divider()
                        ForEach($resolution.rows) { $row in
                            CSVRowView(row: $row, institutionKind: institutionKind)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Transações")
            }
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

    private var selectionSummary: String {
        let selected = resolution.selectedCount
        let total = resolution.rows.count
        var parts = ["\(selected) de \(total) selecionadas"]
        if resolution.duplicateCount > 0 {
            parts.append("\(resolution.duplicateCount) \(resolution.duplicateCount == 1 ? "duplicada" : "duplicadas")")
        }
        return parts.joined(separator: " · ")
    }
}

/// Wrapper fino que mapeia `CSVPreviewRow` → `TransactionRow.importPreview`.
/// O `tipo` da fatura ("Parcelamento", "Internacional"...) vai como memo
/// quando difere do default "Compra à vista".
private struct CSVRowView: View {
    @Binding var row: CSVPreviewRow
    let institutionKind: InstitutionKind?

    var body: some View {
        // CSV de fatura: parser já filtra estornos/pagamentos como negativos
        // pra outra esteira (transfer). O que sobra é 100% despesa.
        TransactionRow(
            selection: $row.selected,
            institutionKind: institutionKind,
            description: row.raw.description,
            memo: memo,
            date: row.raw.date,
            amount: row.raw.amount,
            amountKind: .outgoing,
            status: row.isDuplicate ? .duplicate : nil
        )
    }

    private var memo: String? {
        let tipo = row.raw.tipo
        guard !tipo.isEmpty, tipo != "Compra à vista" else { return nil }
        return tipo
    }
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
            Text(
                "\(rowCount) \(rowCount == 1 ? "transação importada" : "transações importadas") em \(batchIds.count) \(batchIds.count == 1 ? "lote" : "lotes"). Categorias já aplicadas conforme sua revisão."
            )
        } actions: {
            Button("Desfazer \(batchIds.count == 1 ? "este lote" : "todos os lotes")", role: .destructive) {
                Task {
                    for id in batchIds {
                        await store.undo(batchId: id)
                    }
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
