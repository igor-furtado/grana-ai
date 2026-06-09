import Foundation
import OSLog

/// Pipeline de categorização automática (Fase 4).
///
/// **Dois modos de operação:**
///
/// 1. **Pré-commit** (`classifyDrafts`): usado pelo wizard de import. Recebe
///    drafts (transações ainda não persistidas), chama cache + IA, devolve
///    sugestões em memória. Nada vai pro banco aqui — quem commita é o
///    `ImportStore.finalizeImport()` em uma única `writeTransaction` atômica
///    junto com as transactions, batches, accounts etc.
///
/// 2. **Pós-commit** (`classifyExisting`): usado pelo botão "Recategorizar
///    transações antigas" das Settings. Transações já existem no banco;
///    aqui o service atualiza diretamente o `category_id` quando confidence
///    está acima do auto-approved threshold.
///
/// **Único batch.** Para um import inteiro, mandamos todas as transações que
/// deram cache miss numa só chamada ao Claude CLI. Se o CLI estourar tempo ou
/// truncar, aí dividimos — não antes.
///
/// **Off-main.** Marca `Sendable`; chamada de Tasks em background.
final class CategorizationService: Sendable {
    /// Tamanho máximo do batch enviado por chamada ao Claude CLI. Imports
    /// grandes (fatura de cartão com 100+ linhas, OFX anual) estouravam o
    /// timeout de 120s. 30 itens por chunk: rápido o suficiente e reduz a
    /// taxa de "modelo preguiçoso" (em batches maiores ele tende a pular
    /// índices, gerando fallback). Chunks rodam em paralelo — N chunks
    /// pequenos preferíveis a 1 chunk grande.
    private static let maxAIBatchSize = 30

    /// Thresholds usados pelo UI pra agrupar sugestões em alta/média/baixa.
    /// `absoluteMinimum` ainda é usado: AI retornando confidence abaixo dele
    /// cai como fallback (não pode poluir cache nem virar sugestão "real").
    struct ConfidenceThresholds: Hashable {
        var autoApproved: Double = 0.85
        var reviewRequired: Double = 0.70
        var absoluteMinimum: Double = 0.30

        nonisolated static let `default` = ConfidenceThresholds()
    }

    /// Resultado de `classifyDrafts`: sugestões pra apresentar ao usuário +
    /// entradas de cache a persistir no momento do commit final.
    ///
    /// Não persistimos cache durante o classify pra preservar atomicidade —
    /// se o usuário cancelar o import, nada deve sobrar no banco.
    struct DraftClassificationResult {
        let suggestions: [CategorizationSuggestion]
        /// Uma entrada por hash distinto que veio da IA com confidence ≥
        /// absoluteMinimum. Cache hits não geram nova entrada (já existem).
        let pendingCacheEntries: [CategorizationCacheEntry]
    }

    private let client: ClaudeCLIClient
    private let transactions: TransactionRepository
    private let categories: CategoryRepository
    private let accounts: AccountRepository
    private let institutions: InstitutionRepository
    private let cache: CategorizationCacheRepository
    private let corrections: CategorizationCorrectionRepository
    /// Nome do modelo usado pra lookup/escrita no cache. Exposto pra que o
    /// Store grave entries de correção com o mesmo identificador que o
    /// service usa pra buscar — divergência aqui causa cache miss silencioso.
    let model: String
    private let fewShotLimit: Int

    init(
        client: ClaudeCLIClient,
        transactions: TransactionRepository,
        categories: CategoryRepository,
        accounts: AccountRepository,
        institutions: InstitutionRepository,
        cache: CategorizationCacheRepository,
        corrections: CategorizationCorrectionRepository,
        model: String = Config.claudeCLIModel,
        fewShotLimit: Int = 30
    ) {
        self.client = client
        self.transactions = transactions
        self.categories = categories
        self.accounts = accounts
        self.institutions = institutions
        self.cache = cache
        self.corrections = corrections
        self.model = model
        self.fewShotLimit = fewShotLimit
    }

    typealias ProgressHandler = @Sendable (Progress) -> Void

