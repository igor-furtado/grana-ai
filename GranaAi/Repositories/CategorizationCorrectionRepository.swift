import Foundation
import PowerSync

/// Acesso à tabela `categorization_corrections`. Fonte dos exemplos few-shot
/// usados nos prompts subsequentes — `recent(limit:)` devolve as N mais
/// recentes ordenadas por `created_at DESC`.
///
/// Histórico mantido completo (não-destrutivo): cada correção entra como
/// linha nova; correções antigas continuam servindo de trail de auditoria.
final class CategorizationCorrectionRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ correction: CategorizationCorrection) async throws {
        try await db.execute(
            sql: """
            INSERT INTO categorization_corrections
                (id, description_hash, normalized_description,
                 original_category_id, original_subcategory_id,
                 corrected_category_id, corrected_subcategory_id,
                 transaction_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                correction.id.uuidString,
                correction.descriptionHash,
                correction.normalizedDescription,
                correction.originalCategoryId?.uuidString,
                correction.originalSubcategoryId?.uuidString,
                correction.correctedCategoryId.uuidString,
                correction.correctedSubcategoryId?.uuidString,
                correction.transactionId.uuidString,
                Converters.dateToString(correction.createdAt),
            ]
        )
    }

    /// As `limit` correções mais recentes. Usado pra montar os few-shots do
    /// próximo prompt. Limit ~30 cabe num system prompt sem inflar tokens.
    func recent(limit: Int) async throws -> [CategorizationCorrection] {
        try await db.getAll(
            sql: """
            SELECT * FROM categorization_corrections
            ORDER BY created_at DESC
            LIMIT ?
            """,
            parameters: [Int64(limit)],
            mapper: Self.mapCorrection
        )
    }

    func getAll() async throws -> [CategorizationCorrection] {
        try await db.getAll(
            sql: """
            SELECT * FROM categorization_corrections
            ORDER BY created_at DESC
            """,
            parameters: [],
            mapper: Self.mapCorrection
        )
    }

    // MARK: - Mapper

    private nonisolated static func mapCorrection(_ cursor: SqlCursor) throws -> CategorizationCorrection {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let originalCategoryId: UUID?
        if let s = try cursor.getStringOptional(name: "original_category_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "original_category_id", value: s)
            }
            originalCategoryId = uuid
        } else {
            originalCategoryId = nil
        }

        let originalSubcategoryId: UUID?
        if let s = try cursor.getStringOptional(name: "original_subcategory_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "original_subcategory_id", value: s)
            }
            originalSubcategoryId = uuid
        } else {
            originalSubcategoryId = nil
        }

        let correctedCategoryIdString = try cursor.getString(name: "corrected_category_id")
        guard let correctedCategoryId = UUID(uuidString: correctedCategoryIdString) else {
            throw DatabaseError.invalidUUID(column: "corrected_category_id", value: correctedCategoryIdString)
        }

        let correctedSubcategoryId: UUID?
        if let s = try cursor.getStringOptional(name: "corrected_subcategory_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "corrected_subcategory_id", value: s)
            }
            correctedSubcategoryId = uuid
        } else {
            correctedSubcategoryId = nil
        }

        let transactionIdString = try cursor.getString(name: "transaction_id")
        guard let transactionId = UUID(uuidString: transactionIdString) else {
            throw DatabaseError.invalidUUID(column: "transaction_id", value: transactionIdString)
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        return try CategorizationCorrection(
            id: id,
            descriptionHash: cursor.getString(name: "description_hash"),
            normalizedDescription: cursor.getString(name: "normalized_description"),
            originalCategoryId: originalCategoryId,
            originalSubcategoryId: originalSubcategoryId,
            correctedCategoryId: correctedCategoryId,
            correctedSubcategoryId: correctedSubcategoryId,
            transactionId: transactionId,
            createdAt: createdAt
        )
    }
}
