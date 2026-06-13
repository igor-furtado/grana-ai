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
/// Todos os valores são projeções denormalizadas e reconstruíveis a partir
/// das transações, configurações de ciclo, pagamentos e créditos.
struct Statement: Identifiable, Codable, Hashable {
    let id: UUID
    let accountId: UUID
    let closingDate: Date
    let dueDate: Date
    /// Compras menos estornos do próprio ciclo. Pode ser negativo.
    var netAmount: Decimal
    /// Saldo credor trazido de faturas anteriores.
    var creditReceived: Decimal
    /// Soma das transferências aplicadas à fatura.
    var paymentApplied: Decimal
    /// Data efetiva em que uma fatura fechada ficou integralmente coberta.
    var settledAt: Date?
    let createdAt: Date
    var updatedAt: Date

    var totalAmount: Decimal {
        max(0, netAmount - creditReceived)
    }

    var creditBalance: Decimal {
        max(0, creditReceived + paymentApplied - netAmount)
    }

    var remainingAmount: Decimal {
        max(0, totalAmount - paymentApplied)
    }

    func status(referenceDate: Date = Date(), calendar: Calendar = .current) -> StatementStatus {
        guard calendar.startOfDay(for: referenceDate) > calendar.startOfDay(for: closingDate) else {
            return .forming
        }
        guard remainingAmount == 0, totalAmount > 0 else {
            return .closed
        }
        return creditReceived == 0 && creditBalance == 0 ? .paid : .settled
    }
}

enum StatementStatus: String, Codable, Hashable {
    case forming
    case closed
    case paid
    case settled

    var displayName: String {
        switch self {
        case .forming: "Em formação"
        case .closed: "Fechada"
        case .paid: "Paga"
        case .settled: "Quitada"
        }
    }
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

/// Parcela de saldo credor produzida por uma fatura fechada e consumida por
/// uma fatura posterior do mesmo cartão.
struct StatementCreditApplication: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceStatementId: UUID
    let destinationStatementId: UUID
    let appliedAmount: Decimal
    let createdAt: Date
}
