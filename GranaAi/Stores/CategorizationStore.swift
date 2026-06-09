import Foundation
import Observation
import OSLog

/// Estado observável do fluxo de categorização.
///
/// **Dois modos:**
///
/// - **Pré-commit** (`classifyDrafts`): usado pelo wizard de import. As
///   sugestões existem só em memória; correções do usuário NÃO vão pro banco
///   até o `ImportStore.finalizeImport()` chamar a `writeTransaction` atômica.
///   `pendingCacheEntries` é entregue ao `ImportStore` no commit.
///
/// - **Pós-commit** (`recategorizeUnclassified`): usado pelo botão das
///   Settings. Aqui as transactions já existem no banco — confirmar/corrigir
///   atualiza o banco diretamente.
///
/// **Propagação de correções:** ao corrigir uma sugestão com hash X, todas as
/// outras sugestões na lista atual com mesmo hash recebem a mesma categoria
/// automaticamente. Bom UX em imports com 50× "iFood".
@MainActor
@Observable
final class CategorizationStore {
    enum Status: Equatable {
        case idle
        case classifying(processed: Int, total: Int, message: String)
        case ready(total: Int, fromCache: Int, fromAI: Int, fallback: Int)
        case failed(message: String)
    }

    /// Modo atual — controla o comportamento de `applyCorrection` e
    /// `confirm` (banco vs memória).
    enum Mode {
        case preCommit
        case postCommit
    }

    private let container: AppContainer

    private(set) var status: Status = .idle
    private(set) var suggestions: [CategorizationSuggestion] = []
    /// Entries de cache geradas pela IA, a serem commitadas atomicamente pelo
    /// `ImportStore`. Não usadas no modo pós-commit (lá o service persiste
    /// direto).
    private(set) var pendingCacheEntries: [CategorizationCacheEntry] = []
    private(set) var mode: Mode = .preCommit

    private(set) var categories: [Category] = []
    /// Snapshots de accounts/institutions pra resolver o logo do banco em
    /// cada row da revisão (`institutionKind(forAccountId:)`). Carregado uma
    /// vez no `loadCategories`; as rows não precisam refletir mutações live
    /// (durante a revisão da IA não se cadastra/edita conta).
    private(set) var accounts: [Account] = []
    private(set) var institutions: [Institution] = []
    var thresholds: CategorizationService.ConfidenceThresholds = .default

    private var currentTask: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    func loadCategories() async {
        do {
            async let cats = container.categories.getAll()
            async let accs = container.accounts.getAll()
            async let insts = container.institutions.getAll()
            categories = try await cats
            accounts = try await accs
            institutions = try await insts
        } catch {
            NoticeCenter.shared.report(error)
        }
    }

    var rootCategories: [Category] {
        categories.filter { $0.parentId == nil }
    }

