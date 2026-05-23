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
                (id, type, initial_balance_cents, archived,
                 institution_id, branch_id, account_number, card_last_four,
                 currency, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                account.id.uuidString,
                account.type.rawValue,
                Converters.decimalToCents(account.initialBalance),
                account.archived ? 1 : 0,
                account.institutionId?.uuidString,
                account.branchId,
                account.accountNumber,
                account.cardLastFour,
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
                type = ?, initial_balance_cents = ?, archived = ?,
                institution_id = ?, branch_id = ?, account_number = ?,
                card_last_four = ?, currency = ?, updated_at = ?
            WHERE id = ?
            """,
            parameters: [
                account.type.rawValue,
                Converters.decimalToCents(account.initialBalance),
                account.archived ? 1 : 0,
                account.institutionId?.uuidString,
                account.branchId,
                account.accountNumber,
                account.cardLastFour,
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
            sql: """
            SELECT * FROM accounts
            ORDER BY type ASC, institution_id ASC, branch_id ASC,
                     account_number ASC, card_last_four ASC
            """,
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
            sql: """
            SELECT * FROM accounts
            ORDER BY type ASC, institution_id ASC, branch_id ASC,
                     account_number ASC, card_last_four ASC
            """,
            parameters: [],
            mapper: Self.mapAccount
        )
    }

    /// Saldo atual por conta = `initial_balance_cents + saídas pela conta +
    /// entradas vindas de transferências apontadas pra esta conta`.
    ///
    /// Detalhe por `categories.kind`:
    /// - `income` → soma na `account_id`.
    /// - `expense` → subtrai da `account_id`.
    /// - `transfer` com `destination_account_id` preenchido → subtrai da
    ///   `account_id` (origem) E soma na `destination_account_id` (destino).
    ///   É como modelamos pagamento de fatura de cartão: a corrente perde, o
    ///   cartão abate dívida — sem precisar de transação espelho.
    /// - `transfer` sem destino → neutro (compat com transferências legadas
    ///   importadas antes da Fase 4.5).
    ///
    /// **Por que duas subqueries em vez de LEFT JOIN + GROUP BY:** o lado de
    /// entrada (`destination_account_id = a.id`) exige um segundo JOIN com
    /// outro alias da `transactions` — o GROUP BY explodia em produto
    /// cartesiano. Subqueries correlacionadas mantêm cada lado isolado e o
    /// SQLite otimiza com índice por `account_id` / `destination_account_id`.
    /// Custo extra é desprezível pra contas com poucas centenas de transações.
    ///
    /// Watch re-emite a cada mudança em `accounts`, `transactions` ou
    /// `categories` — fechando o ciclo reativo: criar/editar/apagar
    /// transação reflete no saldo dos cards em tempo real.
    func watchBalances() throws -> AsyncThrowingStream<[UUID: Decimal], Error> {
        let stream = try db.watch(
            sql: """
            SELECT a.id AS account_id,
                   a.initial_balance_cents
                   + COALESCE((
                       SELECT SUM(
                           CASE c.kind
                               WHEN 'income'   THEN  t.amount_cents
                               WHEN 'expense'  THEN -t.amount_cents
                               WHEN 'transfer' THEN
                                   CASE WHEN t.destination_account_id IS NOT NULL
                                        THEN -t.amount_cents ELSE 0 END
                               ELSE 0
                           END
                       )
                       FROM transactions t
                       JOIN categories c ON c.id = t.category_id
                       WHERE t.account_id = a.id
                   ), 0)
                   + COALESCE((
                       SELECT SUM(t.amount_cents)
                       FROM transactions t
                       JOIN categories c ON c.id = t.category_id
                       WHERE t.destination_account_id = a.id
                         AND c.kind = 'transfer'
                   ), 0) AS balance_cents
            FROM accounts a
            """,
            parameters: [],
            mapper: Self.mapBalanceRow
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in stream {
                        let dict = Dictionary(uniqueKeysWithValues: rows)
                        continuation.yield(dict)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func mapBalanceRow(_ cursor: SqlCursor) throws -> (UUID, Decimal) {
        let idString = try cursor.getString(name: "account_id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: idString)
        }
        let cents = try cursor.getInt64(name: "balance_cents")
        return (id, Converters.centsToDecimal(cents))
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
        let currency = try (cursor.getStringOptional(name: "currency")) ?? "BRL"

        return try Account(
            id: id,
            type: type,
            initialBalance: Converters.centsToDecimal(
                cursor.getInt64(name: "initial_balance_cents")
            ),
            archived: (cursor.getInt64(name: "archived")) != 0,
            institutionId: institutionId,
            branchId: cursor.getStringOptional(name: "branch_id"),
            accountNumber: cursor.getStringOptional(name: "account_number"),
            cardLastFour: cursor.getStringOptional(name: "card_last_four"),
            currency: currency,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
