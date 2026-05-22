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
    var thresholds: CategorizationService.ConfidenceThresholds = .default

    private var currentTask: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    func loadCategories() async {
        do {
            categories = try await container.categories.getAll()
        } catch {
            ErrorCenter.shared.report(error)
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
                ErrorCenter.shared.report(error, title: "Falha ao categorizar")
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
                ErrorCenter.shared.report(error, title: "Falha ao categorizar")
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
                ErrorCenter.shared.report(error, title: "Falha ao confirmar sugestão")
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
                ErrorCenter.shared.report(error, title: "Falha ao aplicar correção")
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
            suggestions[idx].confidence = 1.0   // usuário confirmou; máxima confiança
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
        case .started(let total):
            status = .classifying(processed: 0, total: total, message: "Verificando cache…")
        case .cacheChecked(let hits, let misses):
            status = .classifying(
                processed: hits,
                total: hits + misses,
                message: misses > 0 ? "\(hits) via cache · enviando \(misses) pra IA…" : "Tudo via cache."
            )
        case .aiCallStarted(let misses):
            status = .classifying(processed: 0, total: misses, message: "Categorizando \(misses) com IA…")
        case .aiCallFinished:
            break
        case .finished(let total, let fromCache, let fromAI, let fallback):
            status = .ready(total: total, fromCache: fromCache, fromAI: fromAI, fallback: fallback)
        case .failed(let error):
            status = .failed(message: error.localizedDescription)
        }
    }
}
