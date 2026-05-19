import Foundation

/// Sugestão da IA pra uma transação específica, materializada em memória pro
/// fluxo de revisão. Não persiste — usada apenas durante o wizard de import
/// (Fase 4) ou na recategorização opt-in (Settings).
///
/// `source` distingue:
/// - `.cache` — descrição já vista antes; não consultou IA (latência zero).
/// - `.ai` — chamada Claude desta sessão.
/// - `.fallback` — IA falhou, confidence < threshold absoluto, ou slug
///   desconhecido; transação cai em "Não Classificado".
///
/// **`originalCategoryId` preserva a sugestão original.** Quando o usuário
/// corrige (muta `categoryId`/`subcategoryId`), o original fica gravado pra
/// que no commit final geremos uma `CategorizationCorrection` com o trail
/// "antes/depois" pra few-shots.
struct CategorizationSuggestion: Identifiable, Hashable {
    enum Source: String, Hashable {
        case cache
        case ai
        case fallback
    }

    let id: UUID
    let transactionId: UUID
    /// Hash SHA256 da descrição normalizada — chave do cache, propagação de
    /// correções entre sugestões com mesma descrição.
    let descriptionHash: String

    var categoryId: UUID
    var subcategoryId: UUID?
    var confidence: Double
    let source: Source

    /// Categoria que a IA/cache sugeriu antes de qualquer correção do usuário.
    /// `nil` quando `source == .fallback` (não há "sugestão original" real).
    let originalCategoryId: UUID?
    let originalSubcategoryId: UUID?

    /// Snapshot do draft pra renderizar a row sem precisar voltar no `ImportStore`.
    var transactionDescription: String
    var transactionAmount: Decimal     // magnitude (`abs`) — UI renderiza assim
    var transactionOccurredAt: Date
    var transactionAccountId: UUID
    /// Marca de revisão. Quando o usuário aceita explicitamente (botão de
    /// confirm), vira true. Correção também marca como reviewed automaticamente.
    var isReviewed: Bool

    /// True se o usuário corrigiu a categoria — ou seja, o estado atual difere
    /// da sugestão original. Usado pra decidir se gera `CategorizationCorrection`
    /// no commit.
    var wasCorrected: Bool {
        guard let originalCategoryId else { return true }   // fallback corrigido = sempre correção
        return categoryId != originalCategoryId || subcategoryId != originalSubcategoryId
    }

    enum ConfidenceBucket {
        case high
        case medium
        case low

        var displayName: String {
            switch self {
            case .high:   "Alta"
            case .medium: "Média"
            case .low:    "Baixa"
            }
        }
    }

    func bucket(
        autoApproved: Double,
        reviewRequired: Double
    ) -> ConfidenceBucket {
        if confidence >= autoApproved { return .high }
        if confidence >= reviewRequired { return .medium }
        return .low
    }
}
