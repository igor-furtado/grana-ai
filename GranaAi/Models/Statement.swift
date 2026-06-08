import Foundation

/// Fatura de cartão de crédito (ciclo de fechamento).
///
/// Criada **lazy** pelo `TransactionRepository`: quando uma transação em
/// conta-cartão entra, o resolver de janela calcula `(closingDate, dueDate)`
/// do ciclo que cobre `occurredAt`; se não há Statement com esse
/// `closingDate`, uma nova é criada antes do insert da transação.
///
/// **Imutabilidade de `closingDate`/`dueDate`:** o usuário pode editar
/// `statement_closing_day`/`payment_due_day` na `CreditCardDetails` depois,
/// mas Statements já criadas mantêm o snapshot original — senão mudaria
/// retroativamente a qual fatura uma compra antiga pertence.
///
/// **`paidAt` é cache denormalizado:** populado quando
/// `SUM(StatementPayment.appliedAmount) >= totalAmount`. Toda escrita em
/// `statement_payments` ou em `transactions` que afete `total_amount_cents`
/// recalcula este campo na mesma `writeTransaction`.
struct Statement: Identifiable, Codable, Hashable {
    let id: UUID
    let accountId: UUID
    let closingDate: Date
    let dueDate: Date
    /// Magnitude positiva (soma de `transactions.amount_cents` vinculadas).
    /// `Decimal` no Swift, `Int64` centavos no banco (ver §invariantes
    /// CLAUDE.md). Recalculado a cada insert/update/delete em transactions
    /// da conta-cartão.
    var totalAmount: Decimal
    /// `nil` quando ainda não foi totalmente paga. Quando preenchido,
    /// reflete o momento em que a soma dos payments cobriu o total.
    var paidAt: Date?
    /// Arquivo CSV/OFX que originou esta Fatura (quando criada via import).
    /// `nil` pra Statements criadas por transações manuais.
    var sourceFilename: String?
    let createdAt: Date
    var updatedAt: Date

    var isPaid: Bool { paidAt != nil }
}

/// Aplicação de uma transferência sobre uma Fatura. Modela o N:N — uma
/// transferência pode aplicar a 1+ Faturas (split), uma Fatura pode receber
/// 1+ transferências (adiantamento). Cada linha registra **quanto** desta
/// transferência foi aplicado a esta Fatura específica.
///
/// **Constraint não no schema** (PowerSync sem NOT NULL/CHECK): a soma dos
/// `appliedAmount` de payments com mesmo `transactionId` não deve exceder
/// `transactions.amount` daquela transferência. Validado no Repository.
struct StatementPayment: Identifiable, Codable, Hashable {
    let id: UUID
    let statementId: UUID
    let transactionId: UUID
    /// Valor da transferência aplicado a esta Fatura (magnitude positiva).
    var appliedAmount: Decimal
    let createdAt: Date
    var updatedAt: Date
}