    enum Progress {
        case started(total: Int)
        case cacheChecked(hits: Int, misses: Int)
        case aiCallStarted(misses: Int)
        /// Emitido depois de cada chunk paralelo da IA completar (sucesso
        /// OU fallback). `processed` é cumulativo: hits do cache + itens já
        /// resolvidos pela IA até agora. `total` é `drafts.count` (todos
        /// os itens do import).
        case aiChunkFinished(processed: Int, total: Int)
        case aiCallFinished
        case finished(total: Int, fromCache: Int, fromAI: Int, fallback: Int)
        case failed(error: Error)
    }

    // MARK: - Pré-commit (wizard de import)

    /// Classifica drafts (transações ainda não persistidas). Cache hit é O(1);
    /// misses entram numa única chamada à Claude API.
    ///
    /// Devolve sugestões + cache entries a persistir no commit final. Não
    /// toca banco aqui (exceto leitura).
    func classifyDrafts(
        _ drafts: [TransactionDraft],
        thresholds: ConfidenceThresholds = .default,
        progress: ProgressHandler? = nil
    ) async throws -> DraftClassificationResult {
        guard !drafts.isEmpty else {
            progress?(.finished(total: 0, fromCache: 0, fromAI: 0, fallback: 0))
            return DraftClassificationResult(suggestions: [], pendingCacheEntries: [])
        }

        async let allCategoriesTask = categories.getAll()
        async let allAccountsTask = accounts.getAll()
        async let allInstitutionsTask = institutions.getAll()
        async let allBankDetailsTask = accounts.getAllBankDetails()
        async let allCreditCardsTask = accounts.getAllCreditCardDetails()
        async let recentCorrectionsTask = corrections.recent(limit: fewShotLimit)
        let (allCategories, allAccounts, allInstitutions, allBankDetails, allCreditCards, fewShotCorrections) =
            try await (
                allCategoriesTask,
                allAccountsTask,
                allInstitutionsTask,
                allBankDetailsTask,
                allCreditCardsTask,
                recentCorrectionsTask
            )

        let institutionNamesById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: allInstitutions.map { ($0.id, $0.name) }
        )
        let ownAccounts: [CategorizationPrompt.OwnAccountInfo] = allAccounts
            .filter { !$0.archived }
            .map { account in
                CategorizationPrompt.OwnAccountInfo(
                    name: Account.displayName(
                        for: account,
                        institutions: allInstitutions,
                        bankAccounts: allBankDetails,
                        creditCards: allCreditCards
                    ),
                    typeDisplay: account.type.displayName,
                    institutionName: account.institutionId.flatMap { institutionNamesById[$0] }
                )
            }

