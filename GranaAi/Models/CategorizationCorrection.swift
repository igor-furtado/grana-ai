import Foundation

/// Correção explícita do usuário sobre uma sugestão de categorização da IA.
/// Cada correção vira exemplo few-shot do prompt das próximas chamadas
/// (`ORDER BY created_at DESC LIMIT N`), fechando o ciclo de aprendizado
/// sem precisar de fine-tuning.
///
/// Histórico mantido completo (não-destrutivo) — uma correção nova substitui
/// o cache mas não apaga a anterior, pra preservar o trail de auditoria.
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