    func subcategories(of parentId: UUID) -> [Category] {
        categories.filter { $0.parentId == parentId }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    /// Logo do banco da row na tela de revisão. Resolve via
    /// `account.institutionId → institution.kind`. Devolve `nil` se a conta
    /// não tem instituição mapeada (ex: `.other`) — caller esconde o slot.
    func institutionKind(forAccountId accountId: UUID) -> InstitutionKind? {
        guard let account = accounts.first(where: { $0.id == accountId }),
              let institutionId = account.institutionId,
              let institution = institutions.first(where: { $0.id == institutionId })
        else { return nil }
        return institution.kind
    }

    // MARK: - Pré-commit (wizard de import)

    /// Classifica drafts em background. Resultado popula `suggestions` e
    /// `pendingCacheEntries`. Não toca banco.
    func classifyDrafts(_ drafts: [TransactionDraft]) {
        cancel()
        mode = .preCommit
        status = .classifying(processed: 0, total: drafts.count, message: "Categorizando…")
        suggestions = []
        pendingCacheEntries = []

        let service = container.categorization
        let thresholds = self.thresholds
        currentTask = Task { [weak self] in
            do {
                let result = try await service.classifyDrafts(
                    drafts,
                    thresholds: thresholds,
                    progress: { progress in
                        Task { @MainActor in
                            self?.handle(progress: progress)
                        }
                    }
                )
                self?.suggestions = result.suggestions
                self?.pendingCacheEntries = result.pendingCacheEntries
            } catch is CancellationError {
                // Cancelado pelo usuário ou pelo fluxo — sinaliza `.idle` pra
                // que quem está observando o status (ImportStore) possa sair
                // do polling sem ficar preso em `.classifying`.
                self?.status = .idle
            } catch {
                self?.status = .failed(message: error.localizedDescription)
                NoticeCenter.shared.report(error, title: "Falha ao categorizar")
            }
        }
    }

    // MARK: - Pós-commit (Settings)

    func recategorizeUnclassified() {
        cancel()
        mode = .postCommit
        status = .classifying(processed: 0, total: 0, message: "Categorizando…")
        suggestions = []
        pendingCacheEntries = []

        let service = container.categorization
        let thresholds = self.thresholds
        currentTask = Task { [weak self] in
            do {
                let result = try await service.recategorizeUnclassified(
                    thresholds: thresholds,
                    progress: { progress in
                        Task { @MainActor in
                            self?.handle(progress: progress)
                        }
                    }
                )
                self?.suggestions = result
            } catch is CancellationError {
                self?.status = .idle
            } catch {
                self?.status = .failed(message: error.localizedDescription)
                NoticeCenter.shared.report(error, title: "Falha ao categorizar")
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Aguarda a conclusão da classificação corrente. Retorna imediatamente
    /// se não houver nenhuma em andamento. Usado pelo `ImportStore` pra
    /// avançar de fase sem polling do `status`.
    func waitForCompletion() async {
        await currentTask?.value
    }

    // MARK: - Ações do usuário (UI)

    /// Confirma uma sugestão (aceita como está). No modo pré-commit só marca
    /// `isReviewed`; no pós-commit atualiza a transaction no banco.
    func confirm(at index: Int) async {
        guard suggestions.indices.contains(index) else { return }
        switch mode {
        case .preCommit:
            suggestions[index].isReviewed = true
        case .postCommit:
            let suggestion = suggestions[index]
            do {
                try await container.categorization.confirmExistingSuggestion(suggestion)
                suggestions[index].isReviewed = true
            } catch {
                NoticeCenter.shared.report(error, title: "Falha ao confirmar sugestão")
            }
        }
    }

    func confirmAll() async {
        let pending = suggestions.indices.filter { !suggestions[$0].isReviewed }
        for index in pending {
            await confirm(at: index)
        }
    }

    /// Aplica correção. Em ambos os modos a propagação de mesma-hash acontece;
    /// no pós-commit a correção vai pro banco (insert correction + invalida
    /// cache + atualiza transaction). No pré-commit só muta a memória — quem
    /// commita é o `ImportStore.finalizeImport()`.
    func applyCorrection(
        at index: Int,
        correctedCategoryId: UUID,
        correctedSubcategoryId: UUID?
    ) async {
        guard suggestions.indices.contains(index) else { return }
        let hash = suggestions[index].descriptionHash

        switch mode {
        case .preCommit:
            propagateCorrectionInMemory(
                matchingHash: hash,
                categoryId: correctedCategoryId,
                subcategoryId: correctedSubcategoryId
            )
            // Atualiza o pendingCacheEntry pra esse hash — a correção vai
            // sobrescrever o que a IA propôs no momento do commit.
            updatePendingCacheForCorrection(
                hash: hash,
                categoryId: correctedCategoryId,
                subcategoryId: correctedSubcategoryId,
                normalizedDescription: DescriptionNormalizer.normalize(suggestions[index].transactionDescription)
            )
        case .postCommit:
            let suggestion = suggestions[index]
            do {
                try await container.categorization.applyCorrectionPostCommit(
                    suggestion: suggestion,
                    correctedCategoryId: correctedCategoryId,
                    correctedSubcategoryId: correctedSubcategoryId
                )
                propagateCorrectionInMemory(
                    matchingHash: hash,
                    categoryId: correctedCategoryId,
                    subcategoryId: correctedSubcategoryId
                )
            } catch {
                NoticeCenter.shared.report(error, title: "Falha ao aplicar correção")
            }
        }
    }

    private func propagateCorrectionInMemory(
        matchingHash hash: String,
        categoryId: UUID,
        subcategoryId: UUID?
    ) {
        for idx in suggestions.indices where suggestions[idx].descriptionHash == hash {
            suggestions[idx].categoryId = categoryId
            suggestions[idx].subcategoryId = subcategoryId
            suggestions[idx].confidence = 1.0 // usuário confirmou; máxima confiança
            suggestions[idx].isReviewed = true
        }
    }

    private func updatePendingCacheForCorrection(
        hash: String,
        categoryId: UUID,
        subcategoryId: UUID?,
        normalizedDescription: String
    ) {
        let now = Date()
        // Usa o mesmo model name do service pra que o cache lookup futuro
        // bata (chave composta é hash+model).
        let model = container.categorization.model

        // Remove entry da IA pra esse hash (se existir).
        pendingCacheEntries.removeAll { $0.descriptionHash == hash }

        // Adiciona uma nova com a correção do usuário (confidence 1.0).
        pendingCacheEntries.append(CategorizationCacheEntry(
            id: UUID(),
            descriptionHash: hash,
            normalizedDescription: normalizedDescription,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            confidence: 1.0,
            model: model,
            createdAt: now,
            updatedAt: now
        ))
    }

    // MARK: - Helpers de commit (consumidos pelo ImportStore)

    /// Constrói as `CategorizationCorrection` a serem persistidas no commit
    /// final. Uma por sugestão que diverge da original.
    func buildPendingCorrections() -> [CategorizationCorrection] {
        let now = Date()
        return suggestions
            .filter { $0.wasCorrected }
            .map { suggestion in
                let normalized = DescriptionNormalizer.normalize(suggestion.transactionDescription)
                return CategorizationCorrection(
                    id: UUID(),
                    descriptionHash: suggestion.descriptionHash,
                    normalizedDescription: normalized,
                    originalCategoryId: suggestion.originalCategoryId,
                    originalSubcategoryId: suggestion.originalSubcategoryId,
                    correctedCategoryId: suggestion.categoryId,
                    correctedSubcategoryId: suggestion.subcategoryId,
                    transactionId: suggestion.transactionId,
                    createdAt: now
                )
            }
    }

    /// Lookup: categoria/subcategoria que o usuário acabou de aceitar pra um
    /// dado `transactionId`. O `ImportStore` usa pra montar as `Transaction`s
    /// no commit final.
    func resolvedCategory(forTransactionId id: UUID) -> (categoryId: UUID, subcategoryId: UUID?)? {
        guard let s = suggestions.first(where: { $0.transactionId == id }) else { return nil }
        return (s.categoryId, s.subcategoryId)
    }

    // MARK: - Progress

    private func handle(progress: CategorizationService.Progress) {
        switch progress {
        case let .started(total):
            status = .classifying(processed: 0, total: total, message: "Verificando cache…")
        case let .cacheChecked(hits, misses):
            let total = hits + misses
            let message: String
            if misses == 0 {
                message = "Tudo via cache."
            } else {
                message = "\(hits) via cache · \(misses) na IA…"
            }
            status = .classifying(processed: hits, total: total, message: message)
        case let .aiCallStarted(misses):
            // O `aiChunkFinished` posterior vai trazer a contagem cumulativa
            // correta. Aqui só atualiza a mensagem pro usuário entender que
            // saiu do cache pra IA — `processed` e `total` ficam de fora pra
            // não zerar o que veio do `cacheChecked`.
            if case let .classifying(processed, total, _) = status {
                status = .classifying(
                    processed: processed,
                    total: total,
                    message: "Categorizando \(misses) com IA…"
                )
            } else {
                status = .classifying(processed: 0, total: misses, message: "Categorizando \(misses) com IA…")
            }
        case let .aiChunkFinished(processed, total):
            let remaining = max(0, total - processed)
            let message = remaining > 0
                ? "\(processed) de \(total) prontas · \(remaining) restantes…"
                : "Finalizando…"
            status = .classifying(processed: processed, total: total, message: message)
        case .aiCallFinished:
            break
        case let .finished(total, fromCache, fromAI, fallback):
            status = .ready(total: total, fromCache: fromCache, fromAI: fromAI, fallback: fallback)
        case let .failed(error):
            status = .failed(message: error.localizedDescription)
        }
    }
}
