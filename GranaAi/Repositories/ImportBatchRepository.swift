import Foundation
import PowerSync

/// Acesso a `import_batches`. Operação crítica é o `delete(id:)` — apaga o
/// batch *e* todas as transactions associadas em uma única `writeTransaction`,
/// garantindo que "desfazer" é atômico: ou tudo volta, ou nada.
final class ImportBatchRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ batch: ImportBatch) async throws {
        try await db.execute(
            sql: """
                INSERT INTO import_batches
                    (id, source_filename, account_id, row_count, imported_at,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                batch.id.uuidString,
                batch.sourceFilename,
                batch.accountId.uuidString,
                Int64(batch.rowCount),
                Converters.dateToString(batch.importedAt),
                Converters.dateToString(batch.createdAt),
                Converters.dateToString(batch.updatedAt),
            ]
        )
    }

    /// Apaga o batch + todas as transactions com `import_batch_id = batchId`
    /// **atomicamente**. Sem `writeTransaction`, o app poderia ficar num estado
    /// onde a row do batch sumiu mas as transactions órfãs continuaram (ou
    /// vice-versa) — `writeTransaction` faz rollback automático em qualquer
    /// throw.
    func delete(id batchId: UUID) async throws {
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: "DELETE FROM transactions WHERE import_batch_id = ?",
                parameters: [batchId.uuidString]
            )
            try tx.execute(
                sql: "DELETE FROM import_batches WHERE id = ?",
                parameters: [batchId.uuidString]
            )
        }
    }

    func getById(_ id: UUID) async throws -> ImportBatch? {
        try await db.getOptional(
            sql: "SELECT * FROM import_batches WHERE id = ?",
            parameters: [id.uuidString],
            mapper: Self.mapBatch
        )
    }

    func getAll() async throws -> [ImportBatch] {
        try await db.getAll(
            sql: "SELECT * FROM import_batches ORDER BY imported_at DESC",
            parameters: [],
            mapper: Self.mapBatch
        )
    }

    func watchAll() throws -> AsyncThrowingStream<[ImportBatch], Error> {
        try db.watch(
            sql: "SELECT * FROM import_batches ORDER BY imported_at DESC",
            parameters: [],
            mapper: Self.mapBatch
        )
    }

    private nonisolated static func mapBatch(_ cursor: SqlCursor) throws -> ImportBatch {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let accountIdString = try cursor.getString(name: "account_id")
        guard let accountId = UUID(uuidString: accountIdString) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: accountIdString)
        }

        let importedAtString = try cursor.getString(name: "imported_at")
        guard let importedAt = Converters.stringToDate(importedAtString) else {
            throw DatabaseError.invalidDate(column: "imported_at", value: importedAtString)
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }

        return ImportBatch(
            id: id,
            sourceFilename: try cursor.getString(name: "source_filename"),
            accountId: accountId,
            rowCount: Int(try cursor.getInt64(name: "row_count")),
            importedAt: importedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
