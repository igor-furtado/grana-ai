import Foundation
import Observation
import OSLog

/// Estado observável do wizard de importação. Suporta dois fluxos:
///
/// - **CSV/XLSX** (Fase 3 inicial): `idle → mapping → preview → confirming → done`.
/// - **OFX**: `idle → ofxReview → confirming → done`. Auto-detecta instituição
///   e conta a partir do próprio arquivo; usuário só confirma os nomes
///   amigáveis quando contas novas precisam ser criadas.
///
/// Cada `STMTRS` do OFX vira um batch independente; múltiplas contas no
/// mesmo arquivo geram múltiplas operações de auto-create — tudo em uma
/// única `writeTransaction` pra atomicidade.
@MainActor
@Observable
final class ImportStore {
    enum Phase: Equatable {
        case idle
        /// Após o file picker, antes do `ofxReview`. Parsing + dedup
        /// podem demorar em extratos grandes (centenas de transações) —
        /// sem esse estado a UI parece travada.
        case loading(progress: String)
        case mapping
        case preview
        case ofxReview
        case confirming
        case done(batchIds: [UUID], rowCount: Int)
        case failed(message: String)
    }

    private let database: AppDatabase

    private(set) var phase: Phase = .idle

    /// Contexto do arquivo aberto. Fica fora do `Phase` pra sobreviver às
    /// transições.
    private(set) var sourceURL: URL?
    private(set) var sourceKind: ImportSourceKind?
    private(set) var rawRows: [[String]] = []
    private(set) var previewRows: [ImportPreviewRow] = []

    /// Dados "vivos" do wizard CSV/XLSX. Não ficam no `Phase` porque o usuário
    /// pode ajustar mapping/conta/template enquanto a fase é a mesma (`mapping`).
    var selectedAccountId: UUID?
    var mapping = ColumnMapping()
    var dateFormat: String = "dd/MM/yyyy"
    var decimalSeparator: String = ","
    var includeDuplicates: Bool = false
    var templateNameToSave: String = ""

    /// Fluxo OFX.
    private(set) var ofxDocument: OFXDocument?
    var ofxResolutions: [OFXStatementResolution] = []

    private(set) var availableTemplates: [ImportTemplate] = []
    private(set) var batches: [ImportBatch] = []
    private(set) var accounts: [Account] = []
    private(set) var institutions: [Institution] = []
    /// Carregadas no `loadInitialData` pra alimentar os pickers de
    /// categoria/subcategoria do preview OFX sem chamar o repo a cada View.
    private(set) var categories: [Category] = []

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Bootstrap

    func loadInitialData() async {
        do {
            accounts = try await database.accounts.getAll()
            institutions = try await database.institutions.getAll()
            categories = try await database.categories.getAll()
            availableTemplates = try await database.importTemplates.getAll()
            batches = try await database.importBatches.getAll()
        } catch {
            log.database.error("ImportStore.loadInitialData falhou: \(String(describing: error))")
        }
    }

    // MARK: - Category helpers (pra UI)

    var rootCategories: [Category] {
        categories.filter { $0.parentId == nil }
    }

