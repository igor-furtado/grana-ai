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
        /// Fase 4.5: preview de fatura de cartão importada via CSV (Inter).
        /// Diferente do OFX, não tem auto-detect — usuário escolhe a conta-cartão
        /// no próprio preview.
        case csvReview
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

    private let container: AppContainer

    private(set) var phase: Phase = .idle

    /// Fase 4: store de categorização compartilhado entre os steps do wizard.
    /// Disparado **antes** do commit ao banco — a tela de revisão é parte do
    /// fluxo, não um post-step. Cancelar o import descarta tudo (nenhuma
    /// transaction vai pro banco se o usuário não confirmar).
    let categorization: CategorizationStore

    // Fase 4: estado "em voo" entre o preview e o commit final. Construído
    // pelo `confirmOFXImport`; consumido pelo `finalizeImport`.
    //
    // Não há mais criação de Institution/Account no commit — a partir da
    // Fase 4.5 a importação **exige** uma conta existente escolhida pelo
    // usuário. Drafts ficam só pra transactions + batches. Privados porque
    // nenhum caller fora do store precisa ler — fluxo é confirm → categorize
    // → finalize, todo dentro deste arquivo.
    private var pendingDrafts: [TransactionDraft] = []
    private var pendingBatchesWithDrafts: [(batch: ImportBatch, draftIds: [UUID])] = []

    /// Contexto do arquivo aberto. Fica fora do `Phase` pra sobreviver às
    /// transições.
    private(set) var sourceURL: URL?

    /// Fluxo OFX.
    private(set) var ofxDocument: OFXDocument?
    var ofxResolutions: [OFXStatementResolution] = []

    /// Fluxo CSV de fatura de cartão (Inter). Diferente do OFX, é uma única
    /// resolução (uma fatura = uma conta-cartão).
    var csvResolution: CSVStatementResolution?

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

    init(container: AppContainer) {
        self.container = container
        self.categorization = CategorizationStore(container: container)
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
        case let .failed(message):
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
            accounts = try await container.accounts.getAll()
            institutions = try await container.institutions.getAll()
            categories = try await container.categories.getAll()
            batches = try await container.importBatches.getAll()
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
        do { batches = try await container.importBatches.getAll() }
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
            let ext = url.pathExtension.lowercased()
            if ext == "csv" {
                try await loadCSV(url: url)
            } else {
                try await loadOFX(url: url)
            }
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
    /// parseado. Tenta auto-detectar uma conta existente que bate com a
    /// identidade bancária (instituição+agência+número). Se não achar,
    /// `accountId` fica nil e o usuário precisa escolher uma conta existente
    /// no preview — **não criamos contas novas a partir do import** (MVP).
    private func resolveStatement(
        _ statement: OFXStatement,
        heuristic: OFXCategoryHeuristic
    ) async throws -> OFXStatementResolution {
        let matchedAccountId = try await autoDetectAccountId(for: statement)

        // **Batched dedup**: pra contas existentes, busca TODOS os FITIDs já
        // gravados de uma vez e converte pra Set. O check por linha vira O(1)
        // em memória em vez de uma query por linha — em extratos com 500+
        // transações isso é a diferença entre <1s e 30+s.
        let existingExternalIds: Set<String>
        if let matchedAccountId {
            existingExternalIds = (try? await container.transactions.externalIds(forAccount: matchedAccountId)) ?? []
        } else {
            existingExternalIds = []
        }

        let rows = buildOFXRows(
            for: statement,
            existingExternalIds: existingExternalIds,
            heuristic: heuristic
        )

        return OFXStatementResolution(
            statement: statement,
            accountId: matchedAccountId,
            wasAutoDetected: matchedAccountId != nil,
            ofxBankLabel: ofxBankLabel(for: statement),
            ofxAccountLabel: ofxAccountLabel(for: statement),
            rows: rows
        )
    }

    /// Constrói as `OFXPreviewRow` aplicando dedup contra um set já carregado.
    /// Extraído pra ser reusado no `setOFXAccount` quando o usuário troca a
    /// conta no picker — re-dedup roda sem refazer o parse inteiro.
    private func buildOFXRows(
        for statement: OFXStatement,
        existingExternalIds: Set<String>,
        heuristic: OFXCategoryHeuristic
    ) -> [OFXPreviewRow] {
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
        return rows
    }

    /// Procura uma conta existente que bata com o `<BANKACCTFROM>` do OFX via
    /// instituição (pelo `bankId` / FID) + agência + número. Retorna `nil` se
    /// qualquer parte não bater — usuário precisa escolher manualmente.
    private func autoDetectAccountId(for statement: OFXStatement) async throws -> UUID? {
        let code = statement.account.bankId
        guard let institution = try await container.institutions.findByCode(code) else {
            return nil
        }
        let existing = try await container.accounts.findByBankIdentity(
            institutionId: institution.id,
            branchId: statement.account.branchId,
            accountNumber: statement.account.accountId
        )
        return existing?.id
    }

    /// Label do banco vindo do OFX pra exibição no header da Section. Usa o
    /// `<FI><ORG>` quando disponível; cai pro `displayName` do `InstitutionKind`
    /// derivado do FID quando o cabeçalho `<FI>` está vazio (acontece em OFX
    /// legados).
    private func ofxBankLabel(for statement: OFXStatement) -> String {
        if let org = statement.institutionHeader.organization, !org.isEmpty {
            return org
        }
        return InstitutionKind.fromCode(statement.account.bankId).displayName
    }

    /// Label da conta vindo do OFX pra exibição. Formata `código · agência ·
    /// conta` compactamente — é o que o usuário precisa pra reconhecer "essa
    /// conta do extrato é qual das minhas".
    private func ofxAccountLabel(for statement: OFXStatement) -> String {
        var parts: [String] = [statement.account.accountId]
        if let branch = statement.account.branchId, !branch.isEmpty {
            parts.append("Ag \(branch)")
        }
        parts.append("cód. \(statement.account.bankId)")
        return parts.joined(separator: " · ")
    }

    /// Trocar a conta selecionada no preview OFX exige refazer o dedup contra
    /// o novo conjunto de external_ids — sem isso, o badge "Já importada"
    /// ficaria desatualizado.
    func setOFXAccount(statementIndex idx: Int, to accountId: UUID?) async {
        guard ofxResolutions.indices.contains(idx) else { return }
        var resolution = ofxResolutions[idx]
        resolution.accountId = accountId
        resolution.wasAutoDetected = false

        let existingExternalIds: Set<String>
        if let accountId {
            existingExternalIds = (try? await container.transactions.externalIds(forAccount: accountId)) ?? []
        } else {
            existingExternalIds = []
        }

        // Re-aplica dedup mantendo a categoria já resolvida pela heurística.
        // `selected` só é recalculado quando o flag `isDuplicate` muda — assim
        // qualquer decisão manual do usuário (desmarcar uma row não-duplicada
        // que ele não quer importar) é preservada ao trocar a conta.
        for rowIdx in resolution.rows.indices {
            let fitid = resolution.rows[rowIdx].raw.fitid
            let wasDup = resolution.rows[rowIdx].isDuplicate
            let isDup = existingExternalIds.contains(fitid)
            resolution.rows[rowIdx].isDuplicate = isDup
            if wasDup != isDup {
                resolution.rows[rowIdx].selected = !isDup
            }
        }
        ofxResolutions[idx] = resolution
    }

    /// Resolve as categorias raiz "Não Classificado", "Transferências" e
    /// "Renda e Pagamentos" pra alimentar a heurística. As duas últimas são
    /// opcionais (a heurística cai pra unclassified se faltarem).
    private func buildHeuristic() async throws -> OFXCategoryHeuristic {
        guard let unclassified = try await container.categories.findRootByName("Não Classificado") else {
            throw ImportError.unclassifiedCategoryMissing
        }
        let transfers = try await container.categories.findRootByName("Transferências")
        let income = try await container.categories.findRootByName("Renda e Pagamentos")
        return OFXCategoryHeuristic(roots: .init(
            unclassified: unclassified.id,
            transfers: transfers?.id,
            income: income?.id
        ))
    }

    // MARK: - CSV de fatura de cartão (Fase 4.5)

    /// Lê CSV de fatura de cartão (Inter) → monta uma única `CSVStatementResolution`
    /// com as linhas válidas. **Exige conta-cartão existente** — se o usuário
    /// não tem nenhuma cadastrada, falha com mensagem orientando a criar uma
    /// antes (MVP simplificado: import nunca cria contas). Pré-seleciona
    /// quando há uma única conta-cartão pra reduzir cliques.
    private func loadCSV(url: URL) async throws {
        phase = .loading(progress: "Lendo fatura…")
        let reader = InterCreditCardCSVReader()
        let statement = try reader.read(from: url)

        // Arquivadas ficam fora — o usuário tirou do dia-a-dia, importar pra
        // elas seria inesperado. Desarquivar é o passo explícito.
        let creditCardAccounts = accounts.filter { $0.type == .creditCard && !$0.archived }
        if creditCardAccounts.isEmpty {
            throw ImportError.noCreditCardAccount
        }
        let initialAccountId: UUID? = creditCardAccounts.count == 1
            ? creditCardAccounts.first?.id
            : nil

        let rows: [CSVPreviewRow] = statement.rows.map { raw in
            let externalId = InterCreditCardCSVReader.makeExternalId(
                date: raw.date,
                description: raw.description,
                amount: raw.amount,
                tipo: raw.tipo
            )
            return CSVPreviewRow(
                raw: raw,
                derived: DerivedTransaction(
                    occurredAt: raw.date,
                    amount: raw.amount,
                    description: raw.description,
                    notes: "\(raw.tipo) · \(raw.interCategory)"
                ),
                externalId: externalId,
                isDuplicate: false,
                selected: true
            )
        }

        var resolution = CSVStatementResolution(
            sourceFilename: url.lastPathComponent,
            accountId: initialAccountId,
            rows: rows,
            skippedNegativeCount: statement.skippedNegativeCount
        )

        if let accId = initialAccountId {
            resolution = await applyCSVDedup(resolution, accountId: accId)
        }

        csvResolution = resolution
        phase = .csvReview
    }

    /// Re-aplica dedup quando o usuário muda a conta-cartão no picker.
    /// Sem isso, o preview mostra "Já importada" baseado na conta anterior.
    func setCSVAccount(_ accountId: UUID?) async {
        guard var resolution = csvResolution else { return }
        resolution.accountId = accountId

        if let accId = accountId {
            resolution = await applyCSVDedup(resolution, accountId: accId)
        } else {
            // Sem conta selecionada → limpa flags de duplicata e deixa tudo
            // selecionado por default.
            for idx in resolution.rows.indices {
                resolution.rows[idx].isDuplicate = false
                resolution.rows[idx].selected = true
            }
        }
        csvResolution = resolution
    }

    private func applyCSVDedup(
        _ resolution: CSVStatementResolution,
        accountId: UUID
    ) async -> CSVStatementResolution {
        let existing: Set<String> = (try? await container.transactions.externalIds(forAccount: accountId)) ?? []
        var updated = resolution
        for idx in updated.rows.indices {
            let isDup = existing.contains(updated.rows[idx].externalId)
            updated.rows[idx].isDuplicate = isDup
            // Mesma regra do OFX: duplicada começa desligada (usuário re-marca
            // se quiser forçar re-import).
            updated.rows[idx].selected = !isDup
        }
        return updated
    }

    /// Confirma o preview CSV. Mesmo padrão do OFX: monta drafts em voo +
    /// dispara categorização pré-commit. **Exige conta-cartão selecionada** —
    /// MVP não cria conta no import.
    func confirmCSVImport() async {
        guard phase == .csvReview else { return }
        guard let resolution = csvResolution else { return }

        guard let accountId = resolution.accountId else {
            phase = .failed(message: ImportError.accountNotSelected.localizedDescription)
            return
        }

        let toImport = resolution.rows.filter { $0.selected }
        guard !toImport.isEmpty else {
            phase = .failed(message: ImportError.noValidRows.localizedDescription)
            return
        }

        let now = Date()
        let batchId = UUID()
        let batch = ImportBatch(
            id: batchId,
            sourceFilename: resolution.sourceFilename,
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
                // Compra na fatura é despesa (positivo no CSV após nosso filtro
                // de negativos). Passamos `signedAmount` positivo — a IA decide
                // pela descrição/contexto se é expense/income (deve ser expense
                // em ~100% dos casos pois estornos foram filtrados).
                signedAmount: row.raw.amount,
                occurredAt: row.derived.occurredAt,
                description: row.derived.description,
                notes: row.derived.notes,
                externalId: row.externalId,
                // Categoria do próprio Inter (SUPERMERCADO, TRANSPORTE, BARES…)
                // como hint pra IA. Não é nossa taxonomia, só contexto.
                sourceCategoryHint: row.raw.interCategory
            )
        }

        pendingDrafts = drafts
        pendingBatchesWithDrafts = [(batch, drafts.map(\.id))]

        startCategorization()
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
        csvResolution = nil
    }

    // MARK: - Confirm OFX (multi-account) → drafts → categorização

    /// Confirma o preview OFX. **Não cria conta nova** — toda statement precisa
    /// estar apontada pra uma conta existente do usuário (auto-detectada ou
    /// escolhida manualmente). Monta drafts (com `signedAmount` original do
    /// OFX) e dispara a categorização pré-commit. Commit acontece em
    /// `finalizeImport()`.
    func confirmOFXImport() async {
        guard phase == .ofxReview else { return }

        // Normaliza upfront pra (resolution, accountId) — uma única checagem
        // de obrigatoriedade, sem precisar reabrir o opcional dentro do loop.
        let resolved: [(resolution: OFXStatementResolution, accountId: UUID)] = ofxResolutions
            .compactMap { resolution in
                resolution.accountId.map { (resolution, $0) }
            }
        guard resolved.count == ofxResolutions.count else {
            phase = .failed(message: ImportError.accountNotSelected.localizedDescription)
            return
        }

        let now = Date()
        var batchesWithDrafts: [(batch: ImportBatch, draftIds: [UUID])] = []
        var allDrafts: [TransactionDraft] = []

        for (resolution, accountId) in resolved {
            let toImport = resolution.rows.filter { $0.selected }
            if toImport.isEmpty { continue }

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
                    signedAmount: row.derived.amount, // **mantém o sinal do OFX** pra IA
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
            let fallback = try await container.categories.findRootByName("Não Classificado")
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
                try await container.transactions.commitImport(
                    batchesWithTransactions: batchesWithTransactions,
                    cacheEntries: cacheEntries,
                    corrections: corrections
                )
            } catch {
                throw ImportError.batchInsertFailed(underlying: error)
            }

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

    /// Volta da revisão pro preview de origem (OFX ou CSV) — usado pelo botão
    /// "Voltar" da tela de revisão pra ajustar o que vai ser importado antes
    /// de finalizar. Descarta sugestões em memória (próximo confirm refaz a
    /// categorização). Detecta a origem pelo que está populado: csvResolution
    /// presente → CSV; senão → OFX.
    func backToPreviewFromReview() {
        guard phase == .reviewingCategorization || phase == .categorizing else { return }
        categorizationWaitTask?.cancel()
        categorizationWaitTask = nil
        categorization.cancel()
        clearPendingState()
        phase = csvResolution != nil ? .csvReview : .ofxReview
    }

    private func clearPendingState() {
        pendingDrafts = []
        pendingBatchesWithDrafts = []
    }

    // MARK: - Undo

    func undo(batchId: UUID) async {
        do {
            try await container.importBatches.delete(id: batchId)
            await refreshBatches()
        } catch {
            ErrorCenter.shared.report(error, title: "Falha ao desfazer importação")
        }
    }
}

