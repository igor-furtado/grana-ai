#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Wizard de importação apresentado como **sheet modal** sobre a tela de
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
        .frame(minWidth: 880, minHeight: 620)
    }

    private func initialize() {
        let s = ImportStore(database: environment.database)
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
        case .mapping:
            MappingStepView(store: store)
        case .preview:
            PreviewStepView(store: store)
        case .ofxReview:
            OFXReviewStepView(store: store)
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

// MARK: - Idle (file picker)

private struct IdleStepView: View {
    @Binding var fileImporterShown: Bool
    let store: ImportStore

    var body: some View {
        ContentUnavailableView {
            Label("Importar extrato", systemImage: "square.and.arrow.down")
        } description: {
            Text("Selecione um arquivo **OFX** (preferido — auto-detecta a conta e o banco) ou um CSV/XLSX exportado do seu banco.")
        } actions: {
            Button("Escolher arquivo") { fileImporterShown = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(
            isPresented: $fileImporterShown,
            allowedContentTypes: Self.allowedTypes,
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

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .data]
        // XLSX UTI oficial. OFX não tem UTI declarado pela Apple, então
        // `.data` no array libera qualquer extensão — o `loadFile` ramifica
        // pela extensão real depois.
        if let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") {
            types.append(xlsx)
        }
        return types
    }
}

// MARK: - Mapping

private struct MappingStepView: View {
    @Bindable var store: ImportStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.sourceURL?.lastPathComponent ?? "—")
                    .font(.headline)
                Spacer()
                Button("Cancelar") { store.cancel() }
            }

            Form {
                Section("Conta destino") {
                    Picker("Conta", selection: $store.selectedAccountId) {
                        Text("Selecione…").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }

                if !templatesForCurrentKind.isEmpty {
                    Section("Template salvo") {
                        Picker("Aplicar template", selection: Binding<UUID?>(
                            get: { nil },
                            set: { id in
                                if let id, let t = templatesForCurrentKind.first(where: { $0.id == id }) {
                                    store.applyTemplate(t)
                                }
                            }
                        )) {
                            Text("Novo mapeamento").tag(UUID?.none)
                            ForEach(templatesForCurrentKind) { t in
                                Text(t.name).tag(UUID?.some(t.id))
                            }
                        }
                    }
                }

                Section("Formato") {
                    Picker("Formato da data", selection: $store.dateFormat) {
                        Text("dd/MM/yyyy").tag("dd/MM/yyyy")
                        Text("yyyy-MM-dd").tag("yyyy-MM-dd")
                        Text("dd-MM-yyyy").tag("dd-MM-yyyy")
                        Text("MM/dd/yyyy").tag("MM/dd/yyyy")
                    }
                    Picker("Separador decimal", selection: $store.decimalSeparator) {
                        Text("Vírgula (BR)").tag(",")
                        Text("Ponto (US/ISO)").tag(".")
                    }
                    Stepper(
                        value: $store.mapping.headerRowsToSkip,
                        in: 0...10
                    ) {
                        Text("Pular \(store.mapping.headerRowsToSkip) linhas iniciais")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 280)

            Text("Mapeamento de colunas")
                .font(.headline)

            ScrollView(.horizontal) {
                ColumnMappingTable(
                    rawRows: Array(store.rawRows.prefix(10)),
                    mapping: $store.mapping
                )
            }

            HStack {
                Spacer()
                Button("Gerar preview") {
                    Task { await store.generatePreview() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.mapping.isComplete || store.selectedAccountId == nil)
            }
        }
        .padding()
    }

    private var templatesForCurrentKind: [ImportTemplate] {
        guard let kind = store.sourceKind else { return [] }
        return store.availableTemplates.filter { $0.sourceKind == kind }
    }
}

// MARK: - Mapping table

private struct ColumnMappingTable: View {
    let rawRows: [[String]]
    @Binding var mapping: ColumnMapping

    private var columnCount: Int {
        rawRows.map(\.count).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<columnCount, id: \.self) { col in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Col \(col + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ColumnRolePicker(column: col, mapping: $mapping)
                    }
                    .frame(minWidth: 140, alignment: .leading)
                }
            }

            Divider()

            ForEach(Array(rawRows.enumerated()), id: \.offset) { rowOffset, row in
                HStack(spacing: 4) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        Text(col < row.count ? row[col] : "")
                            .font(.callout)
                            .lineLimit(1)
                            .frame(minWidth: 140, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
                .background(rowOffset % 2 == 0 ? Color.surfaceMuted.opacity(0.5) : Color.clear)
            }
        }
    }
}

