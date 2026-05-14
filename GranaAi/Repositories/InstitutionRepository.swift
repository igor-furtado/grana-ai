import Foundation
import PowerSync

final class InstitutionRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ institution: Institution) async throws {
        try await db.execute(
            sql: """
                INSERT INTO institutions
                    (id, code, name, kind, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                institution.id.uuidString,
                institution.code,
                institution.name,
                institution.kind.rawValue,
                Converters.dateToString(institution.createdAt),
                Converters.dateToString(institution.updatedAt),
            ]
        )
    }

    func update(_ institution: Institution) async throws {
        try await db.execute(
            sql: """
                UPDATE institutions SET
                    code = ?, name = ?, kind = ?, updated_at = ?
                WHERE id = ?
                """,
            parameters: [
                institution.code,
                institution.name,
                institution.kind.rawValue,
                Converters.dateToString(institution.updatedAt),
                institution.id.uuidString,
            ]
        )
    }

    func getAll() async throws -> [Institution] {
        try await db.getAll(
            sql: "SELECT * FROM institutions ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapInstitution
        )
    }

    func findByCode(_ code: String) async throws -> Institution? {
        try await db.getOptional(
            sql: "SELECT * FROM institutions WHERE code = ? LIMIT 1",
            parameters: [code],
            mapper: Self.mapInstitution
        )
    }

    func getById(_ id: UUID) async throws -> Institution? {
        try await db.getOptional(
            sql: "SELECT * FROM institutions WHERE id = ?",
            parameters: [id.uuidString],
            mapper: Self.mapInstitution
        )
    }

    func watchAll() throws -> AsyncThrowingStream<[Institution], Error> {
        try db.watch(
            sql: "SELECT * FROM institutions ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapInstitution
        )
    }

    private nonisolated static func mapInstitution(_ cursor: SqlCursor) throws -> Institution {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }
        let kindRaw = try cursor.getString(name: "kind")
        guard let kind = InstitutionKind(rawValue: kindRaw) else {
            throw DatabaseError.invalidEnum(column: "kind", value: kindRaw)
        }
        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }
        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }
        return Institution(
            id: id,
            code: try cursor.getString(name: "code"),
            name: try cursor.getString(name: "name"),
            kind: kind,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