// MARK: - OFX resolution data structures

/// Estado por `STMTRS`. A partir da Fase 4.5 o import **nunca cria contas** —
/// usuário aponta cada statement pra uma conta existente. `accountId` começa
/// preenchido se o auto-detect (instituição+agência+número) bater com uma
/// conta cadastrada; senão, fica `nil` até o usuário escolher no picker.
struct OFXStatementResolution: Identifiable, Equatable {
    let id = UUID()
    let statement: OFXStatement
    /// Conta de destino — `nil` bloqueia a confirmação até o usuário escolher.
    var accountId: UUID?
    /// `true` se o auto-detect encontrou a conta sozinho; `false` se o usuário
    /// escolheu manualmente ou ainda não escolheu. Usado pra badge na UI.
    var wasAutoDetected: Bool
    /// Banco como o OFX declara (`<FI><ORG>` ou fallback pelo FID). Exibido
    /// no header da Section pra orientar o usuário no picker.
    let ofxBankLabel: String
    /// Identidade da conta como o OFX declara (`accountId · Ag X · cód. Y`).
    let ofxAccountLabel: String
    var rows: [OFXPreviewRow]

    var validRowCount: Int {
        rows.filter { !$0.isDuplicate }.count
    }

    var duplicateRowCount: Int {
        rows.filter(\.isDuplicate).count
    }
}

