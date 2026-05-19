import Foundation
import Observation
import OSLog

/// Estado observável do wizard de importação OFX.
///
/// Fluxo: `idle → loading → ofxReview → categorizing → reviewingCategorization
/// → confirming → done` (ou `failed` em qualquer transição).
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
        case ofxReview
        /// Fase 4: rodando categorização da IA pré-commit. Drafts já montados,
        /// transações ainda NÃO foram inseridas no banco.
        case categorizing
        /// Fase 4: tela de revisão das sugestões antes do commit. Cancelar
        /// aqui descarta tudo; "Importar" finaliza.
        case reviewingCategorization
        case confirming
        case done(batchIds: [UUID], rowCount: Int)
        case failed(message: String)
    }

    private let database: AppDatabase

    private(set) var phase: Phase = .idle

    /// Fase 4: store de categorização compartilhado entre os steps do wizard.
    /// Disparado **antes** do commit ao banco — a tela de revisão é parte do
    /// fluxo, não um post-step. Cancelar o import descarta tudo (nenhuma
    /// transaction vai pro banco se o usuário não confirmar).
    let categorization: CategorizationStore

    // Fase 4: estado "em voo" entre o preview e o commit final. Construído
    // pelo `confirmOFXImport`; consumido pelo `finalizeImport`.
    private(set) var pendingDrafts: [TransactionDraft] = []
    private(set) var pendingInstitutionsToInsert: [Institution] = []
    private(set) var pendingAccountsToInsert: [Account] = []
    private(set) var pendingBatchesWithDrafts: [(batch: ImportBatch, draftIds: [UUID])] = []

    /// Contexto do arquivo aberto. Fica fora do `Phase` pra sobreviver às
    /// transições.
    private(set) var sourceURL: URL?

    /// Fluxo OFX.
    private(set) var ofxDocument: OFXDocument?
    var ofxResolutions: [OFXStatementResolution] = []

    private(set) var batches: [ImportBatch] = []
    private(set) var accounts: [Account] = []
    private(set) var institutions: [Institution] = []
    /// Carregadas no `loadInitialData` pra alimentar os pickers de
    /// categoria/subcategoria do preview OFX sem chamar o repo a cada View.
    private(set) var categories: [Category] = []

    /// Task que espera a categorização terminar pra avançar a fase. Guardada
    /// pra que `cancel()` consiga interromper o polling — sem isso, cancelar
    /// no meio do `.categorizing` deixa um loop rodando indefinidamente.
    private var categorizationWaitTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        self.categorization = CategorizationStore(database: database)
    }

    // MARK: - Categorização pré-commit (Fase 4)

    /// Configura thresholds via `UserDefaults` e dispara a categorização pré-commit
    /// pra os drafts em voo. Move o wizard pra `.categorizing` e observa a
    /// conclusão pra avançar pra `.reviewingCategorization`.
    ///
    /// Falha de IA NÃO bloqueia o usuário: o service devolve `.fallback` pra
    /// todos os misses; o usuário ainda pode revisar/importar manualmente.
    private func startCategorization() {
        let defaults = UserDefaults.standard
        let autoApproved = defaults.object(forKey: CategorizationDefaultsKey.autoApproved) as? Double ?? 0.85
        let reviewRequired = defaults.object(forKey: CategorizationDefaultsKey.reviewRequired) as? Double ?? 0.70
        categorization.thresholds = CategorizationService.ConfidenceThresholds(
            autoApproved: autoApproved,
            reviewRequired: reviewRequired
        )

        phase = .categorizing
        categorizationWaitTask?.cancel()
        categorizationWaitTask = Task { [weak self] in
            guard let self else { return }
            await self.categorization.loadCategories()
            self.categorization.classifyDrafts(self.pendingDrafts)
            // Observa o status do categorization store em loop curto pra
            // avançar pra `.reviewingCategorization` quando ficar ready (ou
            // pra `.failed` se rolar erro).
            await self.awaitCategorizationCompletion()
        }
    }

    private func awaitCategorizationCompletion() async {
        // Aguarda a task interna do CategorizationStore terminar e então
        // inspeciona o status pra decidir a fase. Sem polling — o
        // CategorizationStore expõe `waitForCompletion()` que faz
        // `await currentTask?.value`.
        //
        // `.idle` significa "cancelado" (inner Task entrou no catch de
        // CancellationError) — sai sem mudar fase, quem cancelou cuida.
        await categorization.waitForCompletion()
        guard !Task.isCancelled else { return }

        switch categorization.status {
        case .ready:
            phase = .reviewingCategorization
        case .failed(let message):
            // Mesmo em falha, deixa o usuário revisar — sugestões fallback
            // ainda permitem confirmar/corrigir manualmente. O erro
            // original já foi reportado ao ErrorCenter pelo CategorizationStore;
            // aqui é só um aviso de fluxo (info, não erro).
            log.ai.notice("Categorização falhou: \(message, privacy: .public). Avançando pra revisão com fallbacks.")
            phase = .reviewingCategorization
        case .idle, .classifying:
            // Cancelado (idle) ou estado inesperado — não mexe na fase.
            return
        }
    }

    // MARK: - Bootstrap

    func loadInitialData() async {
        do {
            accounts = try await database.accounts.getAll()
            institutions = try await database.institutions.getAll()
            categories = try await database.categories.getAll()
            batches = try await database.importBatches.getAll()
        } catch {
            ErrorCenter.shared.report(error)
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
        catch { ErrorCenter.shared.report(error) }
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: - File loading

    func loadFile(url: URL) async {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        do {
            sourceURL = url
            try await loadOFX(url: url)
        } catch let error as ImportError {
            phase = .failed(message: error.localizedDescription)
            ErrorCenter.shared.report(error)
        } catch {
            phase = .failed(message: error.localizedDescription)
            ErrorCenter.shared.report(error)
        }
    }

    /// Reporta uma falha originada **fora** do `loadFile` — tipicamente um
    /// erro do `fileImporter` da SwiftUI (permissão negada, sandbox, etc.).
    /// Sem isso a UI ficava silenciosa quando o picker do sistema falhava.
    func reportFileImportFailure(_ error: Error) {
        ErrorCenter.shared.report(error, title: "Erro ao abrir arquivo")
        phase = .failed(message: error.localizedDescription)
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
            let isDuplicate = existingExternalIds.contains(trn.fitid)
            let derived = DerivedTransaction(
                occurredAt: trn.datePosted,
                amount: trn.amount,
                description: trn.displayDescription,
                notes: trn.memo
            )
            // Defaults sensatos: válidas selecionadas, duplicadas desligadas.
            // Usuário re-marca duplicadas explicitamente caso queira re-importar.
            rows.append(OFXPreviewRow(
                raw: trn,
                derived: derived,
                isDuplicate: isDuplicate,
                categoryId: heuristic.categoryId(for: trn),
                subcategoryId: nil,
                selected: !isDuplicate
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

    func cancel() {
        categorizationWaitTask?.cancel()
        categorizationWaitTask = nil
        categorization.cancel()
        clearPendingState()
        phase = .idle
        sourceURL = nil
        ofxDocument = nil
        ofxResolutions = []
    }

    // MARK: - Confirm OFX (multi-account) → drafts → categorização

    /// Confirma o preview OFX. **Não insere no banco** — monta institutions
    /// novas, accounts novas e drafts (com `signedAmount` original do OFX).
    /// Dispara categorização pré-commit. Commit acontece em `finalizeImport()`.
    func confirmOFXImport() async {
        guard phase == .ofxReview else { return }

        // Consistência de institutions (mesmo code → mesmo name/kind).
        let grouped = Dictionary(grouping: ofxResolutions, by: { $0.institution.code })
        for (code, group) in grouped where group.count > 1 {
            let names = Set(group.map { $0.institution.name })
            let kinds = Set(group.map { $0.institution.kind })
            if names.count > 1 || kinds.count > 1 {
                phase = .failed(message: "Múltiplas contas usam o código \(code) mas com nome ou tipo divergente. Edite todas pra ficarem iguais antes de confirmar.")
                return
            }
        }

        let now = Date()

        var institutionsToInsert: [Institution] = []
        var resolvedInstitutionIds: [String: UUID] = [:]
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
        var batchesWithDrafts: [(batch: ImportBatch, draftIds: [UUID])] = []
        var allDrafts: [TransactionDraft] = []

        for resolution in ofxResolutions {
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
                accountId: accountId,
                rowCount: toImport.count,
                importedAt: now,
                createdAt: now,
                updatedAt: now
            )

            let drafts: [TransactionDraft] = toImport.map { row in
                TransactionDraft(
                    id: UUID(),
                    accountId: accountId,
                    importBatchId: batchId,
                    signedAmount: row.derived.amount,   // **mantém o sinal do OFX** pra IA
                    occurredAt: row.derived.occurredAt,
                    description: row.derived.description,
                    notes: row.derived.notes,
                    externalId: row.raw.fitid
                )
            }
            allDrafts.append(contentsOf: drafts)
            batchesWithDrafts.append((batch, drafts.map(\.id)))
        }

        if allDrafts.isEmpty {
            phase = .failed(message: ImportError.noValidRows.localizedDescription)
            return
        }

        pendingDrafts = allDrafts
        pendingInstitutionsToInsert = institutionsToInsert
        pendingAccountsToInsert = accountsToInsert
        pendingBatchesWithDrafts = batchesWithDrafts

        startCategorization()
    }

    // MARK: - Finalize (commit atômico)

    /// Commit final do import: usa a categoria escolhida (auto-aprovada ou
    /// corrigida pelo usuário) pra cada draft, monta as `Transaction`s
    /// definitivas com `abs(amount)` e dispara o `commitImport` atômico no
    /// `TransactionRepository`.
    ///
    /// Inclui institutions novas, accounts novas, batches, transactions, cache
    /// entries (resultado da IA) e corrections (do que o usuário corrigiu).
    /// Atomicidade total: se qualquer execute falha, banco fica intocado.
    func finalizeImport() async {
        guard phase == .reviewingCategorization else { return }

        if pendingDrafts.isEmpty {
            phase = .failed(message: ImportError.noValidRows.localizedDescription)
            return
        }

        phase = .confirming

        do {
            let now = Date()

            // Resolve `fallbackId` pra drafts cuja categoria suggerida não foi
            // encontrada (paranoia — não deve acontecer).
            let fallback = try await database.categories.findRootByName("Não Classificado")
            guard let fallbackId = fallback?.id else {
                throw ImportError.unclassifiedCategoryMissing
            }

            // Monta transactions por batch usando a categoria atual da sugestão.
            var batchesWithTransactions: [(batch: ImportBatch, transactions: [Transaction])] = []
            for (batch, draftIds) in pendingBatchesWithDrafts {
                let draftsForBatch = pendingDrafts.filter { draftIds.contains($0.id) }
                let txs: [Transaction] = draftsForBatch.map { draft in
                    let resolved = categorization.resolvedCategory(forTransactionId: draft.id)
                    return Transaction(
                        id: draft.id,
                        accountId: draft.accountId,
                        categoryId: resolved?.categoryId ?? fallbackId,
                        subcategoryId: resolved?.subcategoryId,
                        amount: abs(draft.signedAmount),
                        occurredAt: draft.occurredAt,
                        description: draft.description,
                        notes: draft.notes,
                        importBatchId: batch.id,
                        externalId: draft.externalId,
                        createdAt: now,
                        updatedAt: now
                    )
                }
                batchesWithTransactions.append((batch, txs))
            }

            let corrections = categorization.buildPendingCorrections()
            let cacheEntries = categorization.pendingCacheEntries

            do {
                try await database.transactions.commitImport(
                    institutions: pendingInstitutionsToInsert,
                    accounts: pendingAccountsToInsert,
                    batchesWithTransactions: batchesWithTransactions,
                    cacheEntries: cacheEntries,
                    corrections: corrections
                )
            } catch {
                throw ImportError.batchInsertFailed(underlying: error)
            }

            // Atualiza caches locais pós-commit.
            accounts = try await database.accounts.getAll()
            institutions = try await database.institutions.getAll()
            await refreshBatches()

            let totalRows = batchesWithTransactions.reduce(0) { $0 + $1.transactions.count }
            let batchIds = batchesWithTransactions.map { $0.batch.id }

            // Limpa estado em voo agora que tudo foi commitado.
            clearPendingState()

            phase = .done(batchIds: batchIds, rowCount: totalRows)
        } catch let error as ImportError {
            phase = .failed(message: error.localizedDescription)
            ErrorCenter.shared.report(error)
        } catch {
            phase = .failed(message: error.localizedDescription)
            ErrorCenter.shared.report(error)
        }
    }

    /// Volta da revisão pra OFX review — usado pelo botão "Voltar" da
    /// tela de revisão pra ajustar o que vai ser importado antes de finalizar.
    /// Descarta sugestões em memória (próximo confirm refaz a categorização).
    func backToPreviewFromReview() {
        guard phase == .reviewingCategorization || phase == .categorizing else { return }
        categorizationWaitTask?.cancel()
        categorizationWaitTask = nil
        categorization.cancel()
        clearPendingState()
        phase = .ofxReview
    }

    private func clearPendingState() {
        pendingDrafts = []
        pendingInstitutionsToInsert = []
        pendingAccountsToInsert = []
        pendingBatchesWithDrafts = []
    }

    // MARK: - Undo

    func undo(batchId: UUID) async {
        do {
            try await database.importBatches.delete(id: batchId)
            await refreshBatches()
        } catch {
            ErrorCenter.shared.report(error, title: "Falha ao desfazer importação")
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
        rows.filter { !$0.isDuplicate }.count
    }
    var duplicateRowCount: Int {
        rows.filter(\.isDuplicate).count
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
    /// FITID já bate com uma transaction existente da mesma conta. OFX só tem
    /// dois estados de preview hoje: "válida" e "duplicada" — não há `invalid*`
    /// porque o parser OFX já rejeita estruturalmente o que não dá pra
    /// transformar em transação.
    var isDuplicate: Bool
    /// ID da categoria raiz vindo da heurística. Resolvido no `ImportStore`,
    /// não na View, pra evitar passar `database` adiante. Pode ser editado
    /// pelo usuário no preview.
    var categoryId: UUID
    /// Subcategoria opcional. NULL no momento da geração; usuário pode
    /// selecionar uma sub durante o review.
    var subcategoryId: UUID?
    /// Marca por linha: válida → ligada por default; duplicada → desligada
    /// (usuário re-marca pra re-importar).
    var selected: Bool
}
