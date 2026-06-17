import Foundation

/// Entrada do cache de categorização. Chave de lookup é `descriptionHash`
/// (SHA256 hex da descrição normalizada). Hit = O(1), evita uma chamada à
/// Codex CLI para contextos idênticos.
///
/// `model` é guardado pra invalidar quando trocarmos a configuração — o
/// service filtra por `model = Config.anthropicCategorizationModel`, então
/// entradas geradas por um modelo antigo simplesmente não dão hit.
struct CategorizationCacheEntry: Identifiable, Hashable {
    let id: UUID
    var descriptionHash: String
    var normalizedDescription: String
    var categoryId: UUID
    var subcategoryId: UUID?
    var confidence: Double
    var model: String
    let createdAt: Date
    var updatedAt: Date
}
