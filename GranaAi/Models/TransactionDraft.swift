import Foundation

/// Versão pré-banco de uma `Transaction` — usada entre o preview e o commit
/// final do import, enquanto a IA categoriza e o usuário revisa.
///
/// **Por que existe:** Fase 4 categoriza ANTES da inserção no banco. Pra isso
/// precisamos passar pra IA o `signedAmount` original (com sinal vindo do CSV/XLSX/OFX),
/// que a `Transaction` perde no `abs()` exigido pela convenção do app
/// (CLAUDE.md invariante 1). O draft preserva o sinal só enquanto necessário —
/// no commit final, `abs(signedAmount)` vira `Transaction.amount`.
///
/// **`id` já fixado**: gerado quando o draft é criado, propagado pra
/// `Transaction.id` no commit. Permite usar o mesmo UUID em
/// `CategorizationSuggestion.transactionId` durante a revisão.
struct TransactionDraft: Sendable, Identifiable, Hashable {
    let id: UUID
    let accountId: UUID
    let importBatchId: UUID
    /// Valor com sinal original (negativo = saída, positivo = entrada). Vai
    /// pra IA como contexto. No commit final é `abs()`-eado.
    let signedAmount: Decimal
    let occurredAt: Date
    let description: String
    let notes: String?
    /// FITID do OFX, quando existir. CSV/XLSX = nil.
    let externalId: String?
}