        // Map por id pra popular `account_context` em cada item. Inclui contas
        // arquivadas — drafts em voo podem (teoricamente) apontar pra uma
        // conta recém-arquivada; melhor mostrar o contexto certo do que
        // "Desconhecida". `displayName(for:)` já carrega o tipo no formato curto
        // (ex: "Inter Cartão · ••••1234"), então não concatenamos o
        // `type.displayName` de novo — economiza tokens e evita ruído.
        let accountContextById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: allAccounts.map { acc in
                (acc.id, Account.displayName(
                    for: acc,
                    institutions: allInstitutions,
                    bankAccounts: allBankDetails,
                    creditCards: allCreditCards
                ))
            }
        )

        let taxonomy = Taxonomy(categories: allCategories)
        guard let fallbackId = taxonomy.fallbackCategoryId else {
            throw CategorizationError.categoryNotFound(slug: "nao-classificado")
        }

        progress?(.started(total: drafts.count))

        // Cache lookup batched.
        let hashByDraftId: [UUID: String] = Dictionary(uniqueKeysWithValues:
            drafts.map { ($0.id, DescriptionNormalizer.hash($0.description)) }
        )
        let uniqueHashes = Array(Set(hashByDraftId.values))
        let cacheHits = try await cache.lookupMany(descriptionHashes: uniqueHashes, model: model)

        var suggestions: [CategorizationSuggestion] = []
        var pendingForAI: [TransactionDraft] = []
        var fromCache = 0

        for draft in drafts {
            let hash = hashByDraftId[draft.id] ?? DescriptionNormalizer.hash(draft.description)
            if let hit = cacheHits[hash] {
                fromCache += 1
                suggestions.append(buildSuggestion(
                    draft: draft,
                    hash: hash,
                    categoryId: hit.categoryId,
                    subcategoryId: hit.subcategoryId,
                    confidence: hit.confidence,
                    source: .cache
                ))
            } else {
                pendingForAI.append(draft)
            }
        }
        progress?(.cacheChecked(hits: fromCache, misses: pendingForAI.count))

        var fromAI = 0
        var fromFallback = 0
        var pendingCacheEntries: [String: CategorizationCacheEntry] = [:]

        if !pendingForAI.isEmpty {
            progress?(.aiCallStarted(misses: pendingForAI.count))

            // **Chunking + paralelismo pra reduzir latência total.** Batches
            // grandes estouravam o timeout do CLI; chunks menores rodam em
            // paralelo via `withTaskGroup`. Pra 114 tx em 4 chunks de ~30:
            // sequencial ≈ 4×30s = 120s; paralelo ≈ max(30s) ≈ 30s.
            //
            // Fallback per-chunk: cada Task captura sua própria falha e
            // devolve `.failure(chunk)` — não derruba os outros chunks.
            let chunks = pendingForAI.chunked(into: Self.maxAIBatchSize)
            let fewShots = buildFewShots(corrections: fewShotCorrections, taxonomy: taxonomy)

            // Estrutura local pro retorno de cada Task — `Result` aqui não dá
            // porque a "falha" precisa carregar o chunk original pro fallback.
            // `chunkSize` é sempre o tamanho do chunk original — pra progresso
            // não travar se a IA devolver menos itens que o esperado.
            enum ChunkOutcome {
                case success(
                    chunkSize: Int,
                    suggestions: [CategorizationSuggestion],
                    cacheEntries: [CategorizationCacheEntry]
                )
                case failure(drafts: [TransactionDraft], error: Error)

                var chunkSize: Int {
                    switch self {
                    case let .success(size, _, _): size
                    case let .failure(drafts, _): drafts.count
                    }
                }
            }

            let totalItems = drafts.count
            // `fromCache` aqui já é a contagem final de hits — base inicial
            // da barra de progresso. Cada chunk soma seus `chunk.count`
            // itens em cima disso.
            let baseProcessed = fromCache

            let outcomes: [ChunkOutcome] = await withTaskGroup(of: ChunkOutcome.self) { group in
                for chunk in chunks {
                    let chunkSize = chunk.count
                    group.addTask { [self] in
                        do {
                            let (aiSuggestions, aiCacheEntries) = try await self.runSingleAICall(
                                drafts: chunk,
                                hashByDraftId: hashByDraftId,
                                taxonomy: taxonomy,
                                fallbackId: fallbackId,
                                ownAccounts: ownAccounts,
                                accountContextById: accountContextById,
                                fewShots: fewShots,
                                thresholds: thresholds
                            )
                            return .success(
                                chunkSize: chunkSize,
                                suggestions: aiSuggestions,
                                cacheEntries: aiCacheEntries
                            )
                        } catch {
                            return .failure(drafts: chunk, error: error)
                        }
                    }
                }

                var collected: [ChunkOutcome] = []
                var processedSoFar = baseProcessed
                for await outcome in group {
                    processedSoFar += outcome.chunkSize
                    progress?(.aiChunkFinished(processed: processedSoFar, total: totalItems))
                    collected.append(outcome)
                }
                return collected
            }

            // Agrega resultados de todos os chunks. Erros viram um único toast
            // (em vez de N toasts pra N chunks falhos) — `NoticeCenter` faz
            // dedup mas mesmo assim queremos ser explícitos.
            var failedCount = 0
            for outcome in outcomes {
                switch outcome {
                case let .success(_, aiSuggestions, aiCacheEntries):
                    for s in aiSuggestions {
                        switch s.source {
                        case .ai: fromAI += 1
                        case .fallback: fromFallback += 1
                        case .cache: break
                        }
                    }
                    suggestions.append(contentsOf: aiSuggestions)
                    for entry in aiCacheEntries {
                        pendingCacheEntries[entry.descriptionHash] = entry
                    }
                case let .failure(chunk, error):
                    failedCount += 1
                    // Loga o erro raw pra diagnóstico (não vira toast aqui;
                    // o toast resumido vem depois do laço).
                    log.ai
                        .error(
                            "Chunk de categorização falhou (\(chunk.count) drafts): \(error.localizedDescription, privacy: .public)"
                        )
                    for draft in chunk {
                        let hash = hashByDraftId[draft.id] ?? DescriptionNormalizer.hash(draft.description)
                        suggestions.append(buildSuggestion(
                            draft: draft,
                            hash: hash,
                            categoryId: fallbackId,
                            subcategoryId: nil,
                            confidence: 0.0,
                            source: .fallback
                        ))
                        fromFallback += 1
                    }
                }
            }
            if failedCount > 0 {
                let title = failedCount == 1
                    ? "IA indisponível em 1 lote — usando fallback"
                    : "IA indisponível em \(failedCount) lotes — usando fallback"
                // Toast sem `Error` tipado — a causa real (timeout, parse,
                // rede) já está em `log.ai.error` por chunk acima. Usar um
                // `AIError` específico aqui mentiria sobre a categoria do erro.
                let message = "\(failedCount) lote(s) caíram pro fallback. Veja o console pra detalhes."
                Task { @MainActor in
                    NoticeCenter.shared.report(title: title, message: message)
                }
            }
            progress?(.aiCallFinished)
        }

        progress?(.finished(
            total: drafts.count,
            fromCache: fromCache,
            fromAI: fromAI,
            fallback: fromFallback
        ))

        log.ai
            .info(
                "classifyDrafts total=\(drafts.count) cacheHits=\(fromCache) fromAI=\(fromAI) fallback=\(fromFallback)"
            )

        // Ordena por confidence ascendente — usuário revisa primeiro o que
        // mais precisa de atenção.
        let sortedSuggestions = suggestions.sorted { $0.confidence < $1.confidence }

        return DraftClassificationResult(
            suggestions: sortedSuggestions,
            pendingCacheEntries: Array(pendingCacheEntries.values)
        )
    }

    // MARK: - Pós-commit (Settings: recategorizar antigas)

    /// Re-classifica todas as transações que ainda estão em "Não Classificado"
    /// no banco. Diferente do `classifyDrafts`, este caminho persiste o cache
    /// imediatamente (não há "cancelar import" pra invalidar). A aplicação
    /// nas transactions é por confirmação explícita do usuário no modal de
    /// revisão — alinhado com o resto do app, onde mudança no banco só
    /// acontece depois de "Confirmar".
    func recategorizeUnclassified(
        thresholds: ConfidenceThresholds = .default,
        progress: ProgressHandler? = nil
    ) async throws -> [CategorizationSuggestion] {
        let allCats = try await categories.getAll()
        let taxonomy = Taxonomy(categories: allCats)
        guard let fallbackId = taxonomy.fallbackCategoryId else {
            throw CategorizationError.categoryNotFound(slug: "nao-classificado")
        }

        let all = try await transactions.getAll()
        let pending = all.filter { $0.categoryId == fallbackId }
        guard !pending.isEmpty else {
            progress?(.finished(total: 0, fromCache: 0, fromAI: 0, fallback: 0))
            return []
        }

        // Converte transactions existentes em drafts pra reusar `classifyDrafts`.
        // `signedAmount` aqui já é magnitude (foi `abs()`-eada no insert) —
        // a IA não tem o sinal original. Trade-off conhecido pro path de
        // recategorização pós-commit.
        let drafts = pending.map { tx in
            TransactionDraft(
                id: tx.id,
                accountId: tx.accountId,
                importBatchId: tx.importBatchId ?? UUID(), // batch real não é usado nesse caminho
                signedAmount: tx.amount,
                occurredAt: tx.occurredAt,
                description: tx.description,
                notes: tx.notes,
                externalId: tx.externalId
            )
        }

        let result = try await classifyDrafts(drafts, thresholds: thresholds, progress: progress)

        // Persiste cache entries (não há "cancelar import" nesse caminho — o
        // usuário disparou o opt-in explicitamente).
        try await cache.upsertMany(result.pendingCacheEntries)

        return result.suggestions
    }

    /// Aplica correção manual pós-commit (usuário corrige uma sugestão de
    /// `recategorizeUnclassified`). Insere correction + refresca cache +
    /// atualiza transaction em **uma única `writeTransaction`** — sem isso,
    /// falha entre os passos deixa correção apontando pra categoria que não
    /// está na transação nem no cache (envenenando os few-shots futuros).
    func applyCorrectionPostCommit(
        suggestion: CategorizationSuggestion,
        correctedCategoryId: UUID,
        correctedSubcategoryId: UUID?
    ) async throws {
        let normalized = DescriptionNormalizer.normalize(suggestion.transactionDescription)
        let hash = suggestion.descriptionHash
        let now = Date()

        let correction = CategorizationCorrection(
            id: UUID(),
            descriptionHash: hash,
            normalizedDescription: normalized,
            originalCategoryId: suggestion.originalCategoryId,
            originalSubcategoryId: suggestion.originalSubcategoryId,
            correctedCategoryId: correctedCategoryId,
            correctedSubcategoryId: correctedSubcategoryId,
            transactionId: suggestion.transactionId,
            createdAt: now
        )

        let cacheEntry = CategorizationCacheEntry(
            id: UUID(),
            descriptionHash: hash,
            normalizedDescription: normalized,
            categoryId: correctedCategoryId,
            subcategoryId: correctedSubcategoryId,
            confidence: 1.0,
            model: model,
            createdAt: now,
            updatedAt: now
        )

        try await transactions.applyPostCommitCorrection(
            correction: correction,
            cacheEntry: cacheEntry,
            transactionId: suggestion.transactionId,
            newCategoryId: correctedCategoryId,
            newSubcategoryId: correctedSubcategoryId,
            updatedAt: now
        )
    }

    /// Aplica auto-approved no banco — confirma sugestões com confidence ≥
    /// auto-approved nas transactions existentes. Usado apenas no path
    /// pós-commit.
    func confirmExistingSuggestion(_ suggestion: CategorizationSuggestion) async throws {
        try await updateTransactionCategory(
            transactionId: suggestion.transactionId,
            categoryId: suggestion.categoryId,
            subcategoryId: suggestion.subcategoryId
        )
    }

    // MARK: - Internos

    private func runSingleAICall(
        drafts: [TransactionDraft],
        hashByDraftId: [UUID: String],
        taxonomy: Taxonomy,
        fallbackId: UUID,
        ownAccounts: [CategorizationPrompt.OwnAccountInfo],
        accountContextById: [UUID: String],
        fewShots: [CategorizationPrompt.FewShotExample],
        thresholds: ConfidenceThresholds
    ) async throws -> ([CategorizationSuggestion], [CategorizationCacheEntry]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let items: [CategorizationPrompt.Item] = drafts.enumerated().map { idx, draft in
            // Trim do hint pra não passar string vazia ou só whitespace.
            // Vazio vira `nil` (= `null` no JSON), evitando ruído no prompt.
            let trimmed = draft.sourceCategoryHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint: String? = (trimmed?.isEmpty == false) ? trimmed : nil
            return CategorizationPrompt.Item(
                index: idx,
                description: DescriptionNormalizer.normalize(draft.description),
                signedAmount: NSDecimalNumber(decimal: draft.signedAmount).stringValue,
                date: dateFormatter.string(from: draft.occurredAt),
                accountContext: accountContextById[draft.accountId] ?? "Desconhecida",
                sourceHint: hint
            )
        }

        let invocation = try CategorizationPrompt.buildInvocation(
            items: items,
            categories: taxonomy.promptOptions(),
            ownAccounts: ownAccounts,
            fewShots: fewShots
        )
        let responseData = try await client.runStructured(
            systemPrompt: invocation.systemPrompt,
            userPrompt: invocation.userPrompt,
            jsonSchema: invocation.jsonSchema
        )
        let results = try CategorizationPrompt.parseResults(from: responseData)

        // Valida indices antes de aplicar — se a IA devolve duplicatas, o
        // dicionário abaixo sobrescreveria silenciosamente e dois drafts
        // diferentes receberiam a mesma categoria. Indices faltantes seguem
        // pro path de fallback no laço abaixo (comportamento aceitável).
        let returnedIndices = results.map(\.index)
        if Set(returnedIndices).count != returnedIndices.count {
            throw AIError.responseParse(
                "IA devolveu indices duplicados (\(returnedIndices.count) resultados pra \(drafts.count) drafts)"
            )
        }

        var byIndex: [Int: CategorizationPrompt.ClassificationResult] = [:]
        for r in results {
            byIndex[r.index] = r
        }

        // **Por que duas passadas:** dois drafts com mesma descrição normalizada
        // (mesmo hash) podem receber respostas diferentes da IA — cada item leva
        // seu próprio `signed_amount`/`date` no prompt, e a IA não é
        // determinística. Sem normalização, três rows de "iFood" apareceriam
        // com categorias diferentes na UI e o cache (uma entrada por hash)
        // gravaria a primeira que aparecesse — divergente do que o usuário vê.
        //
        // Solução: pass 1 elege o "winner" por hash (maior confidence ≥ mínimo,
        // slug válido); pass 2 monta as sugestões usando o winner pra todos os
        // drafts daquele hash, ou fallback quando nenhum draft do hash teve
        // resposta utilizável.
        struct HashWinner {
            let categoryId: UUID
            let subcategoryId: UUID?
            let confidence: Double
            let normalizedDescription: String
        }
        var bestByHash: [String: HashWinner] = [:]
        // Drafts com result válido mas confidence abaixo do mínimo absoluto.
        // Mantemos o número pra reportar na sugestão de fallback (telemetria);
        // não vira winner.
        var lowConfidenceByDraft: [UUID: Double] = [:]
        // Slugs desconhecidos viram um único toast por slug — N drafts com o
        // mesmo erro não geram N toasts.
        var reportedUnknownSlugs: Set<String> = []

        for (idx, draft) in drafts.enumerated() {
            guard let result = byIndex[idx] else { continue }
            let hash = hashByDraftId[draft.id] ?? DescriptionNormalizer.hash(draft.description)

            guard let resolvedCategoryId = taxonomy.uuid(forSlug: result.categorySlug) else {
                if reportedUnknownSlugs.insert(result.categorySlug).inserted {
                    NoticeCenter.capture(AIError.unknownCategorySlug(result.categorySlug))
                }
                continue
            }

            guard result.confidence >= thresholds.absoluteMinimum else {
                lowConfidenceByDraft[draft.id] = result.confidence
                continue
            }

            if let existing = bestByHash[hash], existing.confidence >= result.confidence {
                continue
            }

            let subcategoryId = result.subcategoryName.flatMap {
                taxonomy.subcategoryUUID(parentId: resolvedCategoryId, name: $0)
            }
            bestByHash[hash] = HashWinner(
                categoryId: resolvedCategoryId,
                subcategoryId: subcategoryId,
                confidence: result.confidence,
                normalizedDescription: DescriptionNormalizer.normalize(draft.description)
            )
        }

        let now = Date()
        var cacheByHash: [String: CategorizationCacheEntry] = [:]
        var suggestions: [CategorizationSuggestion] = []

        for draft in drafts {
            let hash = hashByDraftId[draft.id] ?? DescriptionNormalizer.hash(draft.description)

            if let winner = bestByHash[hash] {
                suggestions.append(buildSuggestion(
                    draft: draft,
                    hash: hash,
                    categoryId: winner.categoryId,
                    subcategoryId: winner.subcategoryId,
                    confidence: winner.confidence,
                    source: .ai
                ))
                if cacheByHash[hash] == nil {
                    cacheByHash[hash] = CategorizationCacheEntry(
                        id: UUID(),
                        descriptionHash: hash,
                        normalizedDescription: winner.normalizedDescription,
                        categoryId: winner.categoryId,
                        subcategoryId: winner.subcategoryId,
                        confidence: winner.confidence,
                        model: model,
                        createdAt: now,
                        updatedAt: now
                    )
                }
            } else {
                suggestions.append(buildSuggestion(
                    draft: draft,
                    hash: hash,
                    categoryId: fallbackId,
                    subcategoryId: nil,
                    confidence: lowConfidenceByDraft[draft.id] ?? 0.0,
                    source: .fallback
                ))
            }
        }

        return (suggestions, Array(cacheByHash.values))
    }

    private func buildSuggestion(
        draft: TransactionDraft,
        hash: String,
        categoryId: UUID,
        subcategoryId: UUID?,
        confidence: Double,
        source: CategorizationSuggestion.Source
    ) -> CategorizationSuggestion {
        // `originalCategoryId` é o categoryId atual exceto pra fallback (onde
        // não há "sugestão real" — `nil` sinaliza correção sempre necessária).
        let originalCategoryId: UUID? = source == .fallback ? nil : categoryId
        let originalSubcategoryId: UUID? = source == .fallback ? nil : subcategoryId

        return CategorizationSuggestion(
            id: UUID(),
            transactionId: draft.id,
            descriptionHash: hash,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            confidence: confidence,
            source: source,
            originalCategoryId: originalCategoryId,
            originalSubcategoryId: originalSubcategoryId,
            transactionDescription: draft.description,
            transactionAmount: abs(draft.signedAmount),
            transactionOccurredAt: draft.occurredAt,
            transactionAccountId: draft.accountId,
            isReviewed: false
        )
    }

    private func updateTransactionCategory(
        transactionId: UUID,
        categoryId: UUID,
        subcategoryId: UUID?
    ) async throws {
        guard let existing = try await transactions.getById(transactionId) else { return }
        var updated = existing
        updated.categoryId = categoryId
        updated.subcategoryId = subcategoryId
        updated.updatedAt = Date()
        try await transactions.update(updated)
    }

    private func buildFewShots(
        corrections: [CategorizationCorrection],
        taxonomy: Taxonomy
    ) -> [CategorizationPrompt.FewShotExample] {
        corrections.compactMap { correction in
            guard let slug = taxonomy.slug(forUUID: correction.correctedCategoryId) else {
                return nil
            }
            let subName = correction.correctedSubcategoryId
                .flatMap { taxonomy.subcategoryName(for: $0) }
            return CategorizationPrompt.FewShotExample(
                normalizedDescription: correction.normalizedDescription,
                correctedCategorySlug: slug,
                correctedSubcategoryName: subName
            )
        }
    }
}

