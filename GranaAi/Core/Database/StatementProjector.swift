import Foundation
import PowerSync

enum StatementProjectionError: LocalizedError {
    case missingCycleConfiguration
    case invalidRefund
    case refundBeforePurchase
    case refundExceedsPurchase
    case unappliedPayment

    var errorDescription: String? {
        switch self {
        case .missingCycleConfiguration:
            "O cartão não possui configuração de fechamento e vencimento."
        case .invalidRefund:
            "O estorno precisa apontar para uma compra válida do mesmo cartão."
        case .refundBeforePurchase:
            "A data do estorno não pode ser anterior à compra original."
        case .refundExceedsPurchase:
            "A soma dos estornos não pode superar o valor da compra original."
        case .unappliedPayment:
            "O pagamento precisa ser integralmente aplicado a dívidas existentes na data da transferência."
        }
    }
}

/// Reconstrói toda a projeção financeira de um cartão dentro da transação de
/// banco que alterou sua origem. As tabelas de fatura são materializações; as
/// fontes da verdade são transações e configurações de ciclo.
nonisolated enum StatementProjector {
    private struct Entry {
        let id: UUID
        let accountId: UUID
        let categoryId: UUID
        let subcategoryId: UUID?
        let destinationAccountId: UUID?
        let refundOfTransactionId: UUID?
        let amountCents: Int64
        let occurredAt: Date
        let kind: CategoryKind
    }

    private struct Cycle {
        let effectiveFrom: Date
        let closingDay: Int
        let dueDay: Int
    }

    private struct ExistingStatement {
        let id: UUID
        let closingDate: Date
        let createdAt: Date
    }

    private struct Work {
        let id: UUID
        let closingDate: Date
        let dueDate: Date
        let createdAt: Date
        var firstEntryDate: Date?
        var netCents: Int64 = 0
        var creditReceivedCents: Int64 = 0
        var paymentAppliedCents: Int64 = 0
        var coverageDate: Date?
        var settledAt: Date?
    }

    private struct PaymentAllocation {
        let statementId: UUID
        let transactionId: UUID
        let amountCents: Int64
        let occurredAt: Date
    }

    private struct CreditAllocation {
        let sourceStatementId: UUID
        let destinationStatementId: UUID
        let amountCents: Int64
        let occurredAt: Date
    }

    private enum EventKind {
        case cardEntry(Entry)
        case closing(statementIndex: Int)
        case payment(Entry)
    }

    private struct Event {
        let date: Date
        let priority: Int
        let tieBreaker: String
        let kind: EventKind
    }

    static func rebuild(
        accountId: UUID,
        in tx: any ConnectionContext,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let entries = try loadEntries(accountId: accountId, in: tx)
        let accountEntries = entries.filter { $0.accountId == accountId }
        try validateAndSynchronizeRefunds(accountEntries, in: tx)
        let synchronizedEntries = try loadEntries(accountId: accountId, in: tx)
        let synchronizedCardEntries = synchronizedEntries.filter {
            $0.accountId == accountId && $0.kind != .transfer
        }
        let synchronizedPayments = synchronizedEntries.filter {
            $0.destinationAccountId == accountId && $0.kind == .transfer
        }

        let cycles = try loadCycles(accountId: accountId, in: tx)
        guard !cycles.isEmpty || synchronizedCardEntries.isEmpty else {
            throw StatementProjectionError.missingCycleConfiguration
        }
        let existing = try loadExistingStatements(accountId: accountId, in: tx)
        let existingByClosing = Dictionary(uniqueKeysWithValues: existing.map {
            (Converters.dateToString($0.closingDate), $0)
        })

        var workByClosing: [String: Work] = [:]
        var statementIdByTransaction: [UUID: UUID] = [:]
        for entry in synchronizedCardEntries {
            let cycle = cycle(for: entry.occurredAt, from: cycles)
            let window = StatementWindow.resolve(
                closingDay: cycle.closingDay,
                paymentDueDay: cycle.dueDay,
                on: entry.occurredAt,
                calendar: calendar
            )
            let key = Converters.dateToString(window.closingDate)
            if workByClosing[key] == nil {
                let previous = existingByClosing[key]
                workByClosing[key] = Work(
                    id: previous?.id ?? UUID(),
                    closingDate: window.closingDate,
                    dueDate: window.dueDate,
                    createdAt: previous?.createdAt ?? referenceDate
                )
            }
            statementIdByTransaction[entry.id] = workByClosing[key]?.id
        }

        var works = workByClosing.values.sorted { $0.closingDate < $1.closingDate }
        let indexById = Dictionary(uniqueKeysWithValues: works.indices.map { (works[$0].id, $0) })
        var events: [Event] = []
        for entry in synchronizedCardEntries {
            guard let statementId = statementIdByTransaction[entry.id],
                  let index = indexById[statementId]
            else { continue }
            events.append(Event(
                date: entry.occurredAt,
                priority: 0,
                tieBreaker: entry.id.uuidString,
                kind: .cardEntry(entry)
            ))
            works[index].firstEntryDate = minDate(works[index].firstEntryDate, entry.occurredAt)
        }

        let today = calendar.startOfDay(for: referenceDate)
        for index in works.indices where today > calendar.startOfDay(for: works[index].closingDate) {
            let closeEventDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: works[index].closingDate)
            ) ?? works[index].closingDate
            events.append(Event(
                date: closeEventDate,
                priority: 1,
                tieBreaker: works[index].id.uuidString,
                kind: .closing(statementIndex: index)
            ))
        }
        for payment in synchronizedPayments {
            events.append(Event(
                date: payment.occurredAt,
                priority: 2,
                tieBreaker: payment.id.uuidString,
                kind: .payment(payment)
            ))
        }
        events.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.tieBreaker < $1.tieBreaker
        }

        var paymentAllocations: [PaymentAllocation] = []
        var creditAllocations: [CreditAllocation] = []
        for event in events {
            switch event.kind {
            case let .cardEntry(entry):
                guard let statementId = statementIdByTransaction[entry.id],
                      let index = indexById[statementId]
                else { continue }
                works[index].netCents += entry.refundOfTransactionId == nil
                    ? entry.amountCents
                    : -entry.amountCents
            case let .closing(sourceIndex):
                let excess = max(
                    0,
                    works[sourceIndex].creditReceivedCents
                        + works[sourceIndex].paymentAppliedCents
                        - works[sourceIndex].netCents
                )
                if excess > 0, sourceIndex + 1 < works.count {
                    let destinationIndex = sourceIndex + 1
                    works[destinationIndex].creditReceivedCents += excess
                    works[destinationIndex].coverageDate = maxDate(
                        works[destinationIndex].coverageDate,
                        event.date
                    )
                    creditAllocations.append(CreditAllocation(
                        sourceStatementId: works[sourceIndex].id,
                        destinationStatementId: works[destinationIndex].id,
                        amountCents: excess,
                        occurredAt: event.date
                    ))
                }
                updateSettlement(index: sourceIndex, at: event.date, works: &works)
            case let .payment(payment):
                var remaining = payment.amountCents
                for index in works.indices where remaining > 0 {
                    guard let firstEntryDate = works[index].firstEntryDate,
                          firstEntryDate <= payment.occurredAt
                    else { continue }
                    let debt = max(
                        0,
                        works[index].netCents
                            - works[index].creditReceivedCents
                            - works[index].paymentAppliedCents
                    )
                    guard debt > 0 else { continue }
                    let applied = min(debt, remaining)
                    works[index].paymentAppliedCents += applied
                    works[index].coverageDate = maxDate(
                        works[index].coverageDate,
                        payment.occurredAt
                    )
                    paymentAllocations.append(PaymentAllocation(
                        statementId: works[index].id,
                        transactionId: payment.id,
                        amountCents: applied,
                        occurredAt: payment.occurredAt
                    ))
                    remaining -= applied
                    updateSettlement(index: index, at: payment.occurredAt, works: &works)
                }
                guard remaining == 0 else {
                    throw StatementProjectionError.unappliedPayment
                }
            }
        }

        try persist(
            accountId: accountId,
            works: works,
            statementIdByTransaction: statementIdByTransaction,
            paymentAllocations: paymentAllocations,
            creditAllocations: creditAllocations,
            referenceDate: referenceDate,
            in: tx
        )
    }

    private static func loadEntries(
        accountId: UUID,
        in tx: any ConnectionContext
    ) throws -> [Entry] {
        try tx.getAll(
            sql: """
            SELECT t.id, t.account_id, t.category_id, t.subcategory_id,
                   t.destination_account_id, t.refund_of_transaction_id,
                   t.amount_cents, t.occurred_at, c.kind
            FROM transactions t
            JOIN categories c ON c.id = t.category_id
            WHERE t.account_id = ? OR t.destination_account_id = ?
            ORDER BY t.occurred_at ASC, t.id ASC
            """,
            parameters: [accountId.uuidString, accountId.uuidString],
            mapper: { cursor in
                let id = try uuid(cursor, "id")
                let sourceAccountId = try uuid(cursor, "account_id")
                let categoryId = try uuid(cursor, "category_id")
                let occurredAt = try date(cursor, "occurred_at")
                let kindRaw = try cursor.getString(name: "kind")
                guard let kind = CategoryKind(rawValue: kindRaw) else {
                    throw DatabaseError.invalidEnum(column: "kind", value: kindRaw)
                }
                return try Entry(
                    id: id,
                    accountId: sourceAccountId,
                    categoryId: categoryId,
                    subcategoryId: optionalUUID(cursor, "subcategory_id"),
                    destinationAccountId: optionalUUID(cursor, "destination_account_id"),
                    refundOfTransactionId: optionalUUID(cursor, "refund_of_transaction_id"),
                    amountCents: cursor.getInt64(name: "amount_cents"),
                    occurredAt: occurredAt,
                    kind: kind
                )
            }
        )
    }

    private static func validateAndSynchronizeRefunds(
        _ entries: [Entry],
        in tx: any ConnectionContext
    ) throws {
        let byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var refundedByPurchase: [UUID: Int64] = [:]
        for refund in entries where refund.refundOfTransactionId != nil {
            guard let purchaseId = refund.refundOfTransactionId,
                  let purchase = byId[purchaseId],
                  purchase.refundOfTransactionId == nil,
                  purchase.accountId == refund.accountId,
                  purchase.kind != .transfer
            else {
                throw StatementProjectionError.invalidRefund
            }
            guard refund.occurredAt >= purchase.occurredAt else {
                throw StatementProjectionError.refundBeforePurchase
            }
            let total = refundedByPurchase[purchaseId, default: 0] + refund.amountCents
            guard total <= purchase.amountCents else {
                throw StatementProjectionError.refundExceedsPurchase
            }
            refundedByPurchase[purchaseId] = total
            if refund.categoryId != purchase.categoryId
                || refund.subcategoryId != purchase.subcategoryId
            {
                try tx.execute(
                    sql: """
                    UPDATE transactions
                    SET category_id = ?, subcategory_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    parameters: [
                        purchase.categoryId.uuidString,
                        purchase.subcategoryId?.uuidString,
                        Converters.dateToString(Date()),
                        refund.id.uuidString,
                    ]
                )
            }
        }
    }

    private static func loadCycles(
        accountId: UUID,
        in tx: any ConnectionContext
    ) throws -> [Cycle] {
        let configured: [Cycle] = try tx.getAll(
            sql: """
            SELECT effective_from, statement_closing_day, payment_due_day
            FROM credit_card_cycle_configs
            WHERE account_id = ?
            ORDER BY effective_from ASC
            """,
            parameters: [accountId.uuidString],
            mapper: { cursor in
                try Cycle(
                    effectiveFrom: date(cursor, "effective_from"),
                    closingDay: Int(cursor.getInt64(name: "statement_closing_day")),
                    dueDay: Int(cursor.getInt64(name: "payment_due_day"))
                )
            }
        )
        if !configured.isEmpty { return configured }
        return try tx.getAll(
            sql: """
            SELECT statement_closing_day, payment_due_day
            FROM credit_cards WHERE account_id = ?
            """,
            parameters: [accountId.uuidString],
            mapper: { cursor in
                try Cycle(
                    effectiveFrom: .distantPast,
                    closingDay: Int(cursor.getInt64(name: "statement_closing_day")),
                    dueDay: Int(cursor.getInt64(name: "payment_due_day"))
                )
            }
        )
    }

    private static func loadExistingStatements(
        accountId: UUID,
        in tx: any ConnectionContext
    ) throws -> [ExistingStatement] {
        try tx.getAll(
            sql: """
            SELECT id, closing_date, created_at
            FROM statements WHERE account_id = ?
            """,
            parameters: [accountId.uuidString],
            mapper: { cursor in
                try ExistingStatement(
                    id: uuid(cursor, "id"),
                    closingDate: date(cursor, "closing_date"),
                    createdAt: date(cursor, "created_at")
                )
            }
        )
    }

    private static func persist(
        accountId: UUID,
        works: [Work],
        statementIdByTransaction: [UUID: UUID],
        paymentAllocations: [PaymentAllocation],
        creditAllocations: [CreditAllocation],
        referenceDate: Date,
        in tx: any ConnectionContext
    ) throws {
        let oldStatementIds: [String] = try tx.getAll(
            sql: "SELECT id FROM statements WHERE account_id = ?",
            parameters: [accountId.uuidString],
            mapper: { cursor in try cursor.getString(name: "id") }
        )
        for statementId in oldStatementIds {
            try tx.execute(
                sql: "DELETE FROM statement_payments WHERE statement_id = ?",
                parameters: [statementId]
            )
            try tx.execute(
                sql: """
                DELETE FROM statement_credit_applications
                WHERE source_statement_id = ? OR destination_statement_id = ?
                """,
                parameters: [statementId, statementId]
            )
        }
        try tx.execute(
            sql: "DELETE FROM statements WHERE account_id = ?",
            parameters: [accountId.uuidString]
        )
        try tx.execute(
            sql: "UPDATE transactions SET statement_id = NULL WHERE account_id = ?",
            parameters: [accountId.uuidString]
        )

        for work in works {
            try tx.execute(
                sql: """
                INSERT INTO statements
                    (id, account_id, closing_date, due_date, net_amount_cents,
                     credit_received_cents, payment_applied_cents, settled_at,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                parameters: [
                    work.id.uuidString,
                    accountId.uuidString,
                    Converters.dateToString(work.closingDate),
                    Converters.dateToString(work.dueDate),
                    work.netCents,
                    work.creditReceivedCents,
                    work.paymentAppliedCents,
                    work.settledAt.map(Converters.dateToString),
                    Converters.dateToString(work.createdAt),
                    Converters.dateToString(referenceDate),
                ]
            )
        }
        for (transactionId, statementId) in statementIdByTransaction {
            try tx.execute(
                sql: "UPDATE transactions SET statement_id = ? WHERE id = ?",
                parameters: [statementId.uuidString, transactionId.uuidString]
            )
        }
        for allocation in paymentAllocations {
            try tx.execute(
                sql: """
                INSERT INTO statement_payments
                    (id, statement_id, transaction_id, applied_amount_cents,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                parameters: [
                    UUID().uuidString,
                    allocation.statementId.uuidString,
                    allocation.transactionId.uuidString,
                    allocation.amountCents,
                    Converters.dateToString(allocation.occurredAt),
                    Converters.dateToString(referenceDate),
                ]
            )
        }
        for allocation in creditAllocations {
            try tx.execute(
                sql: """
                INSERT INTO statement_credit_applications
                    (id, source_statement_id, destination_statement_id,
                     applied_amount_cents, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                parameters: [
                    UUID().uuidString,
                    allocation.sourceStatementId.uuidString,
                    allocation.destinationStatementId.uuidString,
                    allocation.amountCents,
                    Converters.dateToString(allocation.occurredAt),
                ]
            )
        }
    }

    private static func updateSettlement(
        index: Int,
        at eventDate: Date,
        works: inout [Work]
    ) {
        let covered = works[index].netCents > 0
            && works[index].creditReceivedCents + works[index].paymentAppliedCents
            >= works[index].netCents
        guard covered, eventDate >= works[index].closingDate else { return }
        let coverageDate = works[index].coverageDate ?? eventDate
        works[index].settledAt = max(works[index].closingDate, coverageDate)
    }

    private static func cycle(for date: Date, from cycles: [Cycle]) -> Cycle {
        cycles.last(where: { $0.effectiveFrom <= date }) ?? cycles[0]
    }

    private static func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
        lhs.map { min($0, rhs) } ?? rhs
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        lhs.map { max($0, rhs) } ?? rhs
    }

    private static func uuid(_ cursor: SqlCursor, _ column: String) throws -> UUID {
        let raw = try cursor.getString(name: column)
        guard let value = UUID(uuidString: raw) else {
            throw DatabaseError.invalidUUID(column: column, value: raw)
        }
        return value
    }

    private static func optionalUUID(_ cursor: SqlCursor, _ column: String) throws -> UUID? {
        guard let raw = try cursor.getStringOptional(name: column) else { return nil }
        guard let value = UUID(uuidString: raw) else {
            throw DatabaseError.invalidUUID(column: column, value: raw)
        }
        return value
    }

    private static func date(_ cursor: SqlCursor, _ column: String) throws -> Date {
        let raw = try cursor.getString(name: column)
        guard let value = Converters.stringToDate(raw) else {
            throw DatabaseError.invalidDate(column: column, value: raw)
        }
        return value
    }
}