// MARK: - CSV resolution data structures (Fase 4.5)

/// Estado do preview de fatura CSV (cartão de crédito). É um único batch por
/// arquivo (uma fatura = uma conta). `accountId` precisa estar definido pra
/// confirmar — pré-selecionado quando há uma única conta-cartão cadastrada,
/// senão o usuário escolhe no picker.
struct CSVStatementResolution: Equatable {
    let sourceFilename: String
    var accountId: UUID?
    var rows: [CSVPreviewRow]
    /// Quantas linhas com valor negativo (pagamentos da fatura anterior +
    /// estornos) foram puladas no parse. Reportado na UI pra o usuário
    /// saber que houve filtro.
    let skippedNegativeCount: Int

    var selectedCount: Int {
        rows.filter(\.selected).count
    }

    var duplicateCount: Int {
        rows.filter(\.isDuplicate).count
    }
}

struct CSVPreviewRow: Identifiable, Hashable {
    let id = UUID()
    let raw: InterCreditCardCSVReader.Row
    var derived: DerivedTransaction
    /// External ID sintético construído por `InterCreditCardCSVReader.makeExternalId`.
    /// Usado pra dedup contra `transactions.external_id` da conta selecionada.
    let externalId: String
    var isDuplicate: Bool
    var selected: Bool
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
