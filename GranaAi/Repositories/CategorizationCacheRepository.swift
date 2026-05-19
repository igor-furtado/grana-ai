import Foundation
import PowerSync

/// Acesso à tabela `categorization_cache`. Lookup é por
/// (`description_hash`, `model`) — chave composta que invalida automaticamente
/// quando a configuração de modelo muda (ver `Config.anthropicCategorizationModel`).
///
/// **Upsert manual:** PowerSync expõe SQL puro, sem `INSERT OR REPLACE` por
/// trás de helper tipado. Fazemos delete-then-insert dentro de
/// `writeTransaction` quando precisamos garantir só uma entrada por hash+model.
final class CategorizationCacheRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /// Lookup O(1). Devolve `nil` se não houver entrada pro hash naquele
    /// modelo (cache miss → consultar IA).
    func lookup(descriptionHash: String, model: String) async throws -> CategorizationCacheEntry? {
        try await db.getOptional(
            sql: """
                SELECT * FROM categorization_cache
                WHERE description_hash = ? AND model = ?
                LIMIT 1
                """,
            parameters: [descriptionHash, model],
            mapper: Self.mapEntry
        )
    }

    /// Lookup batched — recebe N hashes, devolve `[hash: entry]` em uma só
    /// query. Usado pelo service na fase de pré-check antes de chamar a IA.
    func lookupMany(descriptionHashes: [String], model: String) async throws -> [String: CategorizationCacheEntry] {
        guard !descriptionHashes.isEmpty else { return [:] }

        // PowerSync expõe prepared statements via `?`; `IN` precisa de N
        // placeholders dinâmicos. Geramos `?, ?, ...` no SQL e passamos
        // hashes + model como parâmetros — ainda blindado contra injection.
        let placeholders = Array(repeating: "?", count: descriptionHashes.count).joined(separator: ", ")
        let sql = """
            SELECT * FROM categorization_cache
            WHERE description_hash IN (\(placeholders)) AND model = ?
            """
        var parameters: [(any Sendable)?] = descriptionHashes.map { $0 as any Sendable }
        parameters.append(model)

        let entries = try await db.getAll(
            sql: sql,
            parameters: parameters,
            mapper: Self.mapEntry
        )

        var result: [String: CategorizationCacheEntry] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.descriptionHash] = entry
        }
        return result
    }

    /// Insere ou atualiza uma entrada. Usa `writeTransaction` pra delete-then-insert
    /// atomicamente, evitando duplicatas por hash+model.
    func upsert(_ entry: CategorizationCacheEntry) async throws {
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: "DELETE FROM categorization_cache WHERE description_hash = ? AND model = ?",
                parameters: [entry.descriptionHash, entry.model]
            )
            try tx.execute(
                sql: Self.insertSQL,
                parameters: Self.insertParameters(for: entry)
            )
        }
    }

    /// Versão batched do upsert — uma `writeTransaction` única, N entradas.
    func upsertMany(_ entries: [CategorizationCacheEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await db.writeTransaction { tx in
            for entry in entries {
                try tx.execute(
                    sql: "DELETE FROM categorization_cache WHERE description_hash = ? AND model = ?",
                    parameters: [entry.descriptionHash, entry.model]
                )
                try tx.execute(
                    sql: Self.insertSQL,
                    parameters: Self.insertParameters(for: entry)
                )
            }
        }
    }

    /// Invalida cache de uma descrição específica (usado quando o usuário
    /// corrige uma categorização — ver `CategorizationService.applyCorrection`).
    func invalidate(descriptionHash: String) async throws {
        try await db.execute(
            sql: "DELETE FROM categorization_cache WHERE description_hash = ?",
            parameters: [descriptionHash]
        )
    }

    /// Apaga TUDO. Usado pelo botão "Recategorizar transações antigas" em
    /// Settings — força a IA a reavaliar do zero respeitando as correções
    /// recentes que entraram nos few-shots.
    func clear() async throws {
        try await db.execute(sql: "DELETE FROM categorization_cache", parameters: [])
    }

    // MARK: - SQL/mapper

    private nonisolated static let insertSQL = """
        INSERT INTO categorization_cache
            (id, description_hash, normalized_description, category_id,
             subcategory_id, confidence, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private nonisolated static func insertParameters(for entry: CategorizationCacheEntry) -> [(any Sendable)?] {
        [
            entry.id.uuidString,
            entry.descriptionHash,
            entry.normalizedDescription,
            entry.categoryId.uuidString,
            entry.subcategoryId?.uuidString,
            entry.confidence,
            entry.model,
            Converters.dateToString(entry.createdAt),
            Converters.dateToString(entry.updatedAt),
        ]
    }

    private nonisolated static func mapEntry(_ cursor: SqlCursor) throws -> CategorizationCacheEntry {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let categoryIdString = try cursor.getString(name: "category_id")
        guard let categoryId = UUID(uuidString: categoryIdString) else {
            throw DatabaseError.invalidUUID(column: "category_id", value: categoryIdString)
        }

        let subcategoryId: UUID?
        if let s = try cursor.getStringOptional(name: "subcategory_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "subcategory_id", value: s)
            }
            subcategoryId = uuid
        } else {
            subcategoryId = nil
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }

        return CategorizationCacheEntry(
            id: id,
            descriptionHash: try cursor.getString(name: "description_hash"),
            normalizedDescription: try cursor.getString(name: "normalized_description"),
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            confidence: try cursor.getDouble(name: "confidence"),
            model: try cursor.getString(name: "model"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
