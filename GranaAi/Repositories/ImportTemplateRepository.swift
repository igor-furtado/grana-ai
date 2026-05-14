import Foundation
import PowerSync

/// Acesso a `import_templates`. O `ColumnMapping` é serializado como JSON na
/// coluna `mapping_json` — adicionar campo novo no mapping não exige
/// alteração de schema.
final class ImportTemplateRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ template: ImportTemplate) async throws {
        let mappingJSON = try Self.encodeMapping(template.mapping)
        try await db.execute(
            sql: """
                INSERT INTO import_templates
                    (id, name, source_kind, mapping_json, date_format,
                     decimal_separator, default_account_id,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                template.id.uuidString,
                template.name,
                template.sourceKind.rawValue,
                mappingJSON,
                template.dateFormat,
                template.decimalSeparator,
                template.defaultAccountId?.uuidString,
                Converters.dateToString(template.createdAt),
                Converters.dateToString(template.updatedAt),
            ]
        )
    }

    func update(_ template: ImportTemplate) async throws {
        let mappingJSON = try Self.encodeMapping(template.mapping)
        try await db.execute(
            sql: """
                UPDATE import_templates SET
                    name = ?, source_kind = ?, mapping_json = ?, date_format = ?,
                    decimal_separator = ?, default_account_id = ?, updated_at = ?
                WHERE id = ?
                """,
            parameters: [
                template.name,
                template.sourceKind.rawValue,
                mappingJSON,
                template.dateFormat,
                template.decimalSeparator,
                template.defaultAccountId?.uuidString,
                Converters.dateToString(template.updatedAt),
                template.id.uuidString,
            ]
        )
    }

    func delete(id: UUID) async throws {
        try await db.execute(
            sql: "DELETE FROM import_templates WHERE id = ?",
            parameters: [id.uuidString]
        )
    }

    func getAll() async throws -> [ImportTemplate] {
        try await db.getAll(
            sql: "SELECT * FROM import_templates ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapTemplate
        )
    }

    func getByName(_ name: String) async throws -> ImportTemplate? {
        try await db.getOptional(
            sql: "SELECT * FROM import_templates WHERE name = ? LIMIT 1",
            parameters: [name],
            mapper: Self.mapTemplate
        )
    }

    func watchAll() throws -> AsyncThrowingStream<[ImportTemplate], Error> {
        try db.watch(
            sql: "SELECT * FROM import_templates ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapTemplate
        )
    }

    // MARK: - Codable bridge

    // Encoders/decoders são pesados pra alocar; deixar estáticos paga a
    // primeira chamada e mais nada.
    private nonisolated static let jsonEncoder = JSONEncoder()
    private nonisolated static let jsonDecoder = JSONDecoder()

    private nonisolated static func encodeMapping(_ mapping: ColumnMapping) throws -> String {
        let data = try jsonEncoder.encode(mapping)
        guard let s = String(data: data, encoding: .utf8) else {
            throw ImportError.templateInvalidJSON
        }
        return s
    }

    private nonisolated static func decodeMapping(_ json: String) throws -> ColumnMapping {
        guard let data = json.data(using: .utf8) else {
            throw ImportError.templateInvalidJSON
        }
        do {
            return try jsonDecoder.decode(ColumnMapping.self, from: data)
        } catch {
            throw ImportError.templateInvalidJSON
        }
    }

    private nonisolated static func mapTemplate(_ cursor: SqlCursor) throws -> ImportTemplate {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let kindRaw = try cursor.getString(name: "source_kind")
        guard let kind = ImportSourceKind(rawValue: kindRaw) else {
            throw DatabaseError.invalidEnum(column: "source_kind", value: kindRaw)
        }

        let mapping = try decodeMapping(try cursor.getString(name: "mapping_json"))

        let defaultAccountId: UUID?
        if let s = try cursor.getStringOptional(name: "default_account_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "default_account_id", value: s)
            }
            defaultAccountId = uuid
        } else {
            defaultAccountId = nil
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }
        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }

        return ImportTemplate(
            id: id,
            name: try cursor.getString(name: "name"),
            sourceKind: kind,
            mapping: mapping,
            dateFormat: try cursor.getString(name: "date_format"),
            decimalSeparator: try cursor.getString(name: "decimal_separator"),
            defaultAccountId: defaultAccountId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