    func subcategories(of parentId: UUID) -> [Category] {
        categories.filter { $0.parentId == parentId }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    func refreshBatches() async {
        do { batches = try await database.importBatches.getAll() }
        catch { log.database.error("refreshBatches falhou: \(String(describing: error))") }
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: - File loading

    func loadFile(url: URL) async {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let kind = try SpreadsheetReaderFactory.sourceKind(for: url)
            sourceURL = url
            sourceKind = kind

            switch kind {
            case .ofx:
                try await loadOFX(url: url)
            case .csv, .xlsx:
                try await loadTabular(url: url, kind: kind)
            }
        } catch let error as ImportError {
            phase = .failed(message: error.localizedDescription)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    /// Reporta uma falha originada **fora** do `loadFile` — tipicamente um
    /// erro do `fileImporter` da SwiftUI (permissão negada, sandbox, etc.).
    /// Sem isso a UI ficava silenciosa quando o picker do sistema falhava.
    func reportFileImportFailure(_ error: Error) {
        log.database.error("fileImporter falhou: \(String(describing: error))")
        phase = .failed(message: error.localizedDescription)
    }

    private func loadTabular(url: URL, kind: ImportSourceKind) async throws {
        let reader = try SpreadsheetReaderFactory.reader(for: url)
        let rows = try reader.readRows(from: url)
        if rows.isEmpty {
            phase = .failed(message: ImportError.emptySheet.localizedDescription)
            return
        }
        mapping = ColumnMapping()
        rawRows = rows
        previewRows = []
        phase = .mapping
    }

    /// Lê OFX → cria `ofxResolutions` (uma por `STMTRS`) com auto-detect de
    /// instituição/conta + parsing de cada transação + detecção de duplicata
    /// via FITID. Move pra `.ofxReview`.
    private func loadOFX(url: URL) async throws {
        phase = .loading(progress: "Lendo arquivo…")
        let reader = OFXReader()
        let document = try reader.read(from: url)
        ofxDocument = document

        phase = .loading(progress: "Resolvendo categorias…")
        // Resolver categorias raiz uma vez — heurística reusa os IDs.
        let heuristic = try await buildHeuristic()

        var resolutions: [OFXStatementResolution] = []
        for (idx, statement) in document.statements.enumerated() {
            phase = .loading(progress: document.statements.count > 1
                ? "Processando conta \(idx + 1) de \(document.statements.count)…"
                : "Processando \(statement.transactions.count) transações…")
            let resolution = try await resolveStatement(statement, heuristic: heuristic)
            resolutions.append(resolution)
        }
        ofxResolutions = resolutions

        if resolutions.allSatisfy({ $0.rows.isEmpty }) {
            phase = .failed(message: ImportError.noValidRows.localizedDescription)
            return
        }
        phase = .ofxReview
    }

    /// Materializa uma `OFXStatementResolution` a partir de um `OFXStatement`
    /// parseado. Faz, em ordem:
    /// 1. Auto-detect da instituição via FID (busca por código; se não achar
    ///    e o kind for `.inter`, usa o seed; se for `.other`, draft com nome
    ///    do OFX que o usuário pode editar).
    /// 2. Match exato da conta pela tripla (institution, branch, accountId).
    /// 3. Parsing de cada transação em `DerivedTransaction` + detecção de
    ///    duplicata via FITID (só faz sentido quando a conta já existe).
    private func resolveStatement(
        _ statement: OFXStatement,
        heuristic: OFXCategoryHeuristic
    ) async throws -> OFXStatementResolution {
        let inst = try await resolveInstitution(for: statement)
        let acc = try await resolveAccount(for: statement, institution: inst)

        // **Batched dedup**: pra contas existentes, busca TODOS os FITIDs já
        // gravados de uma vez e converte pra Set. O check por linha vira O(1)
        // em memória em vez de uma query por linha — em extratos com 500+
        // transações isso é a diferença entre <1s e 30+s.
        let existingExternalIds: Set<String>
        if let existingId = acc.existingId {
            existingExternalIds = (try? await database.transactions.externalIds(forAccount: existingId)) ?? []
        } else {
            existingExternalIds = []
        }

        var rows: [OFXPreviewRow] = []
        rows.reserveCapacity(statement.transactions.count)
        for trn in statement.transactions {
            var status: PreviewStatus = .valid
            if existingExternalIds.contains(trn.fitid) {
                status = .duplicate(matching: [])
            }
            let derived = DerivedTransaction(
                occurredAt: trn.datePosted,
                amount: trn.amount,
                description: trn.displayDescription,
                notes: trn.memo
            )
            // Defaults sensatos: válidas selecionadas, duplicadas desligadas.
            // Usuário re-marca duplicadas explicitamente caso queira re-importar.
            let selected: Bool = {
                if case .valid = status { return true }
                return false
            }()
            rows.append(OFXPreviewRow(
                raw: trn,
                derived: derived,
                status: status,
                categoryId: heuristic.categoryId(for: trn),
                subcategoryId: nil,
                selected: selected
            ))
        }

        return OFXStatementResolution(
            statement: statement,
            institution: inst,
            account: acc,
            rows: rows
        )
    }

    private func resolveInstitution(for statement: OFXStatement) async throws -> InstitutionResolution {
        let code = statement.account.bankId
        if let existing = try await database.institutions.findByCode(code) {
            return InstitutionResolution(
                existingId: existing.id,
                code: existing.code,
                name: existing.name,
                kind: existing.kind
            )
        }
        // Não existe → propor criação. Detecta kind pelo FID; se desconhecido,
        // usa nome vindo do <FI><ORG> do arquivo (ou fallback genérico).
        let kind = InstitutionKind.fromCode(code)
        let name = statement.institutionHeader.organization ?? kind.displayName
        return InstitutionResolution(existingId: nil, code: code, name: name, kind: kind)
    }

    private func resolveAccount(
        for statement: OFXStatement,
        institution: InstitutionResolution
    ) async throws -> AccountResolution {
        let bankAccount = statement.account
        if let institutionId = institution.existingId,
           let existing = try await database.accounts.findByBankIdentity(
               institutionId: institutionId,
               branchId: bankAccount.branchId,
               accountNumber: bankAccount.accountId
           ) {
            return AccountResolution(
                existingId: existing.id,
                name: existing.name,
                type: existing.type,
                branchId: existing.branchId,
                accountNumber: existing.accountNumber ?? bankAccount.accountId,
                currency: existing.currency
            )
        }
        // Não existe → draft pré-preenchido pra criação.
        return AccountResolution(
            existingId: nil,
            name: defaultName(for: bankAccount, institution: institution),
            type: bankAccount.mappedAccountType,
            branchId: bankAccount.branchId,
            accountNumber: bankAccount.accountId,
            currency: statement.currency
        )
    }

    private func defaultName(
        for bankAccount: OFXAccountKey,
        institution: InstitutionResolution
    ) -> String {
        // "Inter · 310013887" é compacto e único o suficiente. Usuário pode
        // renomear antes de confirmar.
        "\(institution.name) · \(bankAccount.accountId)"
    }

    /// Resolve as categorias raiz "Não Classificado", "Transferências" e
    /// "Renda e Pagamentos" pra alimentar a heurística. As duas últimas são
    /// opcionais (a heurística cai pra unclassified se faltarem).
    private func buildHeuristic() async throws -> OFXCategoryHeuristic {
        guard let unclassified = try await database.categories.findRootByName("Não Classificado") else {
            throw ImportError.unclassifiedCategoryMissing
        }
        let transfers = try await database.categories.findRootByName("Transferências")
        let income = try await database.categories.findRootByName("Renda e Pagamentos")
        return OFXCategoryHeuristic(roots: .init(
            unclassified: unclassified.id,
            transfers: transfers?.id,
            income: income?.id
        ))
    }

    // MARK: - CSV/XLSX flow (existente)

    func applyTemplate(_ template: ImportTemplate) {
        mapping = template.mapping
        dateFormat = template.dateFormat
        decimalSeparator = template.decimalSeparator
        if let defaultId = template.defaultAccountId {
            selectedAccountId = defaultId
        }
    }

    func generatePreview() async {
        guard phase == .mapping else { return }
        if !mapping.isComplete {
            phase = .failed(message: ImportError.mappingIncomplete.localizedDescription)
            return
        }
        let parser = ImportParser(
            mapping: mapping,
            dateFormat: dateFormat,
            decimalSeparator: decimalSeparator
        )
        var rows = parser.parse(rows: rawRows)
        for i in rows.indices {
            guard case .valid = rows[i].status, let d = rows[i].derived else { continue }
            do {
                let matches = try await database.transactions.findPotentialDuplicates(
                    date: d.occurredAt,
                    amountCents: Converters.decimalToCents(d.amount),
                    description: d.description
                )
                if !matches.isEmpty {
                    rows[i].status = .duplicate(matching: matches.map(\.id))
                }
            } catch {
                log.database.error("findPotentialDuplicates falhou: \(String(describing: error))")
            }
        }
        previewRows = rows
        phase = .preview
    }

    func backToMapping() {
        guard phase == .preview else { return }
        previewRows = []
        phase = .mapping
    }

    func cancel() {
        phase = .idle
        mapping = ColumnMapping()
        sourceURL = nil
        sourceKind = nil
        rawRows = []
        previewRows = []
        selectedAccountId = nil
        templateNameToSave = ""
        includeDuplicates = false
        ofxDocument = nil
        ofxResolutions = []
    }

    // MARK: - Confirm CSV/XLSX (existente)

    func confirmImport() async {
        guard phase == .preview else { return }
        let rows = previewRows
        guard let accountId = selectedAccountId else {
            phase = .failed(message: "Selecione uma conta antes de importar.")
            return
        }
        phase = .confirming

        do {
            guard let fallback = try await database.categories.findRootByName("Não Classificado") else {
                throw ImportError.unclassifiedCategoryMissing
            }

            let selectedRows = rows.compactMap { row -> DerivedTransaction? in
                switch row.status {
                case .valid:        return row.derived
                case .duplicate:    return includeDuplicates ? row.derived : nil
                default:            return nil
                }
            }
            if selectedRows.isEmpty {
                phase = .failed(message: ImportError.noValidRows.localizedDescription)
                return
            }

            let trimmedTemplateName = templateNameToSave.trimmingCharacters(in: .whitespacesAndNewlines)
            var templateId: UUID? = nil
            if !trimmedTemplateName.isEmpty {
                let now = Date()
                let kind = sourceKind ?? .csv
                let template = ImportTemplate(
                    id: UUID(),
                    name: trimmedTemplateName,
                    sourceKind: kind,
                    mapping: mapping,
                    dateFormat: dateFormat,
                    decimalSeparator: decimalSeparator,
                    defaultAccountId: accountId,
                    createdAt: now,
                    updatedAt: now
                )
                try await database.importTemplates.insert(template)
                templateId = template.id
            }

            let now = Date()
            let batchId = UUID()
            let batch = ImportBatch(
                id: batchId,
                sourceFilename: sourceURL?.lastPathComponent ?? "import",
                sourceKind: sourceKind ?? .csv,
                templateId: templateId,
                accountId: accountId,
                rowCount: selectedRows.count,
                importedAt: now,
                createdAt: now,
                updatedAt: now
            )
            // Convenção do app: `amount` armazena MAGNITUDE; o sinal (entrada
            // vs saída) vem do `kind` da categoria associada. O parser
            // CSV/XLSX devolve valores com sinal pra distinguir débito de
            // crédito; normalizamos pra magnitude na inserção pra ficar
            // consistente com a entrada manual e com as agregações do
            // dashboard, que assumem magnitude.
            let transactions: [Transaction] = selectedRows.map { d in
                Transaction(
                    id: UUID(),
                    accountId: accountId,
                    categoryId: fallback.id,
                    subcategoryId: nil,
                    amount: abs(d.amount),
                    occurredAt: d.occurredAt,
                    description: d.description,
                    notes: d.notes,
                    importBatchId: batchId,
                    externalId: nil,
                    createdAt: now,
                    updatedAt: now
                )
            }
            do {
                try await database.transactions.insertBatch(transactions, batch: batch)
            } catch {
                throw ImportError.batchInsertFailed(underlying: error)
            }

            await refreshBatches()
            if templateId != nil {
                availableTemplates = (try? await database.importTemplates.getAll()) ?? availableTemplates
            }
            phase = .done(batchIds: [batchId], rowCount: transactions.count)
            templateNameToSave = ""
        } catch let error as ImportError {
            phase = .failed(message: error.localizedDescription)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Confirm OFX (multi-account)

    /// Materializa todos os `OFXStatementResolution` selecionados em um
    /// **único** `writeTransaction`:
    /// - cria instituições novas (1 por banco que ainda não existia);
    /// - cria contas novas (1 por statement com conta inédita);
    /// - cria N `import_batches` + as `transactions` correspondentes.
    ///
    /// Se qualquer execute lançar, toda a operação é desfeita — o app nunca
    /// fica com batches órfãos ou contas sem batch.
    func confirmOFXImport() async {
        guard phase == .ofxReview else { return }

        // Quando o mesmo `code` aparece em múltiplos statements, todos têm
        // que ter `name` e `kind` consistentes — caso contrário a edição de
        // um deles seria descartada silenciosamente ao escolher um único
        // representante. Falhar alto pra forçar o usuário a alinhar.
        let grouped = Dictionary(grouping: ofxResolutions, by: { $0.institution.code })
        for (code, group) in grouped where group.count > 1 {
            let names = Set(group.map { $0.institution.name })
            let kinds = Set(group.map { $0.institution.kind })
            if names.count > 1 || kinds.count > 1 {
                phase = .failed(message: "Múltiplas contas usam o código \(code) mas com nome ou tipo divergente. Edite todas pra ficarem iguais antes de confirmar.")
                return
            }
        }

        phase = .confirming

        do {
            let now = Date()

            // Materializar IDs definitivos pra Institutions e Accounts (existe
            // ou cria). Stub mutável pra rastrear os IDs novos pra reutilizar
            // em statements posteriores que apontem pra mesma instituição.
            var institutionsToInsert: [Institution] = []
            var resolvedInstitutionIds: [String: UUID] = [:]   // code → id
            for code in Set(ofxResolutions.map { $0.institution.code }) {
                if let resolution = ofxResolutions.first(where: { $0.institution.code == code }) {
                    if let existing = resolution.institution.existingId {
                        resolvedInstitutionIds[code] = existing
                    } else {
                        let newInst = Institution(
                            id: UUID(),
                            code: code,
                            name: resolution.institution.name,
                            kind: resolution.institution.kind,
                            createdAt: now,
                            updatedAt: now
                        )
                        institutionsToInsert.append(newInst)
                        resolvedInstitutionIds[code] = newInst.id
                    }
                }
            }

            var accountsToInsert: [Account] = []
            var batchesWithTransactions: [(batch: ImportBatch, transactions: [Transaction])] = []

            for resolution in ofxResolutions {
                // Cada linha controla sua própria inclusão via `selected`.
                // Duplicadas vêm desligadas; usuário re-marca pra re-importar.
                let toImport = resolution.rows.filter { $0.selected }
                if toImport.isEmpty { continue }

                let institutionId = resolvedInstitutionIds[resolution.institution.code]
                let accountId: UUID
                if let existingId = resolution.account.existingId {
                    accountId = existingId
                } else {
                    let newAccount = Account(
                        id: UUID(),
                        name: resolution.account.name,
                        type: resolution.account.type,
                        initialBalance: 0,
                        archived: false,
                        institutionId: institutionId,
                        branchId: resolution.account.branchId,
                        accountNumber: resolution.account.accountNumber,
                        currency: resolution.account.currency,
                        createdAt: now,
                        updatedAt: now
                    )
                    accountsToInsert.append(newAccount)
                    accountId = newAccount.id
                }

                let batchId = UUID()
                let batch = ImportBatch(
                    id: batchId,
                    sourceFilename: sourceURL?.lastPathComponent ?? "import.ofx",
                    sourceKind: .ofx,
                    templateId: nil,
                    accountId: accountId,
                    rowCount: toImport.count,
                    importedAt: now,
                    createdAt: now,
                    updatedAt: now
                )
                // Convenção do app: `amount` armazena MAGNITUDE; o sinal
                // (entrada vs saída) vem do `kind` da categoria associada.
                // OFX TRNAMT é signed (negativo pra débito); normalizamos
                // pra magnitude na inserção pra que `SUM(amount_cents)` por
                // kind continue válido junto com lançamentos manuais.
                let txs: [Transaction] = toImport.map { row in
                    Transaction(
                        id: UUID(),
                        accountId: accountId,
                        categoryId: row.categoryId,
                        subcategoryId: row.subcategoryId,
                        amount: abs(row.derived.amount),
                        occurredAt: row.derived.occurredAt,
                        description: row.derived.description,
                        notes: row.derived.notes,
                        importBatchId: batchId,
                        externalId: row.raw.fitid,
                        createdAt: now,
                        updatedAt: now
                    )
                }
                batchesWithTransactions.append((batch, txs))
            }

            if batchesWithTransactions.isEmpty {
                phase = .failed(message: ImportError.noValidRows.localizedDescription)
                return
            }

            do {
                try await database.transactions.insertMultipleBatches(
                    institutions: institutionsToInsert,
                    accounts: accountsToInsert,
                    batchesWithTransactions: batchesWithTransactions
                )
            } catch {
                throw ImportError.batchInsertFailed(underlying: error)
            }

            // Atualizar caches locais.
            accounts = try await database.accounts.getAll()
            institutions = try await database.institutions.getAll()
            await refreshBatches()

            let totalRows = batchesWithTransactions.reduce(0) { $0 + $1.transactions.count }
            let batchIds = batchesWithTransactions.map { $0.batch.id }
            phase = .done(batchIds: batchIds, rowCount: totalRows)
        } catch let error as ImportError {
            phase = .failed(message: error.localizedDescription)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Undo

    func undo(batchId: UUID) async {
        do {
            try await database.importBatches.delete(id: batchId)
            await refreshBatches()
        } catch {
            log.database.error("undo(batchId:) falhou: \(String(describing: error))")
        }
    }
}

// MARK: - OFX resolution data structures

/// Estado por `STMTRS`. Mutável — o usuário pode editar o `name` da conta
/// nova antes de confirmar.
struct OFXStatementResolution: Identifiable, Equatable {
    let id = UUID()
    let statement: OFXStatement
    var institution: InstitutionResolution
    var account: AccountResolution
    var rows: [OFXPreviewRow]

    var isAccountNew: Bool { account.existingId == nil }
    var isInstitutionNew: Bool { institution.existingId == nil }

    var validRowCount: Int {
        rows.filter { if case .valid = $0.status { return true }; return false }.count
    }
    var duplicateRowCount: Int {
        rows.filter { if case .duplicate = $0.status { return true }; return false }.count
    }
}

struct InstitutionResolution: Equatable {
    var existingId: UUID?
    var code: String
    var name: String
    var kind: InstitutionKind
}

struct AccountResolution: Equatable {
    var existingId: UUID?
    var name: String
    var type: AccountType
    var branchId: String?
    var accountNumber: String
    var currency: String
}

struct OFXPreviewRow: Identifiable, Hashable {
    let id = UUID()
    let raw: OFXTransaction
    var derived: DerivedTransaction
    var status: PreviewStatus
    /// ID da categoria raiz vindo da heurística. Resolvido no `ImportStore`,
    /// não na View, pra evitar passar `database` adiante. Pode ser editado
    /// pelo usuário no preview.
    var categoryId: UUID
    /// Subcategoria opcional. NULL no momento da geração; usuário pode
    /// selecionar uma sub durante o review.
    var subcategoryId: UUID?
    /// Marca por linha: válida → ligada por default; duplicada → desligada
    /// (usuário re-marca pra re-importar). Substitui o toggle global
    /// "incluir duplicadas" do fluxo CSV/XLSX.
    var selected: Bool
}