private struct ColumnRolePicker: View {
    let column: Int
    @Binding var mapping: ColumnMapping

    enum Role: String, CaseIterable, Identifiable {
        case ignore   = "Ignorar"
        case date     = "Data"
        case description = "Descrição"
        case amount   = "Valor"
        case debit    = "Débito"
        case credit   = "Crédito"
        case notes    = "Notas"
        var id: String { rawValue }
    }

    var body: some View {
        Picker("", selection: roleBinding) {
            ForEach(Role.allCases) { role in
                Text(role.rawValue).tag(role)
            }
        }
        .labelsHidden()
    }

    private var roleBinding: Binding<Role> {
        Binding(
            get: { currentRole },
            set: { assign($0) }
        )
    }

    private var currentRole: Role {
        if mapping.date == column { return .date }
        if mapping.description == column { return .description }
        if mapping.amount == column { return .amount }
        if mapping.debit == column { return .debit }
        if mapping.credit == column { return .credit }
        if mapping.notes == column { return .notes }
        return .ignore
    }

    /// Atribuir um papel a uma coluna **remove esse mesmo papel de qualquer
    /// outra coluna** — não faz sentido ter duas colunas marcadas como "Data".
    /// Também limpa o papel anterior dessa coluna.
    private func assign(_ role: Role) {
        // Limpar coluna anterior do papel-alvo.
        switch role {
        case .ignore: break
        case .date: mapping.date = nil
        case .description: mapping.description = nil
        case .amount:
            mapping.amount = nil
            // Valor unificado é mutuamente exclusivo com débito/crédito.
            mapping.debit = nil
            mapping.credit = nil
        case .debit:
            mapping.debit = nil
            mapping.amount = nil
        case .credit:
            mapping.credit = nil
            mapping.amount = nil
        case .notes: mapping.notes = nil
        }

        // Remover esta coluna de qualquer papel que tinha antes.
        if mapping.date == column { mapping.date = nil }
        if mapping.description == column { mapping.description = nil }
        if mapping.amount == column { mapping.amount = nil }
        if mapping.debit == column { mapping.debit = nil }
        if mapping.credit == column { mapping.credit = nil }
        if mapping.notes == column { mapping.notes = nil }

        // Atribuir o papel novo.
        switch role {
        case .ignore: break
        case .date: mapping.date = column
        case .description: mapping.description = column
        case .amount: mapping.amount = column
        case .debit: mapping.debit = column
        case .credit: mapping.credit = column
        case .notes: mapping.notes = column
        }
    }
}

// MARK: - Preview

private struct PreviewStepView: View {
    @Bindable var store: ImportStore

    private var summary: (valid: Int, duplicate: Int, invalid: Int) {
        var v = 0, d = 0, i = 0
        for row in store.previewRows {
            switch row.status {
            case .valid: v += 1
            case .duplicate: d += 1
            case .invalidDate, .invalidAmount, .missingFields: i += 1
            }
        }
        return (v, d, i)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatusSummaryCard(title: "Válidas", count: summary.valid, color: .green, systemImage: "checkmark.circle.fill")
                StatusSummaryCard(title: "Duplicadas", count: summary.duplicate, color: .yellow, systemImage: "exclamationmark.triangle.fill")
                StatusSummaryCard(title: "Inválidas", count: summary.invalid, color: .red, systemImage: "xmark.circle.fill")
            }

            Toggle("Incluir duplicadas", isOn: $store.includeDuplicates)

