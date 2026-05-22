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
    /// Categoria fornecida pelo sistema de origem (ex: coluna "Categoria"
    /// do CSV do Inter: SUPERMERCADO, TRANSPORTE, BARES…). **Não é nossa
    /// taxonomia** — vai pra IA só como hint adicional pra reduzir incerteza.
    /// `nil` quando a fonte não fornece (OFX, planilhas genéricas).
    let sourceCategoryHint: String?

    init(
        id: UUID,
        accountId: UUID,
        importBatchId: UUID,
        signedAmount: Decimal,
        occurredAt: Date,
        description: String,
        notes: String?,
        externalId: String?,
        sourceCategoryHint: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.importBatchId = importBatchId
        self.signedAmount = signedAmount
        self.occurredAt = occurredAt
        self.description = description
        self.notes = notes
        self.externalId = externalId
        self.sourceCategoryHint = sourceCategoryHint
    }
}
