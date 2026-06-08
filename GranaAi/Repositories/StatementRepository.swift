import Foundation
import PowerSync

/// Persistência de `Statement` (fatura) e `StatementPayment` (junction
/// transferência→fatura). Concentra também os recálculos denormalizados
/// (`total_amount_cents`, `paid_at`) que precisam rodar a cada escrita em
/// transactions de cartão ou em statement_payments.
///
/// **Por que os recálculos vivem aqui** (em vez de `TransactionRepository`):
/// mantém o conhecimento de Statement coeso. O `TransactionRepository`
/// invoca os métodos `recalculateTotal(for:tx:)` dentro do mesmo
/// `writeTransaction` que insere/edita a transação — atomicidade preservada.
final class StatementRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - Statements: read

    /// Busca Statement por `(accountId, closingDate)` — chave lógica do
    /// ciclo. Usada pelo resolver: se devolver nil, o caller cria um novo.
    func find(accountId: UUID, closingDate: Date) async throws -> Statement? {
        try await db.getOptional(
            sql: """
            SELECT * FROM statements
            WHERE account_id = ? AND closing_date = ?
            LIMIT 1
            """,
            parameters: [
                accountId.uuidString,
                Converters.dateToString(closingDate),
            ],
            mapper: Self.mapStatement
        )
    }

    func get(id: UUID) async throws -> Statement? {
        try await db.getOptional(
            sql: "SELECT * FROM statements WHERE id = ? LIMIT 1",
            parameters: [id.uuidString],
            mapper: Self.mapStatement
        )
    }

    func getOpen(accountId: UUID) async throws -> [Statement] {
        try await db.getAll(
            sql: """
            SELECT * FROM statements
            WHERE account_id = ? AND paid_at IS NULL
            ORDER BY closing_date ASC
            """,
            parameters: [accountId.uuidString],
            mapper: Self.mapStatement
        )
    }

    func getAll() async throws -> [Statement] {
        try await db.getAll(
            sql: "SELECT * FROM statements ORDER BY closing_date DESC",
            parameters: [],
            mapper: Self.mapStatement
        )
    }

    func watchAll() throws -> AsyncThrowingStream<[Statement], Error> {
        try db.watch(
            sql: "SELECT * FROM statements ORDER BY closing_date DESC",
            parameters: [],
            mapper: Self.mapStatement
        )
    }

    // MARK: - Statements: write

    /// Insert simples — usado fora de writeTransaction. Pra fluxos atômicos
    /// (CSV/OFX import), `insertStatementSQL` é exposto pra que callers
    /// componham dentro do próprio `writeTransaction`.
    func insert(_ statement: Statement) async throws {
        try await db.execute(
            sql: Self.insertStatementSQL,
            parameters: Self.insertStatementParams(statement)
        )
    }

    nonisolated static let insertStatementSQL = """
    INSERT INTO statements
        (id, account_id, closing_date, due_date,
         total_amount_cents, paid_at, source_filename,
         created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    nonisolated static func insertStatementParams(_ statement: Statement) -> [(any Sendable)?] {
        [
            statement.id.uuidString,
            statement.accountId.uuidString,
            Converters.dateToString(statement.closingDate),
            Converters.dateToString(statement.dueDate),
            Converters.decimalToCents(statement.totalAmount),
            statement.paidAt.map { Converters.dateToString($0) },
            statement.sourceFilename,
            Converters.dateToString(statement.createdAt),
            Converters.dateToString(statement.updatedAt),
        ]
    }

    // MARK: - Recalc (chamados dentro de writeTransaction pelos repos parceiros)

    /// Recalcula `total_amount_cents` da Statement a partir das transações
    /// vinculadas. Roda em sync dentro do tx — usado pelo
    /// `TransactionRepository` após cada insert/update/delete em conta-cartão.
    /// Depois do recálculo, dispara `recalculatePaidStatus` porque o paid_at
    /// depende do total.
    ///
    /// **Por que `tx.execute` em vez de `db.execute`:** rodar dentro do
    /// mesmo `writeTransaction` que disparou a mudança garante atomicidade
    /// (total + paid_at sempre consistentes com transactions).
    nonisolated static func recalculateTotal(
        statementId: UUID,
        in tx: any PowerSync.ConnectionContext
    ) throws {
        let totalRow = try tx.get(
            sql: """
            SELECT COALESCE(SUM(amount_cents), 0) AS total
            FROM transactions
            WHERE statement_id = ?
            """,
            parameters: [statementId.uuidString],
            mapper: { (cursor: SqlCursor) throws -> Int64 in
                try cursor.getInt64(name: "total")
            }
        )

        try tx.execute(
            sql: """
            UPDATE statements
            SET total_amount_cents = ?, updated_at = ?
            WHERE id = ?
            """,
            parameters: [
                totalRow,
                Converters.dateToString(Date()),
                statementId.uuidString,
            ]
        )

        try recalculatePaidStatus(statementId: statementId, in: tx)
    }

    /// Recalcula `paid_at` comparando `SUM(applied_amount_cents)` dos
    /// payments contra `total_amount_cents`. Set quando coberto, clear
    /// quando descoberto (caso edge: usuário deleta um pagamento parcial).
    nonisolated static func recalculatePaidStatus(
        statementId: UUID,
        in tx: any PowerSync.ConnectionContext
    ) throws {
        struct Status {
            let total: Int64
            let applied: Int64
            let currentPaidAt: String?
        }

        let status = try tx.get(
            sql: """
            SELECT
                s.total_amount_cents AS total,
                COALESCE((
                    SELECT SUM(applied_amount_cents)
                    FROM statement_payments
                    WHERE statement_id = s.id
                ), 0) AS applied,
                s.paid_at AS paid_at
            FROM statements s
            WHERE s.id = ?
            """,
            parameters: [statementId.uuidString],
            mapper: { (cursor: SqlCursor) throws -> Status in
                try Status(
                    total: cursor.getInt64(name: "total"),
                    applied: cursor.getInt64(name: "applied"),
                    currentPaidAt: cursor.getStringOptional(name: "paid_at")
                )
            }
        )

        // Statement com total = 0 e sem payments: paid_at fica NULL.
        // Statement com total > 0 e applied >= total: paid_at = now (se
        // ainda não tem). Caso já esteja paga, preserva timestamp original.
        let shouldBePaid = status.total > 0 && status.applied >= status.total

        if shouldBePaid, status.currentPaidAt == nil {
            try tx.execute(
                sql: "UPDATE statements SET paid_at = ?, updated_at = ? WHERE id = ?",
                parameters: [
                    Converters.dateToString(Date()),
                    Converters.dateToString(Date()),
                    statementId.uuidString,
                ]
            )
        } else if !shouldBePaid, status.currentPaidAt != nil {
            try tx.execute(
                sql: "UPDATE statements SET paid_at = NULL, updated_at = ? WHERE id = ?",
                parameters: [
                    Converters.dateToString(Date()),
                    statementId.uuidString,
                ]
            )
        }
    }

    // MARK: - StatementPayments

    func payments(forStatement statementId: UUID) async throws -> [StatementPayment] {
        try await db.getAll(
            sql: """
            SELECT * FROM statement_payments
            WHERE statement_id = ?
            ORDER BY created_at ASC
            """,
            parameters: [statementId.uuidString],
            mapper: Self.mapPayment
        )
    }

    func payments(forTransaction transactionId: UUID) async throws -> [StatementPayment] {
        try await db.getAll(
            sql: """
            SELECT * FROM statement_payments
            WHERE transaction_id = ?
            """,
            parameters: [transactionId.uuidString],
            mapper: Self.mapPayment
        )
    }

    func watchAllPayments() throws -> AsyncThrowingStream<[StatementPayment], Error> {
        try db.watch(
            sql: "SELECT * FROM statement_payments",
            parameters: [],
            mapper: Self.mapPayment
        )
    }

    /// Atomicamente: apaga todos os payments existentes da transação,
    /// insere os novos, recalcula `paid_at` de cada Statement afetada.
    /// Pattern delete-then-insert porque a UI pode mudar a distribuição
    /// (split mode) — calcular o diff complica sem ganho real.
    func replacePayments(
        forTransaction transactionId: UUID,
        with payments: [StatementPayment]
    ) async throws {
        // Coleta IDs das Statements afetadas (antigas + novas) pra
        // recalcular paid_at de todas.
        let oldPayments = try await self.payments(forTransaction: transactionId)
        let affectedStatementIds = Set(
            oldPayments.map(\.statementId) + payments.map(\.statementId)
        )

        try await db.writeTransaction { tx in
            try tx.execute(
                sql: "DELETE FROM statement_payments WHERE transaction_id = ?",
                parameters: [transactionId.uuidString]
            )
            for payment in payments {
                try tx.execute(
                    sql: """
                    INSERT INTO statement_payments
                        (id, statement_id, transaction_id, applied_amount_cents,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        payment.id.uuidString,
                        payment.statementId.uuidString,
                        payment.transactionId.uuidString,
                        Converters.decimalToCents(payment.appliedAmount),
                        Converters.dateToString(payment.createdAt),
                        Converters.dateToString(payment.updatedAt),
                    ]
                )
            }
            for statementId in affectedStatementIds {
                try Self.recalculatePaidStatus(statementId: statementId, in: tx)
            }
        }
    }

    /// Saldo restante de uma Statement = total − soma dos payments aplicados.
    /// Usado pelo picker pra sugerir "Faltam R$ X". Pode ficar negativo se
    /// houve overpayment (futuro: tratar excesso).
    func remainingAmount(statementId: UUID) async throws -> Decimal {
        let row = try await db.get(
            sql: """
            SELECT
                s.total_amount_cents AS total,
                COALESCE((
                    SELECT SUM(applied_amount_cents)
                    FROM statement_payments
                    WHERE statement_id = s.id
                ), 0) AS applied
            FROM statements s
            WHERE s.id = ?
            """,
            parameters: [statementId.uuidString],
            mapper: { (cursor: SqlCursor) throws -> Int64 in
                let total = try cursor.getInt64(name: "total")
                let applied = try cursor.getInt64(name: "applied")
                return total - applied
            }
        )
        return Converters.centsToDecimal(row)
    }

    // MARK: - Mappers

    private nonisolated static func mapStatement(_ cursor: SqlCursor) throws -> Statement {
        let idStr = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idStr) else {
            throw DatabaseError.invalidUUID(column: "id", value: idStr)
        }
        let accountIdStr = try cursor.getString(name: "account_id")
        guard let accountId = UUID(uuidString: accountIdStr) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: accountIdStr)
        }

        let closingStr = try cursor.getString(name: "closing_date")
        guard let closingDate = Converters.stringToDate(closingStr) else {
            throw DatabaseError.invalidDate(column: "closing_date", value: closingStr)
        }
        let dueStr = try cursor.getString(name: "due_date")
        guard let dueDate = Converters.stringToDate(dueStr) else {
            throw DatabaseError.invalidDate(column: "due_date", value: dueStr)
        }

        let createdAtStr = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtStr) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtStr)
        }
        let updatedAtStr = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtStr) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtStr)
        }

        let paidAt: Date? = try cursor.getStringOptional(name: "paid_at")
            .flatMap { Converters.stringToDate($0) }

        return try Statement(
            id: id,
            accountId: accountId,
            closingDate: closingDate,
            dueDate: dueDate,
            totalAmount: Converters.centsToDecimal(cursor.getInt64(name: "total_amount_cents")),
            paidAt: paidAt,
            sourceFilename: cursor.getStringOptional(name: "source_filename"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private nonisolated static func mapPayment(_ cursor: SqlCursor) throws -> StatementPayment {
        let idStr = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idStr) else {
            throw DatabaseError.invalidUUID(column: "id", value: idStr)
        }
        let statementIdStr = try cursor.getString(name: "statement_id")
        guard let statementId = UUID(uuidString: statementIdStr) else {
            throw DatabaseError.invalidUUID(column: "statement_id", value: statementIdStr)
        }
        let transactionIdStr = try cursor.getString(name: "transaction_id")
        guard let transactionId = UUID(uuidString: transactionIdStr) else {
            throw DatabaseError.invalidUUID(column: "transaction_id", value: transactionIdStr)
        }
        let createdAtStr = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtStr) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtStr)
        }
        let updatedAtStr = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtStr) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtStr)
        }

        return try StatementPayment(
            id: id,
            statementId: statementId,
            transactionId: transactionId,
            appliedAmount: Converters.centsToDecimal(cursor.getInt64(name: "applied_amount_cents")),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