            Table(store.previewRows) {
                TableColumn("Linha") { row in
                    Text("\(row.rowIndex + 1)").monospacedDigit()
                }
                .width(50)

                TableColumn("Status") { row in
                    statusBadge(row.status)
                }
                .width(120)

                TableColumn("Data") { row in
                    Text(row.derived.map { Self.dateFormatter.string(from: $0.occurredAt) } ?? "—")
                }
                .width(110)

                TableColumn("Descrição") { row in
                    Text(row.derived?.description ?? row.rawCells.dropFirst().first ?? "—")
                        .lineLimit(1)
                }

                TableColumn("Valor") { row in
                    if let amount = row.derived?.amount {
                        Text(Self.currencyFormatter.string(from: amount as NSDecimalNumber) ?? "—")
                            .foregroundStyle(amount < 0 ? .red : .green)
                            .monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(120)
            }
            .frame(minHeight: 300)

            Divider()

            HStack {
                TextField("Salvar como template (opcional)", text: $store.templateNameToSave)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Spacer()

                Button("Voltar") { store.backToMapping() }
                Button("Importar \(rowsToImportCount) transações") {
                    Task { await store.confirmImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rowsToImportCount == 0)
            }
        }
        .padding()
    }

    private var rowsToImportCount: Int {
        store.previewRows.reduce(0) { count, row in
            switch row.status {
            case .valid: return count + 1
            case .duplicate: return store.includeDuplicates ? count + 1 : count
            default: return count
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PreviewStatus) -> some View {
        switch status {
        case .valid:
            Label("Válida", systemImage: "checkmark.circle.fill").foregroundStyle(.success)
        case .duplicate:
            Label("Duplicada", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.warning)
        case .invalidDate:
            Label("Data inválida", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.danger)
        case .invalidAmount:
            Label("Valor inválido", systemImage: "dollarsign.circle.trianglebadge.exclamationmark").foregroundStyle(.danger)
        case .missingFields:
            Label("Vazia", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
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

private struct StatusSummaryCard: View {
    let title: String
    let count: Int
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Importar extrato")
                        .font(.title3.weight(.semibold))
                    Text(store.sourceURL?.lastPathComponent ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(store.ofxResolutions.indices, id: \.self) { idx in
                        StatementCard(
                            resolution: $store.ofxResolutions[idx],
                            store: store
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { store.cancel() }
                Button("Importar \(totalSelected) \(totalSelected == 1 ? "transação" : "transações") em \(statementsWithAnySelected) \(statementsWithAnySelected == 1 ? "lote" : "lotes")") {
                    Task { await store.confirmOFXImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(totalSelected == 0)
            }
        }
        .padding()
    }
}

/// Cartão por `STMTRS`. Estrutura visual em duas seções claras:
///
/// - **Conta de destino**: caixa cinza com os dados do banco lidos do
///   próprio OFX (read-only). Quando a conta vai ser criada, um banner
///   indica isso + permite editar o nome amigável.
/// - **Transações encontradas**: master checkbox + lista. Linhas duplicadas
///   ganham badge "JÁ IMPORTADA" e vêm desmarcadas.
private struct StatementCard: View {
    @Binding var resolution: OFXStatementResolution
    let store: ImportStore

    private var allSelected: Bool {
        // Considera só as linhas "selecionáveis" (válidas + duplicadas) — as
        // inválidas nem entram no toggle.
        let selectable = resolution.rows.filter { isSelectable($0) }
        return !selectable.isEmpty && selectable.allSatisfy(\.selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accountSection
            transactionsSection
        }
    }

    // MARK: Account section

    @ViewBuilder
    private var accountSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Informações do banco", systemImage: "building.columns")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if resolution.isAccountNew {
                        Text("Nova conta")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.success.opacity(0.15))
                            .foregroundStyle(.success)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(institutionDisplayName)
                        .font(.headline)
                    Text("\(resolution.institution.code) · \(resolution.account.type.displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Conta: \(resolution.account.accountNumber) · Agência: \(resolution.account.branchId ?? "—")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if resolution.isAccountNew {
                    Divider()
                    LabeledContent("Nome amigável") {
                        TextField("", text: $resolution.account.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker("Tipo", selection: $resolution.account.type) {
                        ForEach(AccountType.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.vertical, 6)
        } label: {
            Text("Conta de destino")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var institutionDisplayName: String {
        // Preferir o nome do <FI><ORG> do próprio OFX (representa o que veio
        // no arquivo). Cai pro `Institution.name` do DB quando ausente.
        resolution.statement.institutionHeader.organization
            ?? resolution.institution.name
    }

    // MARK: Transactions section

    @ViewBuilder
    private var transactionsSection: some View {
        GroupBox {
            // `LazyVStack` (em vez de `VStack`) é crítico aqui: extratos do
            // Inter chegam com 500+ transações. `VStack` materializa todas as
            // rows na construção da View — em testes com 557 rows o app
            // chegou a 3+ GB de RAM. `LazyVStack` só renderiza o que entra
            // no viewport do `ScrollView` externo (`OFXReviewStepView`), o
            // que mantém o uso de memória estável independente do tamanho do
            // extrato.
            LazyVStack(spacing: 0) {
                ForEach(resolution.rows.indices, id: \.self) { idx in
                    OFXRowView(row: $resolution.rows[idx], store: store)
                    if idx < resolution.rows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text("Transações encontradas")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { toggleAll(to: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(allSelected ? "Desmarcar todas" : "Marcar todas selecionáveis")
            }
        }
    }

    private func isSelectable(_ row: OFXPreviewRow) -> Bool {
        switch row.status {
        case .valid, .duplicate: return true
        default: return false
        }
    }

    private func toggleAll(to value: Bool) {
        for idx in resolution.rows.indices where isSelectable(resolution.rows[idx]) {
            resolution.rows[idx].selected = value
        }
    }
}

/// Uma transação no preview. Layout:
/// `[Data + Valor (col esquerda)]  [Descrição + Memo (col central)]  [Categoria | Subcategoria pickers]  [JÁ IMPORTADA badge]  [Checkbox]`
private struct OFXRowView: View {
    @Binding var row: OFXPreviewRow
    let store: ImportStore

    private var isDuplicate: Bool {
        if case .duplicate = row.status { return true }
        return false
    }

    private var isInvalid: Bool {
        switch row.status {
        case .invalidDate, .invalidAmount, .missingFields: return true
        default: return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Data + valor (esquerda)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: row.derived.occurredAt))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(Self.currencyFormatter.string(from: row.derived.amount as NSDecimalNumber) ?? "")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(row.derived.amount < 0 ? .red : .green)
            }
            .frame(width: 110, alignment: .leading)

            // Descrição (centro)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryDescription)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                if let secondary = secondaryDescription {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Pickers de categoria — só pra linhas válidas (não inválidas, não duplicadas).
            if !isInvalid && !isDuplicate {
                categoryPickers
                    .frame(width: 320)
            }

            // Badge "Já importada" pra duplicatas.
            if isDuplicate {
                Text("Já importada")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.warning.opacity(0.18))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            // Checkbox final. Inválidas: bloqueada (nem como override).
            Toggle("", isOn: $row.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isInvalid)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .opacity(rowOpacity)
    }

    /// **Por que `Menu` em vez de `Picker`:** `Picker` materializa todos os
    /// `Text` filhos imediatamente — em extratos com 500+ linhas isso é 500
    /// pickers × 15 categorias = 7500 views materializadas só pra essa coluna,
    /// e mais N pickers de subcategoria. `Menu` constrói o conteúdo apenas
    /// quando o usuário abre, reduzindo o custo de render por linha em ordem
    /// de magnitude.
    @ViewBuilder
    private var categoryPickers: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.rootCategories) { cat in
                    Button(cat.name) {
                        row.categoryId = cat.id
                        row.subcategoryId = nil
                    }
                }
            } label: {
                menuLabel(text: store.category(for: row.categoryId)?.name ?? "Categoria")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)

            Menu {
                Button("Nenhuma") { row.subcategoryId = nil }
                ForEach(store.subcategories(of: row.categoryId)) { sub in
                    Button(sub.name) { row.subcategoryId = sub.id }
                }
            } label: {
                menuLabel(text: subcategoryName ?? "Subcategoria")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)
        }
    }

    private var subcategoryName: String? {
        guard let id = row.subcategoryId, let cat = store.category(for: id) else { return nil }
        return cat.name
    }

    private func menuLabel(text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var primaryDescription: String {
        // NAME geralmente é a contraparte ("Igor Talisson..."), MEMO traz o
        // detalhe ("Pix recebido: Cp :..."). Mostrar NAME como primário.
        if let name = row.raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return row.derived.description
    }

    private var secondaryDescription: String? {
        let memo = row.raw.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let memo, !memo.isEmpty, memo != primaryDescription {
            return memo
        }
        return nil
    }

    private var rowOpacity: Double {
        if isInvalid { return 0.55 }
        if isDuplicate && !row.selected { return 0.55 }
        return 1.0
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
            Label("Importação concluída", systemImage: "checkmark.seal.fill")
        } description: {
            Text("\(rowCount) \(rowCount == 1 ? "transação importada" : "transações importadas") em \(batchIds.count) \(batchIds.count == 1 ? "lote" : "lotes"). A categorização inicial é heurística — você pode ajustar manualmente ou esperar a IA refinar.")
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
            Label("Algo deu errado", systemImage: "exclamationmark.triangle.fill")
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

#endif
