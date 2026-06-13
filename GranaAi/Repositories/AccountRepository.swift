import Foundation
import PowerSync

final class AccountRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - Insert / Update / Delete

    /// Cria a `Account` + a tabela-irmã correspondente ao tipo numa única
    /// `writeTransaction`. A invariante "type=checking ↔ bank_accounts" e
    /// "type=creditCard ↔ credit_cards" não está no schema (PowerSync não tem
    /// constraints), então é responsabilidade do caller passar o `details` do
    /// tipo certo. Caller passa nil pra criar Account sem details (raro;
    /// só faz sentido durante testes ou seed).
    func insert(
        _ account: Account,
        bankDetails: BankAccountDetails? = nil,
        creditCardDetails: CreditCardDetails? = nil
    ) async throws {
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: Self.insertAccountSQL,
                parameters: Self.insertAccountParams(account)
            )
            if let bankDetails {
                try tx.execute(
                    sql: Self.insertBankSQL,
                    parameters: Self.insertBankParams(bankDetails)
                )
            }
            if let creditCardDetails {
                try tx.execute(
                    sql: Self.insertCardSQL,
                    parameters: Self.insertCardParams(creditCardDetails)
                )
                try tx.execute(
                    sql: Self.insertCycleConfigSQL,
                    parameters: Self.insertCycleConfigParams(
                        CreditCardCycleConfig(
                            id: UUID(),
                            accountId: account.id,
                            effectiveFrom: .distantPast,
                            statementClosingDay: creditCardDetails.statementClosingDay,
                            paymentDueDay: creditCardDetails.paymentDueDay,
                            createdAt: account.createdAt
                        )
                    )
                )
            }
        }
    }

    /// Atualiza a `Account` + a tabela-irmã correspondente. `details` é
    /// upsert (delete-then-insert) pra cobrir o caso raro de tipo mudar de
    /// `checking → creditCard` (ou vice-versa) — primeiro apaga details
    /// antigos dos dois tipos, depois insere o novo.
    func update(
        _ account: Account,
        bankDetails: BankAccountDetails? = nil,
        creditCardDetails: CreditCardDetails? = nil,
        cycleEffectiveFrom: Date? = nil
    ) async throws {
        try await db.writeTransaction { tx in
            let previousCardDetails: CreditCardDetails? = try tx.getOptional(
                sql: "SELECT * FROM credit_cards WHERE account_id = ? LIMIT 1",
                parameters: [account.id.uuidString],
                mapper: Self.mapCardDetails
            )
            try tx.execute(
                sql: Self.updateAccountSQL,
                parameters: Self.updateAccountParams(account)
            )

            // Upsert via delete-then-insert. Cobre o caso de mudar de tipo
            // (raro mas possível na UI). PowerSync não tem ON CONFLICT
            // genérico aqui — duas linhas seriam ambíguas, e o schema
            // tampouco impede.
            try tx.execute(
                sql: "DELETE FROM bank_accounts WHERE account_id = ?",
                parameters: [account.id.uuidString]
            )
            try tx.execute(
                sql: "DELETE FROM credit_cards WHERE account_id = ?",
                parameters: [account.id.uuidString]
            )

            if let bankDetails {
                try tx.execute(
                    sql: Self.insertBankSQL,
                    parameters: Self.insertBankParams(bankDetails)
                )
            }
            if let creditCardDetails {
                try tx.execute(
                    sql: Self.insertCardSQL,
                    parameters: Self.insertCardParams(creditCardDetails)
                )
                let cycleChanged = previousCardDetails.map {
                    $0.statementClosingDay != creditCardDetails.statementClosingDay
                        || $0.paymentDueDay != creditCardDetails.paymentDueDay
                } ?? true
                if cycleChanged {
                    let effectiveFrom = cycleEffectiveFrom
                        ?? Self.nextCycleStart(
                            details: previousCardDetails ?? creditCardDetails,
                            referenceDate: account.updatedAt
                        )
                    try tx.execute(
                        sql: """
                        DELETE FROM credit_card_cycle_configs
                        WHERE account_id = ? AND effective_from >= ?
                        """,
                        parameters: [
                            account.id.uuidString,
                            Converters.dateToString(effectiveFrom),
                        ]
                    )
                    try tx.execute(
                        sql: Self.insertCycleConfigSQL,
                        parameters: Self.insertCycleConfigParams(
                            CreditCardCycleConfig(
                                id: UUID(),
                                accountId: account.id,
                                effectiveFrom: effectiveFrom,
                                statementClosingDay: creditCardDetails.statementClosingDay,
                                paymentDueDay: creditCardDetails.paymentDueDay,
                                createdAt: account.updatedAt
                            )
                        )
                    )
                    try StatementProjector.rebuild(accountId: account.id, in: tx)
                }
            } else if previousCardDetails != nil {
                try tx.execute(
                    sql: "DELETE FROM credit_card_cycle_configs WHERE account_id = ?",
                    parameters: [account.id.uuidString]
                )
            }
        }
    }

    /// DELETE em cascata: apaga `bank_accounts` e `credit_cards` da conta
    /// junto, mesmo que só um esteja presente (delete IS NULL-safe via match
    /// pelo `account_id`).
    func delete(id: UUID) async throws {
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: "DELETE FROM bank_accounts WHERE account_id = ?",
                parameters: [id.uuidString]
            )
            try tx.execute(
                sql: "DELETE FROM credit_cards WHERE account_id = ?",
                parameters: [id.uuidString]
            )
            try tx.execute(
                sql: "DELETE FROM credit_card_cycle_configs WHERE account_id = ?",
                parameters: [id.uuidString]
            )
            try tx.execute(
                sql: "DELETE FROM accounts WHERE id = ?",
                parameters: [id.uuidString]
            )
        }
    }

    // MARK: - Queries

    /// Identidade bancária: usa a tripla (instituição, agência, número) pra
    /// localizar uma conta existente quando um OFX traz dados de banco. Faz
    /// JOIN com `bank_accounts` (a partir da Fase 4.6, os campos saíram de
    /// `accounts` pra cá). Retorna `nil` se qualquer parte não bater.
    func findByBankIdentity(
        institutionId: UUID,
        branchId: String?,
        accountNumber: String
    ) async throws -> Account? {
        // Comparação de `branch_id` precisa ser `IS NULL`-safe — alguns OFX
        // não trazem agência. Usamos `(b.branch_id = ? OR (b.branch_id IS NULL AND ? IS NULL))`.
        try await db.getOptional(
            sql: """
            SELECT a.* FROM accounts a
            JOIN bank_accounts b ON b.account_id = a.id
            WHERE a.institution_id = ?
              AND b.account_number = ?
              AND (b.branch_id = ? OR (b.branch_id IS NULL AND ? IS NULL))
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
            ORDER BY type ASC, institution_id ASC, created_at ASC
            """,
            parameters: [],
            mapper: Self.mapAccount
        )
    }

    func getAllBankDetails() async throws -> [BankAccountDetails] {
        try await db.getAll(
            sql: "SELECT * FROM bank_accounts",
            parameters: [],
            mapper: Self.mapBankDetails
        )
    }

    func getAllCreditCardDetails() async throws -> [CreditCardDetails] {
        try await db.getAll(
            sql: "SELECT * FROM credit_cards",
            parameters: [],
            mapper: Self.mapCardDetails
        )
    }

    func bankDetails(for accountId: UUID) async throws -> BankAccountDetails? {
        try await db.getOptional(
            sql: "SELECT * FROM bank_accounts WHERE account_id = ? LIMIT 1",
            parameters: [accountId.uuidString],
            mapper: Self.mapBankDetails
        )
    }

    func creditCardDetails(for accountId: UUID) async throws -> CreditCardDetails? {
        try await db.getOptional(
            sql: "SELECT * FROM credit_cards WHERE account_id = ? LIMIT 1",
            parameters: [accountId.uuidString],
            mapper: Self.mapCardDetails
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

    // MARK: - Streams

    func watchAll() throws -> AsyncThrowingStream<[Account], Error> {
        try db.watch(
            sql: """
            SELECT * FROM accounts
            ORDER BY type ASC, institution_id ASC, created_at ASC
            """,
            parameters: [],
            mapper: Self.mapAccount
        )
    }

    func watchAllBankDetails() throws -> AsyncThrowingStream<[BankAccountDetails], Error> {
        try db.watch(
            sql: "SELECT * FROM bank_accounts",
            parameters: [],
            mapper: Self.mapBankDetails
        )
    }

    func watchAllCreditCardDetails() throws -> AsyncThrowingStream<[CreditCardDetails], Error> {
        try db.watch(
            sql: "SELECT * FROM credit_cards",
            parameters: [],
            mapper: Self.mapCardDetails
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
                           CASE
                               WHEN t.refund_of_transaction_id IS NOT NULL
                                   THEN t.amount_cents
                               WHEN c.kind = 'income'
                                   THEN t.amount_cents
                               WHEN c.kind = 'expense'
                                   THEN -t.amount_cents
                               WHEN c.kind = 'transfer'
                                   THEN CASE WHEN t.destination_account_id IS NOT NULL
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

    // MARK: - SQL constants

    private nonisolated static let insertAccountSQL = """
    INSERT INTO accounts
        (id, type, initial_balance_cents, archived,
         institution_id, currency, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    private nonisolated static let updateAccountSQL = """
    UPDATE accounts SET
        type = ?, initial_balance_cents = ?, archived = ?,
        institution_id = ?, currency = ?, updated_at = ?
    WHERE id = ?
    """

    private nonisolated static let insertBankSQL = """
    INSERT INTO bank_accounts
        (id, account_id, branch_id, account_number, created_at, updated_at)
    VALUES (uuid(), ?, ?, ?, ?, ?)
    """

    private nonisolated static let insertCardSQL = """
    INSERT INTO credit_cards
        (id, account_id, card_last_four, credit_limit_cents,
         statement_closing_day, payment_due_day, created_at, updated_at)
    VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?)
    """

    private nonisolated static let insertCycleConfigSQL = """
    INSERT INTO credit_card_cycle_configs
        (id, account_id, effective_from, statement_closing_day,
         payment_due_day, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
    """

    private nonisolated static func insertAccountParams(_ account: Account) -> [(any Sendable)?] {
        [
            account.id.uuidString,
            account.type.rawValue,
            Converters.decimalToCents(account.initialBalance),
            account.archived ? 1 : 0,
            account.institutionId?.uuidString,
            account.currency,
            Converters.dateToString(account.createdAt),
            Converters.dateToString(account.updatedAt),
        ]
    }

    private nonisolated static func updateAccountParams(_ account: Account) -> [(any Sendable)?] {
        [
            account.type.rawValue,
            Converters.decimalToCents(account.initialBalance),
            account.archived ? 1 : 0,
            account.institutionId?.uuidString,
            account.currency,
            Converters.dateToString(account.updatedAt),
            account.id.uuidString,
        ]
    }

    private nonisolated static func insertBankParams(_ details: BankAccountDetails) -> [(any Sendable)?] {
        [
            details.accountId.uuidString,
            details.branchId,
            details.accountNumber,
            Converters.dateToString(details.createdAt),
            Converters.dateToString(details.updatedAt),
        ]
    }

    private nonisolated static func insertCardParams(_ details: CreditCardDetails) -> [(any Sendable)?] {
        [
            details.accountId.uuidString,
            details.cardLastFour,
            details.creditLimit.map { Converters.decimalToCents($0) },
            Int64(details.statementClosingDay),
            Int64(details.paymentDueDay),
            Converters.dateToString(details.createdAt),
            Converters.dateToString(details.updatedAt),
        ]
    }

    private nonisolated static func insertCycleConfigParams(
        _ config: CreditCardCycleConfig
    ) -> [(any Sendable)?] {
        [
            config.id.uuidString,
            config.accountId.uuidString,
            Converters.dateToString(config.effectiveFrom),
            Int64(config.statementClosingDay),
            Int64(config.paymentDueDay),
            Converters.dateToString(config.createdAt),
        ]
    }

    private nonisolated static func nextCycleStart(
        details: CreditCardDetails,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let window = StatementWindow.resolve(
            closingDay: details.statementClosingDay,
            paymentDueDay: details.paymentDueDay,
            on: referenceDate,
            calendar: calendar
        )
        return calendar.date(byAdding: .day, value: 1, to: window.closingDate)
            ?? window.closingDate
    }

    // MARK: - Mappers

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

        let currency = try (cursor.getStringOptional(name: "currency")) ?? "BRL"

        return try Account(
            id: id,
            type: type,
            initialBalance: Converters.centsToDecimal(
                cursor.getInt64(name: "initial_balance_cents")
            ),
            archived: (cursor.getInt64(name: "archived")) != 0,
            institutionId: institutionId,
            currency: currency,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private nonisolated static func mapBankDetails(_ cursor: SqlCursor) throws -> BankAccountDetails {
        let accountIdStr = try cursor.getString(name: "account_id")
        guard let accountId = UUID(uuidString: accountIdStr) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: accountIdStr)
        }

        let createdAtStr = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtStr) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtStr)
        }
        let updatedAtStr = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtStr) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtStr)
        }

        return try BankAccountDetails(
            accountId: accountId,
            branchId: cursor.getStringOptional(name: "branch_id"),
            accountNumber: cursor.getString(name: "account_number"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private nonisolated static func mapCardDetails(_ cursor: SqlCursor) throws -> CreditCardDetails {
        let accountIdStr = try cursor.getString(name: "account_id")
        guard let accountId = UUID(uuidString: accountIdStr) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: accountIdStr)
        }

        let createdAtStr = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtStr) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtStr)
        }
        let updatedAtStr = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtStr) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtStr)
        }

        let limit: Decimal? = try cursor.getInt64Optional(name: "credit_limit_cents")
            .map { Converters.centsToDecimal($0) }

        return try CreditCardDetails(
            accountId: accountId,
            cardLastFour: cursor.getString(name: "card_last_four"),
            creditLimit: limit,
            statementClosingDay: Int(cursor.getInt64(name: "statement_closing_day")),
            paymentDueDay: Int(cursor.getInt64(name: "payment_due_day")),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
