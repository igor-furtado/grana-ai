import Foundation
import PowerSync

/// Acesso a `transactions`. Encapsula SQL — Views nunca tocam SQL diretamente.
///
/// **Por que mapper é privado static:** o PowerSync exige um closure
/// `@Sendable (SqlCursor) throws -> RowType`. Funções estáticas são
/// trivialmente `Sendable` porque não capturam estado de instância. Manter
/// privado evita que outros módulos dependam do formato exato das colunas.
final class TransactionRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - CRUD

    func insert(_ transaction: Transaction) async throws {
        // Sempre passar `parameters` como `[Sendable?]` — o PowerSync usa
        // prepared statements internamente, então valores nunca vão pra string
        // SQL e SQL injection fica impossível mesmo com input do usuário.
        try await db.execute(
            sql: Self.insertTransactionSQL,
            parameters: Self.insertParameters(for: transaction)
        )
    }

    func update(_ transaction: Transaction) async throws {
        try await db.execute(
            sql: """
                UPDATE transactions SET
                    account_id = ?, category_id = ?, subcategory_id = ?,
                    amount_cents = ?, occurred_at = ?, description = ?,
                    notes = ?, updated_at = ?
                WHERE id = ?
                """,
            parameters: [
                transaction.accountId.uuidString,
                transaction.categoryId.uuidString,
                transaction.subcategoryId?.uuidString,
                Converters.decimalToCents(transaction.amount),
                Converters.dateToString(transaction.occurredAt),
                transaction.description,
                transaction.notes,
                Converters.dateToString(transaction.updatedAt),
                transaction.id.uuidString,
            ]
        )
    }

    func delete(id: UUID) async throws {
        try await db.execute(
            sql: "DELETE FROM transactions WHERE id = ?",
            parameters: [id.uuidString]
        )
    }

    func getById(_ id: UUID) async throws -> Transaction? {
        try await db.getOptional(
            sql: "SELECT * FROM transactions WHERE id = ?",
            parameters: [id.uuidString],
            mapper: Self.mapTransaction
        )
    }

    func getAll() async throws -> [Transaction] {
        try await db.getAll(
            sql: "SELECT * FROM transactions ORDER BY occurred_at DESC",
            parameters: [],
            mapper: Self.mapTransaction
        )
    }

    // MARK: - Reativo (watch)

    /// Retorna `AsyncThrowingStream<[Transaction], Error>` — re-emite sempre
    /// que **qualquer tabela tocada pela query** for modificada (insert /
    /// update / delete). É a base da reatividade da UI: o store consome
    /// essa stream com `for try await` e a View re-renderiza via `@Observable`.
    func watchAll() throws -> AsyncThrowingStream<[Transaction], Error> {
        try db.watch(
            sql: "SELECT * FROM transactions ORDER BY occurred_at DESC",
            parameters: [],
            mapper: Self.mapTransaction
        )
    }

    func watchByAccount(accountId: UUID) throws -> AsyncThrowingStream<[Transaction], Error> {
        try db.watch(
            sql: """
                SELECT * FROM transactions
                WHERE account_id = ?
                ORDER BY occurred_at DESC
                """,
            parameters: [accountId.uuidString],
            mapper: Self.mapTransaction
        )
    }

    func watchByDateRange(from: Date, to: Date) throws -> AsyncThrowingStream<[Transaction], Error> {
        try db.watch(
            sql: """
                SELECT * FROM transactions
                WHERE occurred_at >= ? AND occurred_at <= ?
                ORDER BY occurred_at DESC
                """,
            parameters: [
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: Self.mapTransaction
        )
    }

    // MARK: - Importação em batch (Fase 3)

    /// Insere o `ImportBatch` e todas as `transactions` que pertencem a ele
    /// em **uma única `writeTransaction`**. Atomicidade obrigatória — sem
    /// isso, uma falha no meio deixaria o batch criado sem suas transactions
    /// (ou vice-versa) e o "desfazer batch" não funcionaria.
    func insertBatch(_ transactions: [Transaction], batch: ImportBatch) async throws {
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: """
                    INSERT INTO import_batches
                        (id, source_filename, source_kind, template_id,
                         account_id, row_count, imported_at,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                parameters: [
                    batch.id.uuidString,
                    batch.sourceFilename,
                    batch.sourceKind.rawValue,
                    batch.templateId?.uuidString,
                    batch.accountId.uuidString,
                    Int64(batch.rowCount),
                    Converters.dateToString(batch.importedAt),
                    Converters.dateToString(batch.createdAt),
                    Converters.dateToString(batch.updatedAt),
                ]
            )

            for transaction in transactions {
                try tx.execute(
                    sql: Self.insertTransactionSQL,
                    parameters: Self.insertParameters(for: transaction)
                )
            }
        }
    }

    /// Insere vários batches em uma única `writeTransaction`. Usado pelo
    /// import OFX quando um arquivo traz múltiplos `STMTRS` (uma conta por
    /// statement) — atomicidade: ou todos os batches entram, ou nenhum.
    /// Também grava as `Account`s e `Institution`s novas no mesmo `tx`,
    /// fazendo o auto-create de identidade bancária num único all-or-nothing.
    func insertMultipleBatches(
        institutions: [Institution],
        accounts: [Account],
        batchesWithTransactions: [(batch: ImportBatch, transactions: [Transaction])]
    ) async throws {
        try await db.writeTransaction { tx in
            for institution in institutions {
                try tx.execute(
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

            for account in accounts {
                try tx.execute(
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

            for (batch, transactions) in batchesWithTransactions {
                try tx.execute(
                    sql: """
                        INSERT INTO import_batches
                            (id, source_filename, source_kind, template_id,
                             account_id, row_count, imported_at,
                             created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    parameters: [
                        batch.id.uuidString,
                        batch.sourceFilename,
                        batch.sourceKind.rawValue,
                        batch.templateId?.uuidString,
                        batch.accountId.uuidString,
                        Int64(batch.rowCount),
                        Converters.dateToString(batch.importedAt),
                        Converters.dateToString(batch.createdAt),
                        Converters.dateToString(batch.updatedAt),
                    ]
                )
                for transaction in transactions {
                    try tx.execute(
                        sql: Self.insertTransactionSQL,
                        parameters: Self.insertParameters(for: transaction)
                    )
                }
            }
        }
    }

    /// Detecção de duplicata **exata** via FITID (campo `external_id`). Usado
    /// pelo importer OFX em vez da heurística data+valor+descrição — chave
    /// emitida pelo banco é única por conta, então um `existsByExternal == true`
    /// significa "esta transação já foi importada antes deste mesmo extrato".
    func findByExternalId(
        accountId: UUID,
        externalId: String
    ) async throws -> Transaction? {
        try await db.getOptional(
            sql: """
                SELECT * FROM transactions
                WHERE account_id = ? AND external_id = ?
                LIMIT 1
                """,
            parameters: [accountId.uuidString, externalId],
            mapper: Self.mapTransaction
        )
    }

    /// Versão **batched** do `findByExternalId` — devolve o conjunto de FITIDs
    /// já gravados pra uma conta. Usado no preview de OFX: extratos grandes
    /// têm centenas de transações; consultar uma a uma serializa 500+ idas ao
    /// banco. Uma query + `Set` em Swift é ordem de magnitude mais rápido.
    func externalIds(forAccount accountId: UUID) async throws -> Set<String> {
        let ids: [String] = try await db.getAll(
            sql: """
                SELECT external_id FROM transactions
                WHERE account_id = ? AND external_id IS NOT NULL
                """,
            parameters: [accountId.uuidString],
            mapper: { (cursor: SqlCursor) throws -> String in
                try cursor.getString(name: "external_id")
            }
        )
        return Set(ids)
    }

    /// Match exato de duplicata: mesmo dia (ignorando horário), mesmo valor
    /// em centavos, mesma descrição case-insensitive. Critério intencionalmente
    /// estreito — preferimos perder alguns matches do que reportar falsos
    /// positivos que façam o usuário descartar transações legítimas.
    ///
    /// **Por que não `SUBSTR(occurred_at, 1, 10)`:** o `Converters.iso8601`
    /// serializa em UTC ("Z"), então uma transação às 22h local Brasil
    /// (UTC−3) vira o dia seguinte em UTC. O prefixo `yyyy-MM-dd` do banco
    /// fica fora de fase com o dia local do usuário, fazendo duplicatas
    /// reais escaparem em transações próximas da meia-noite. Solução:
    /// candidatos pela janela `[startOfDay−1d, startOfDay+2d)` no fuso
    /// local (cobre qualquer fuso ±24h sem caso de borda) e filtro
    /// `Calendar.isDate(_:inSameDayAs:)` em memória pra exigir mesmo dia
    /// local. O custo da janela mais larga é desprezível porque
    /// `amount_cents` + `LOWER(description)` já reduzem o resultado a
    /// poucas linhas em qualquer base real.
    ///
    /// **Calendário injetável:** produção usa `Calendar.current` (fuso do
    /// usuário). Testes passam um Calendar com timezone fixo pra evitar
    /// que o resultado dependa do fuso da máquina de CI.
    func findPotentialDuplicates(
        date: Date,
        amountCents: Int64,
        description: String,
        calendar: Calendar = .current
    ) async throws -> [Transaction] {
        let startOfDay = calendar.startOfDay(for: date)
        let windowStart = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: startOfDay) ?? startOfDay

        let candidates: [Transaction] = try await db.getAll(
            sql: """
                SELECT * FROM transactions
                WHERE occurred_at >= ? AND occurred_at < ?
                  AND amount_cents = ?
                  AND LOWER(description) = LOWER(?)
                """,
            parameters: [
                Converters.dateToString(windowStart),
                Converters.dateToString(windowEnd),
                amountCents,
                description,
            ],
            mapper: Self.mapTransaction
        )

        return candidates.filter { calendar.isDate($0.occurredAt, inSameDayAs: date) }
    }

    // MARK: - Agregações (one-shot, NÃO watch)

    // Por que SQL `SUM` / `GROUP BY` em vez de buscar todas as transações e
    // somar em Swift: o SQLite faz a agregação no plano da query e nos devolve
    // só os totais — sem alocar N structs em memória. Pra 10k+ transações é
    // ordem de magnitude mais rápido, e mantém esse caminho viável quando a
    // base crescer.
    //
    // Por que `getAll` (snapshot) em vez de `watch` (stream): o dashboard
    // recalcula on-demand quando o usuário troca o filtro de período. Watch
    // re-emitiria a cada keystroke em qualquer formulário (efeito colateral
    // do invalidation por tabela do PowerSync) — overhead sem benefício aqui.

    /// Soma total de transações de um `kind` no período. Faz JOIN com
    /// `categories` porque `kind` mora lá, não na transaction.
    func sum(kind: CategoryKind, from: Date, to: Date) async throws -> Decimal {
        // `coalesce(SUM, 0)` garante que o caso "0 linhas" devolve 0 em vez
        // de NULL — evita ter que tratar opcional aqui em cima.
        let cents = try await db.get(
            sql: """
                SELECT COALESCE(SUM(t.amount_cents), 0) AS total
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE c.kind = ?
                  AND t.occurred_at >= ?
                  AND t.occurred_at <= ?
                """,
            parameters: [
                kind.rawValue,
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: { (cursor: SqlCursor) throws -> Int64 in
                try cursor.getInt64(name: "total")
            }
        )
        return Converters.centsToDecimal(cents)
    }

    /// Totais por categoria **raiz** no período, ordenados desc por valor.
    /// Como toda transaction aponta direto pra raiz (a UI do form garante),
    /// `GROUP BY category_id` já agrega por raiz — sem self-join com parent.
    func totalsByCategory(
        kind: CategoryKind,
        from: Date,
        to: Date
    ) async throws -> [CategoryTotal] {
        try await db.getAll(
            sql: """
                SELECT c.id AS id, c.name AS name, c.slug AS slug,
                       SUM(t.amount_cents) AS total
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE c.kind = ?
                  AND t.occurred_at >= ?
                  AND t.occurred_at <= ?
                GROUP BY c.id, c.name, c.slug
                ORDER BY total DESC
                """,
            parameters: [
                kind.rawValue,
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: Self.mapCategoryTotal
        )
    }

    /// Totais agrupados por dia da semana no período. Resposta direta pra
    /// "tem dia da semana em que eu gasto mais sistematicamente?".
    ///
    /// **Por que agregar no Swift e não em SQL:** o SQLite tem `strftime('%w')`
    /// mas ele opera **em UTC** sobre a string ISO8601 — uma transação às
    /// 23:30 local (que cai num dia X) seria contada no dia X+1 UTC. Pra
    /// respeitar o fuso do usuário, parseamos a Date no mapper e usamos
    /// `Calendar.component(.weekday)` no fuso local. O volume é pequeno
    /// (30–500 rows mesmo em 12 meses), então o custo extra é desprezível.
    func weekdayTotals(
        kind: CategoryKind,
        from: Date,
        to: Date
    ) async throws -> [WeekdayTotal] {
        let rows: [Occurrence] = try await db.getAll(
            sql: """
                SELECT t.occurred_at  AS occurred_at,
                       t.amount_cents AS amount_cents
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE c.kind = ?
                  AND t.occurred_at >= ?
                  AND t.occurred_at <= ?
                """,
            parameters: [
                kind.rawValue,
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: Self.mapOccurrence
        )

        var buckets: [Int: (total: Decimal, count: Int)] = [:]
        let calendar = Calendar.current
        for row in rows {
            let weekday = calendar.component(.weekday, from: row.occurredAt)
            let prev = buckets[weekday] ?? (.zero, 0)
            buckets[weekday] = (prev.total + row.amount, prev.count + 1)
        }

        return buckets
            .map { WeekdayTotal(weekday: $0.key, total: $0.value.total, count: $0.value.count) }
            .sorted { $0.weekday < $1.weekday }
    }

    /// Totais mensais por categoria raiz no período. Agrupa pela porção
    /// "YYYY-MM" da string ISO8601 — mesmo truque do `dailyTotals`, sem
    /// parsear data por linha. Útil pro gráfico de barras empilhadas
    /// "mês × categoria" rolling 12 meses.
    func monthlyTotalsByCategory(
        kind: CategoryKind,
        from: Date,
        to: Date
    ) async throws -> [MonthlyCategoryTotal] {
        try await db.getAll(
            sql: """
                SELECT SUBSTR(t.occurred_at, 1, 7) AS month,
                       c.id   AS id,
                       c.name AS name,
                       c.slug AS slug,
                       SUM(t.amount_cents) AS total
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE c.kind = ?
                  AND t.occurred_at >= ?
                  AND t.occurred_at <= ?
                GROUP BY month, c.id, c.name, c.slug
                ORDER BY month ASC, total DESC
                """,
            parameters: [
                kind.rawValue,
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: Self.mapMonthlyCategoryTotal
        )
    }

    /// Totais mensais de receita E despesa em uma só query (via `CASE WHEN`).
    /// Alternativa seria duas queries + merge em Swift; o `CASE` agrupa tudo
    /// numa varredura única do banco — mais rápido e mais simples no Store.
    /// Transferências (`kind = .transfer`) NÃO entram — são neutras de saldo.
    func monthlyTotalsByKind(
        from: Date,
        to: Date
    ) async throws -> [MonthlyKindTotal] {
        try await db.getAll(
            sql: """
                SELECT SUBSTR(t.occurred_at, 1, 7) AS month,
                       SUM(CASE WHEN c.kind = 'income'  THEN t.amount_cents ELSE 0 END) AS income,
                       SUM(CASE WHEN c.kind = 'expense' THEN t.amount_cents ELSE 0 END) AS expense
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE c.kind IN ('income', 'expense')
                  AND t.occurred_at >= ?
                  AND t.occurred_at <= ?
                GROUP BY month
                ORDER BY month ASC
                """,
            parameters: [
                Converters.dateToString(from),
                Converters.dateToString(to),
            ],
            mapper: Self.mapMonthlyKindTotal
        )
    }

    // MARK: - SQL + parameters compartilhados

    /// SQL único reutilizado por `insert`, `insertBatch` e
    /// `insertMultipleBatches`. Mudança de schema (coluna nova/removida)
    /// passa a exigir alteração em UM lugar — antes eram 3 cópias e o risco
    /// de divergir uma era real.
    private nonisolated static let insertTransactionSQL = """
        INSERT INTO transactions
            (id, account_id, category_id, subcategory_id,
             amount_cents, occurred_at, description, notes,
             import_batch_id, external_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    /// Parâmetros do `insertTransactionSQL` na ordem das colunas. `nonisolated`
    /// porque é chamado de dentro do closure `@Sendable` de
    /// `writeTransaction` — não pode ser MainActor.
    private nonisolated static func insertParameters(for transaction: Transaction) -> [(any Sendable)?] {
        [
            transaction.id.uuidString,
            transaction.accountId.uuidString,
            transaction.categoryId.uuidString,
            transaction.subcategoryId?.uuidString,
            Converters.decimalToCents(transaction.amount),
            Converters.dateToString(transaction.occurredAt),
            transaction.description,
            transaction.notes,
            transaction.importBatchId?.uuidString,
            transaction.externalId,
            Converters.dateToString(transaction.createdAt),
            Converters.dateToString(transaction.updatedAt),
        ]
    }

    // MARK: - Mapper

    /// Operação atômica futura: ao inserir uma Transaction, também atualizar
    /// `updated_at` da Account associada. Ficaria assim — fora do escopo da
    /// Fase 1, mas serve como referência:
    ///
    /// ```swift
    /// try await db.writeTransaction { tx in
    ///     try tx.execute(sql: "INSERT INTO transactions ...", parameters: [...])
    ///     try tx.execute(sql: "UPDATE accounts SET updated_at = ? WHERE id = ?", parameters: [...])
    /// }
    /// ```
    /// Se o segundo execute lançar, o primeiro é desfeito automaticamente.
    // `nonisolated` porque o PowerSync chama o mapper de fora da MainActor
    // (PowerSync.watch/getAll rodam I/O em background). Sem isso, o default
    // MainActor do target (SWIFT_DEFAULT_ACTOR_ISOLATION) deixaria o método
    // MainActor-isolated e o cast pra `@Sendable` perde isolamento — vira
    // erro em Swift 6.
    private nonisolated static func mapTransaction(_ cursor: SqlCursor) throws -> Transaction {
        let idString = try cursor.getString(name: "id")
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let accountIdString = try cursor.getString(name: "account_id")
        guard let accountId = UUID(uuidString: accountIdString) else {
            throw DatabaseError.invalidUUID(column: "account_id", value: accountIdString)
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

        let cents = try cursor.getInt64(name: "amount_cents")

        let occurredAtString = try cursor.getString(name: "occurred_at")
        guard let occurredAt = Converters.stringToDate(occurredAtString) else {
            throw DatabaseError.invalidDate(column: "occurred_at", value: occurredAtString)
        }

        let description = try cursor.getString(name: "description")
        let notes = try cursor.getStringOptional(name: "notes")

        let importBatchId: UUID?
        if let s = try cursor.getStringOptional(name: "import_batch_id") {
            guard let uuid = UUID(uuidString: s) else {
                throw DatabaseError.invalidUUID(column: "import_batch_id", value: s)
            }
            importBatchId = uuid
        } else {
            importBatchId = nil
        }

        let externalId = try cursor.getStringOptional(name: "external_id")

        let createdAtString = try cursor.getString(name: "created_at")
        guard let createdAt = Converters.stringToDate(createdAtString) else {
            throw DatabaseError.invalidDate(column: "created_at", value: createdAtString)
        }

        let updatedAtString = try cursor.getString(name: "updated_at")
        guard let updatedAt = Converters.stringToDate(updatedAtString) else {
            throw DatabaseError.invalidDate(column: "updated_at", value: updatedAtString)
        }

        return Transaction(
            id: id,
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            amount: Converters.centsToDecimal(cents),
            occurredAt: occurredAt,
            description: description,
            notes: notes,
            importBatchId: importBatchId,
            externalId: externalId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // Mappers de agregado são separados do `mapTransaction` porque leem colunas
    // *computadas* (`total`) e/ou colunas vindas de JOIN (`name`, `slug` da
    // `categories`) — formatos diferentes da row "transaction completa".
    // Manter como funções distintas evita um `if cursor.has(...)` frágil.
    //
    // O ícone não vem do banco: resolve aqui via `CategoryIcon.forSlug` pra
    // que `CategoryTotal` chegue na View já com o ícone pronto (evita
    // segunda viagem). Slug `nil` ou desconhecido → ícone `nil` e a View cai
    // pra cor default.

    private nonisolated static func mapCategoryTotal(_ cursor: SqlCursor) throws -> CategoryTotal {
        let idString = try cursor.getString(name: "id")
        guard let categoryId = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let icon = try cursor.getStringOptional(name: "slug").flatMap(CategoryIcon.forSlug)

        let cents = try cursor.getInt64(name: "total")

        return CategoryTotal(
            categoryId: categoryId,
            categoryName: try cursor.getString(name: "name"),
            icon: icon,
            total: Converters.centsToDecimal(cents)
        )
    }

    /// Linha "mínima" usada por agregações que precisam só de data + valor
    /// (ex: `weekdayTotals`, que computa o dia da semana em Swift).
    private struct Occurrence: Sendable {
        let occurredAt: Date
        let amount: Decimal
    }

    private nonisolated static func mapOccurrence(_ cursor: SqlCursor) throws -> Occurrence {
        let dateString = try cursor.getString(name: "occurred_at")
        guard let occurredAt = Converters.stringToDate(dateString) else {
            throw DatabaseError.invalidDate(column: "occurred_at", value: dateString)
        }
        let cents = try cursor.getInt64(name: "amount_cents")
        return Occurrence(occurredAt: occurredAt, amount: Converters.centsToDecimal(cents))
    }

    private nonisolated static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private nonisolated static func mapMonthlyCategoryTotal(_ cursor: SqlCursor) throws -> MonthlyCategoryTotal {
        let monthString = try cursor.getString(name: "month")
        guard let monthStart = monthFormatter.date(from: monthString) else {
            throw DatabaseError.invalidDate(column: "month", value: monthString)
        }

        let idString = try cursor.getString(name: "id")
        guard let categoryId = UUID(uuidString: idString) else {
            throw DatabaseError.invalidUUID(column: "id", value: idString)
        }

        let icon = try cursor.getStringOptional(name: "slug").flatMap(CategoryIcon.forSlug)

        return MonthlyCategoryTotal(
            monthStart: monthStart,
            categoryId: categoryId,
            categoryName: try cursor.getString(name: "name"),
            icon: icon,
            total: Converters.centsToDecimal(try cursor.getInt64(name: "total"))
        )
    }

    private nonisolated static func mapMonthlyKindTotal(_ cursor: SqlCursor) throws -> MonthlyKindTotal {
        let monthString = try cursor.getString(name: "month")
        guard let monthStart = monthFormatter.date(from: monthString) else {
            throw DatabaseError.invalidDate(column: "month", value: monthString)
        }
        return MonthlyKindTotal(
            monthStart: monthStart,
            income:  Converters.centsToDecimal(try cursor.getInt64(name: "income")),
            expense: Converters.centsToDecimal(try cursor.getInt64(name: "expense"))
        )
    }
}
