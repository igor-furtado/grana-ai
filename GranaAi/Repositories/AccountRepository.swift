import Foundation
import PowerSync

final class AccountRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    func insert(_ account: Account) async throws {
        try await db.execute(
            sql: """
                INSERT INTO accounts
                    (id, name, type, initial_balance_cents, archived,
                     institution_id, branch_id, account_number, currency,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                account.id.uuidString,
                account.name,
                account.type.rawValue,
                Converters.decimalToCents(account.initialBalance),
                account.archived ? 1 : 0,
                account.institutionId?.uuidString,
                account.branchId,
                account.accountNumber,
                account.currency,
                Converters.dateToString(account.createdAt),
                Converters.dateToString(account.updatedAt),
            ]
        )
    }

    func update(_ account: Account) async throws {
        try await db.execute(
            sql: """
                UPDATE accounts SET
                    name = ?, type = ?, initial_balance_cents = ?, archived = ?,
                    institution_id = ?, branch_id = ?, account_number = ?, currency = ?,
                    updated_at = ?
                WHERE id = ?
                """,
            parameters: [
                account.name,
                account.type.rawValue,
                Converters.decimalToCents(account.initialBalance),
                account.archived ? 1 : 0,
                account.institutionId?.uuidString,
                account.branchId,
                account.accountNumber,
                account.currency,
                Converters.dateToString(account.updatedAt),
                account.id.uuidString,
            ]
        )
    }

    func delete(id: UUID) async throws {
        try await db.execute(
            sql: "DELETE FROM accounts WHERE id = ?",
            parameters: [id.uuidString]
        )
    }

    /// Identidade bancária: usa a tripla (instituição, agência, número) pra
    /// localizar uma conta existente quando um OFX traz dados de banco. Se
    /// achar, o auto-create do importer reusa em vez de duplicar.
    func findByBankIdentity(
        institutionId: UUID,
        branchId: String?,
        accountNumber: String
    ) async throws -> Account? {
        // Comparação de `branch_id` precisa ser `IS NULL`-safe — alguns OFX
        // não trazem agência. Usamos `(branch_id = ? OR (branch_id IS NULL AND ? IS NULL))`.
        try await db.getOptional(
            sql: """
                SELECT * FROM accounts
                WHERE institution_id = ?
                  AND account_number = ?
                  AND (branch_id = ? OR (branch_id IS NULL AND ? IS NULL))
                LIMIT 1
                """,
            parameters: [
                institutionId.uuidString,
                accountNumber,
                branchId,
                branchId,
            ],
            mapper: Self.mapAccount
        )
    }

    func getAll() async throws -> [Account] {
        try await db.getAll(
            sql: "SELECT * FROM accounts ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapAccount
        )
    }

    /// Soma de `initial_balance_cents` de contas **não-arquivadas**. Combinado
    /// no Store com (receitas − despesas) lifetime, dá o saldo total.
    /// `archived = 0` filtra contas que o usuário tirou do dia-a-dia mas não
    /// quer deletar (preserva histórico das transações antigas).
    func sumInitialBalance() async throws -> Decimal {
        let cents = try await db.get(
            sql: """
                SELECT COALESCE(SUM(initial_balance_cents), 0) AS total
                FROM accounts
                WHERE archived = 0
                """,
            parameters: [],
            mapper: { (cursor: SqlCursor) throws -> Int64 in
                try cursor.getInt64(name: "total")
            }
        )
        return Converters.centsToDecimal(cents)
    }

    func watchAll() throws -> AsyncThrowingStream<[Account], Error> {
        try db.watch(
            sql: "SELECT * FROM accounts ORDER BY name ASC",
            parameters: [],
            mapper: Self.mapAccount
        )
    }

    private nonisolated static func mapAccount(_ cursor: SqlCursor) throws -> Account {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let typeRaw = try cursor.getString(name: "type")
        guard let type = AccountType(rawValue: typeRaw) else {
            throw DatabaseError.invalidEnum(column: "type", value: typeRaw)
        }

        let institutionId: UUID?
        if let s = try cursor.getStringOptional(name: "institution_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "institution_id", value: s)
            }
            institutionId = uuid
        } else {
            institutionId = nil
        }

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }

        // `currency` veio depois do schema da Fase 1: contas legadas (criadas
        // antes desta fase) podem não ter o valor. Default "BRL" cobre isso
        // sem precisar de migration.
        let currency = (try cursor.getStringOptional(name: "currency")) ?? "BRL"

        return Account(
            id: id,
            name: try cursor.getString(name: "name"),
            type: type,
            initialBalance: Converters.centsToDecimal(
                try cursor.getInt64(name: "initial_balance_cents")
            ),
            archived: (try cursor.getInt64(name: "archived")) != 0,
            institutionId: institutionId,
            branchId: try cursor.getStringOptional(name: "branch_id"),
            accountNumber: try cursor.getStringOptional(name: "account_number"),
            currency: currency,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
