import Foundation
import PowerSync

final class StatementRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

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
        let rows = try await db.getAll(
            sql: """
            SELECT * FROM statements
            WHERE account_id = ?
            ORDER BY closing_date ASC
            """,
            parameters: [accountId.uuidString],
            mapper: Self.mapStatement
        )
        return rows.filter { $0.remainingAmount > 0 }
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
            ORDER BY created_at ASC
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

    func creditApplications(
        forStatement statementId: UUID
    ) async throws -> [StatementCreditApplication] {
        try await db.getAll(
            sql: """
            SELECT * FROM statement_credit_applications
            WHERE source_statement_id = ? OR destination_statement_id = ?
            ORDER BY created_at ASC
            """,
            parameters: [statementId.uuidString, statementId.uuidString],
            mapper: Self.mapCreditApplication
        )
    }

    /// Compatibilidade temporária com callers antigos: a distribuição agora
    /// é sempre derivada da transferência e não aceita alocação arbitrária.
    func replacePayments(
        forTransaction transactionId: UUID,
        with _: [StatementPayment]
    ) async throws {
        try await db.writeTransaction { tx in
            guard let accountIdRaw: String = try tx.getOptional(
                sql: """
                SELECT destination_account_id
                FROM transactions WHERE id = ?
                """,
                parameters: [transactionId.uuidString],
                mapper: { cursor in
                    try cursor.getString(name: "destination_account_id")
                }
            ), let accountId = UUID(uuidString: accountIdRaw) else {
                return
            }
            try StatementProjector.rebuild(accountId: accountId, in: tx)
        }
    }

    func remainingAmount(statementId: UUID) async throws -> Decimal {
        guard let statement = try await get(id: statementId) else { return 0 }
        return statement.remainingAmount
    }

    func rebuild(accountId: UUID) async throws {
        try await db.writeTransaction { tx in
            try StatementProjector.rebuild(accountId: accountId, in: tx)
        }
    }

    private nonisolated static func mapStatement(_ cursor: SqlCursor) throws -> Statement {
        let id = try uuid(cursor, "id")
        let accountId = try uuid(cursor, "account_id")
        let closingDate = try date(cursor, "closing_date")
        let dueDate = try date(cursor, "due_date")
        let createdAt = try date(cursor, "created_at")
        let updatedAt = try date(cursor, "updated_at")
        let settledAt = try cursor.getStringOptional(name: "settled_at")
            .flatMap(Converters.stringToDate)

        return try Statement(
            id: id,
            accountId: accountId,
            closingDate: closingDate,
            dueDate: dueDate,
            netAmount: Converters.centsToDecimal(
                cursor.getInt64(name: "net_amount_cents")
            ),
            creditReceived: Converters.centsToDecimal(
                cursor.getInt64(name: "credit_received_cents")
            ),
            paymentApplied: Converters.centsToDecimal(
                cursor.getInt64(name: "payment_applied_cents")
            ),
            settledAt: settledAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private nonisolated static func mapPayment(_ cursor: SqlCursor) throws -> StatementPayment {
        try StatementPayment(
            id: uuid(cursor, "id"),
            statementId: uuid(cursor, "statement_id"),
            transactionId: uuid(cursor, "transaction_id"),
            appliedAmount: Converters.centsToDecimal(
                cursor.getInt64(name: "applied_amount_cents")
            ),
            createdAt: date(cursor, "created_at"),
            updatedAt: date(cursor, "updated_at")
        )
    }

    private nonisolated static func mapCreditApplication(
        _ cursor: SqlCursor
    ) throws -> StatementCreditApplication {
        try StatementCreditApplication(
            id: uuid(cursor, "id"),
            sourceStatementId: uuid(cursor, "source_statement_id"),
            destinationStatementId: uuid(cursor, "destination_statement_id"),
            appliedAmount: Converters.centsToDecimal(
                cursor.getInt64(name: "applied_amount_cents")
            ),
            createdAt: date(cursor, "created_at")
        )
    }

    private nonisolated static func uuid(
        _ cursor: SqlCursor,
        _ column: String
    ) throws -> UUID {
        let raw = try cursor.getString(name: column)
        guard let value = UUID(uuidString: raw) else {
            throw DatabaseError.invalidUUID(column: column, value: raw)
        }
        return value
    }

    private nonisolated static func date(
        _ cursor: SqlCursor,
        _ column: String
    ) throws -> Date {
        let raw = try cursor.getString(name: column)
        guard let value = Converters.stringToDate(raw) else {
            throw DatabaseError.invalidDate(column: column, value: raw)
        }
        return value
    }
}