// MARK: - Array chunking helper

private extension Array {
    /// Divide o array em sub-arrays de tamanho máximo `size`. O último chunk
    /// pode ser menor. Usado pra fatiar batches grandes da IA em pedaços que
    /// caibam no timeout do CLI.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Taxonomy helper

/// Estrutura de lookup compilada a partir das `categories` carregadas.
/// Mapeia slug ↔ UUID e nome de subcategoria → UUID dentro de cada raiz.
private struct Taxonomy {
    let fallbackCategoryId: UUID?

    private let slugToUUID: [String: UUID]
    private let uuidToSlug: [UUID: String]
    private let subcategoriesByParent: [UUID: [Category]]
    private let categoriesById: [UUID: Category]

    init(categories: [Category]) {
        var slugToUUID: [String: UUID] = [:]
        var uuidToSlug: [UUID: String] = [:]
        var subsByParent: [UUID: [Category]] = [:]
        var byId: [UUID: Category] = [:]

        for category in categories {
            byId[category.id] = category
            if let slug = category.slug {
                slugToUUID[slug] = category.id
                uuidToSlug[category.id] = slug
            }
            if let parentId = category.parentId {
                subsByParent[parentId, default: []].append(category)
            }
        }

        self.slugToUUID = slugToUUID
        self.uuidToSlug = uuidToSlug
        self.subcategoriesByParent = subsByParent
        self.categoriesById = byId
        self.fallbackCategoryId = slugToUUID["nao-classificado"]
    }

    func uuid(forSlug slug: String) -> UUID? {
        slugToUUID[slug]
    }

    func slug(forUUID id: UUID) -> String? {
        uuidToSlug[id]
    }

    func subcategoryUUID(parentId: UUID, name: String) -> UUID? {
        let needle = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        return subcategoriesByParent[parentId]?.first(where: {
            $0.name.folding(options: .diacriticInsensitive, locale: nil).lowercased() == needle
        })?.id
    }

    func subcategoryName(for id: UUID) -> String? {
        categoriesById[id]?.name
    }

    func promptOptions() -> [CategorizationPrompt.CategoryOption] {
        let roots = categoriesById.values
            .filter { $0.parentId == nil && $0.slug != nil }
            .sorted { $0.name < $1.name }

        return roots.map { root in
            let subs = (subcategoriesByParent[root.id] ?? [])
                .sorted { $0.name < $1.name }
                .map(\.name)
            return CategorizationPrompt.CategoryOption(
                slug: root.slug ?? "",
                name: root.name,
                kind: root.kind.rawValue,
                subcategories: subs
            )
        }
    }
}
