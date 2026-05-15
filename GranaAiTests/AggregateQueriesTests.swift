import Foundation
import PowerSync
import Testing
@testable import GranaAi

/// Testes de integração das queries de agregação. Cada teste cria seu próprio
/// banco `:memory:` — banco some quando a instância é desalocada.
@Suite("TransactionRepository (agregações in-memory)")
struct AggregateQueriesTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    /// Insere uma categoria raiz pra usar como FK nas transactions de teste.
    /// Reaproveita o `CategoryRepository` em vez de SQL inline.
    // `Category` colide com `objc.Category` no target de testes — qualificar.
    @discardableResult
    private func seedCategory(
        _ categories: CategoryRepository,
        name: String,
        kind: CategoryKind,
        slug: String? = nil
    ) async throws -> GranaAi.Category {
        let category = GranaAi.Category(
            id: UUID(),
            parentId: nil,
            name: name,
            kind: kind,
            slug: slug,
            createdAt: Date()
        )
        try await categories.insert(category)
        return category
    }

    private func tx(
        accountId: UUID = UUID(),
        categoryId: UUID,
        amount: Decimal,
        occurredAt: Date,
        description: String = "test"
    ) -> GranaAi.Transaction {
        let now = Date()
        return GranaAi.Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: nil,
            amount: amount,
            occurredAt: occurredAt,
            description: description,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Constrói datas determinísticas (UTC) pros casos de borda.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        DateComponents(
            calendar: cal,
            year: y, month: m, day: d, hour: h
        ).date!
    }

    // MARK: - sum

    @Test("sum(.expense) retorna a soma de despesas no período")
    func sumExpenses() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)
        let cats = CategoryRepository(db: db)

        let food   = try await seedCategory(cats, name: "Alimentação", kind: .expense, slug: "alimentacao-e-supermercado")
        let salary = try await seedCategory(cats, name: "Salário",     kind: .income,  slug: "renda-e-pagamentos")

        let march10 = date(2026, 3, 10)
        let march20 = date(2026, 3, 20)
        let april5  = date(2026, 4, 5)

        try await txs.insert(tx(categoryId: food.id,   amount: 100,  occurredAt: march10))
        try await txs.insert(tx(categoryId: food.id,   amount: 50,   occurredAt: march20))
        try await txs.insert(tx(categoryId: food.id,   amount: 999,  occurredAt: april5))  // fora do período
        try await txs.insert(tx(categoryId: salary.id, amount: 5000, occurredAt: march10)) // outro kind

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )

        let total = try await txs.sum(kind: .expense, from: from, to: to)
        #expect(total == 150)

        try await db.close()
    }

    @Test("sum em período vazio retorna 0 (coalesce NULL → 0)")
    func sumEmpty() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )
        let total = try await txs.sum(kind: .expense, from: from, to: to)
        #expect(total == 0)

        try await db.close()
    }

    // MARK: - totalsByCategory

    @Test("totalsByCategory agrupa por raiz e ordena desc")
    func totalsByCategoryOrdered() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)
        let cats = CategoryRepository(db: db)

        let food      = try await seedCategory(cats, name: "Alimentação", kind: .expense, slug: "alimentacao-e-supermercado")
        let transport = try await seedCategory(cats, name: "Transporte",  kind: .expense, slug: "transporte-e-viagem")
        let leisure   = try await seedCategory(cats, name: "Lazer",       kind: .expense, slug: "entretenimento-e-lazer")

        let day = date(2026, 3, 10)

        // Alimentação: 100 + 200 = 300 (maior)
        try await txs.insert(tx(categoryId: food.id,      amount: 100, occurredAt: day))
        try await txs.insert(tx(categoryId: food.id,      amount: 200, occurredAt: day))
        // Transporte: 80
        try await txs.insert(tx(categoryId: transport.id, amount: 80,  occurredAt: day))
        // Lazer: 150 (segunda posição)
        try await txs.insert(tx(categoryId: leisure.id,   amount: 150, occurredAt: day))

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )

        let result = try await txs.totalsByCategory(kind: .expense, from: from, to: to)
        #expect(result.count == 3)
        #expect(result[0].categoryName == "Alimentação")
        #expect(result[0].total == 300)
        #expect(result[0].icon == .utensils)
        #expect(result[1].categoryName == "Lazer")
        #expect(result[1].total == 150)
        #expect(result[2].categoryName == "Transporte")
        #expect(result[2].total == 80)

        try await db.close()
    }

    @Test("totalsByCategory em período vazio retorna []")
    func totalsByCategoryEmpty() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )
        let result = try await txs.totalsByCategory(kind: .expense, from: from, to: to)
        #expect(result.isEmpty)

        try await db.close()
    }

    // MARK: - weekdayTotals

    @Test("weekdayTotals agrupa por dia da semana (mesma quarta soma, ocorrências contam)")
    func weekdayTotalsGroupsByWeekday() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)
        let cats = CategoryRepository(db: db)

        let food = try await seedCategory(cats, name: "Alimentação", kind: .expense, slug: "alimentacao-e-supermercado")

        // Calendar.weekday: 2 = segunda, 4 = quarta, 6 = sexta.
        // Março/2026: 02 = seg, 04 = qua, 09 = seg, 11 = qua, 13 = sex.
        try await txs.insert(tx(categoryId: food.id, amount: 50,  occurredAt: date(2026, 3,  2, 12))) // seg
        try await txs.insert(tx(categoryId: food.id, amount: 30,  occurredAt: date(2026, 3,  9, 12))) // seg
        try await txs.insert(tx(categoryId: food.id, amount: 100, occurredAt: date(2026, 3,  4, 12))) // qua
        try await txs.insert(tx(categoryId: food.id, amount: 25,  occurredAt: date(2026, 3, 11, 12))) // qua
        try await txs.insert(tx(categoryId: food.id, amount: 200, occurredAt: date(2026, 3, 13, 12))) // sex

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )

        let result = try await txs.weekdayTotals(kind: .expense, from: from, to: to)
        // Sem dias da semana zerados — só os 3 que aparecem.
        #expect(result.count == 3)
        // Ordem asc pelo Calendar.weekday: 2 (seg), 4 (qua), 6 (sex).
        let dict = Dictionary(uniqueKeysWithValues: result.map { ($0.weekday, $0) })
        #expect(dict[2]?.total == 80)   // seg: 50 + 30
        #expect(dict[2]?.count == 2)
        #expect(dict[4]?.total == 125)  // qua: 100 + 25
        #expect(dict[4]?.count == 2)
        #expect(dict[6]?.total == 200)  // sex: 200
        #expect(dict[6]?.count == 1)

        try await db.close()
    }

    @Test("weekdayTotals em período vazio retorna []")
    func weekdayTotalsEmpty() async throws {
        let db = makeDatabase()
        let txs = TransactionRepository(db: db)

        let (from, to) = PeriodFilter.currentMonth.dateRange(
            calendar: cal,
            today: date(2026, 3, 15)
        )
        let result = try await txs.weekdayTotals(kind: .expense, from: from, to: to)
        #expect(result.isEmpty)

        try await db.close()
    }
}

@Suite("AccountRepository.sumInitialBalance")
struct AccountSumTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("sumInitialBalance ignora contas arquivadas")
    func sumIgnoresArchived() async throws {
        let db = makeDatabase()
        let accounts = AccountRepository(db: db)

        let now = Date()
        try await accounts.insert(Account(
            id: UUID(), name: "Carteira", type: .wallet,
            initialBalance: 100, archived: false,
            createdAt: now, updatedAt: now
        ))
        try await accounts.insert(Account(
            id: UUID(), name: "Conta Corrente", type: .checking,
            initialBalance: 500, archived: false,
            createdAt: now, updatedAt: now
        ))
        try await accounts.insert(Account(
            id: UUID(), name: "Conta Antiga", type: .checking,
            initialBalance: 9999, archived: true,  // arquivada — NÃO entra
            createdAt: now, updatedAt: now
        ))

        let total = try await accounts.sumInitialBalance()
        #expect(total == 600)

        try await db.close()
    }

    @Test("sumInitialBalance retorna 0 em banco vazio")
    func sumEmpty() async throws {
        let db = makeDatabase()
        let accounts = AccountRepository(db: db)

        let total = try await accounts.sumInitialBalance()
        #expect(total == 0)

        try await db.close()
    }
}
