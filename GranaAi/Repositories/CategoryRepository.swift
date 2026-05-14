import Foundation
import PowerSync

final class CategoryRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ category: Category) async throws {
        try await db.execute(
            sql: """
                INSERT INTO categories
                    (id, parent_id, name, kind, icon, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                category.id.uuidString,
                category.parentId?.uuidString,
                category.name,
                category.kind.rawValue,
                category.icon?.rawValue,
                Converters.dateToString(category.createdAt),
            ]
        )
    }

    func getAll() async throws -> [Category] {
        try await db.getAll(
            sql: "SELECT * FROM categories ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapCategory
        )
    }

    func watchAll() throws -> AsyncThrowingStream<[Category], Error> {
        try db.watch(
            sql: "SELECT * FROM categories ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapCategory
        )
    }

    func getByKind(_ kind: CategoryKind) async throws -> [Category] {
        try await db.getAll(
            sql: "SELECT * FROM categories WHERE kind = ? ORDER BY name ASC",
            parameters: [kind.rawValue],
            mapper: Self.mapCategory
        )
    }

    func getRootCategories() async throws -> [Category] {
        try await db.getAll(
            sql: "SELECT * FROM categories WHERE parent_id IS NULL ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapCategory
        )
    }

    /// Busca uma categoria **raiz** pelo nome exato. Usado pela importação
    /// (Fase 3) pra resolver o ID da categoria "Não Classificado" sem depender
    /// de UUID hard-coded (que muda a cada seed).
    func findRootByName(_ name: String) async throws -> Category? {
        try await db.getOptional(
            sql: """
                SELECT * FROM categories
                WHERE parent_id IS NULL AND name = ?
                LIMIT 1
                """,
            parameters: [name],
            mapper: Self.mapCategory
        )
    }

    func getSubcategoriesOf(parentId: UUID) async throws -> [Category] {
        try await db.getAll(
            sql: "SELECT * FROM categories WHERE parent_id = ? ORDER BY name ASC",
            parameters: [parentId.uuidString],
            mapper: Self.mapCategory
        )
    }

    private nonisolated static func mapCategory(_ cursor: SqlCursor) throws -> Category {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let parentId: UUID?
        if let s = try cursor.getStringOptional(name: "parent_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "parent_id", value: s)
            }
            parentId = uuid
        } else {
            parentId = nil
        }

        let kindRaw = try cursor.getString(name: "kind")
        guard let kind = CategoryKind(rawValue: kindRaw) else {
            throw DatabaseError.invalidEnum(column: "kind", value: kindRaw)
        }

        let icon: CategoryIcon?
        if let iconRaw = try cursor.getStringOptional(name: "icon") {
            guard let parsed = CategoryIcon(rawValue: iconRaw) else {
                throw DatabaseError.invalidEnum(column: "icon", value: iconRaw)
            }
            icon = parsed
        } else {
            icon = nil
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        return Category(
            id: id,
            parentId: parentId,
            name: try cursor.getString(name: "name"),
            kind: kind,
            icon: icon,
            createdAt: createdAt
        )
    }
}
