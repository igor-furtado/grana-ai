import Foundation

/// Correção explícita do usuário sobre uma sugestão de categorização da IA.
/// Histórico mantido completo para auditoria. Uma correção substitui apenas a
/// entrada contextual correspondente no cache.
struct CategorizationCorrection: Identifiable, Hashable {
    let id: UUID
    var descriptionHash: String
    var normalizedDescription: String
    /// Categoria que a IA sugeriu (nullable: quando o usuário corrige uma
    /// transação que ainda estava em "Não Classificado", não há sugestão).
    var originalCategoryId: UUID?
    var originalSubcategoryId: UUID?
    var correctedCategoryId: UUID
    var correctedSubcategoryId: UUID?
    var transactionId: UUID
    let createdAt: Date
}
