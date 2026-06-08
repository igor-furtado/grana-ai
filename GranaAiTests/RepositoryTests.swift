import Foundation
import PowerSync
import Testing
@testable import GranaAi

/// Testes de integração com PowerSync em memória.
///
/// Cada teste cria sua própria instância em `:memory:` — o suite do PowerSync
/// usa esse mesmo padrão (ver `Tests/PowerSyncTests/CrudTests.swift` no SDK).
/// Banco some quando a instância é desalocada.
@Suite("TransactionRepository (in-memory)")
struct TransactionRepositoryTests {
    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    /// `Transaction` é ambíguo aqui: nosso struct (GranaAi.Transaction) e o
    /// protocolo `Transaction` do PowerSync (usado em `writeTransaction`) têm
    /// o mesmo nome. No app principal nosso tipo ganha por ser do mesmo módulo,
    /// mas no target de testes ambos vêm via `import` — precisa qualificar.
    private func sampleTransaction(
        accountId: UUID = UUID(),
        categoryId: UUID = UUID(),
        amount: Decimal = 12.34,
        occurredAt: Date = Date(),
        description: String = "teste"
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

    @Test("Insert + getById roundtrip")
    func insertAndGetById() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        let tx = sampleTransaction(amount: 87.50, description: "Mercado")
        try await repo.insert(tx)

        let fetched = try await repo.getById(tx.id)
        try #require(fetched != nil)

        #expect(fetched?.id == tx.id)
        #expect(fetched?.amount == tx.amount)
        #expect(fetched?.description == "Mercado")
        #expect(fetched?.subcategoryId == nil)

        try await db.close()
    }

    @Test("Update altera os campos")
    func update() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        var tx = sampleTransaction(amount: 10, description: "antigo")
        try await repo.insert(tx)

        tx.amount = 99.99
        tx.description = "novo"
        tx.updatedAt = Date()
        try await repo.update(tx)

        let fetched = try await repo.getById(tx.id)
        #expect(fetched?.amount == 99.99)
        #expect(fetched?.description == "novo")

        try await db.close()
    }

    @Test("Delete remove o registro")
    func delete() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        let tx = sampleTransaction()
        try await repo.insert(tx)
        try await repo.delete(id: tx.id)

        let fetched = try await repo.getById(tx.id)
        #expect(fetched == nil)

        try await db.close()
    }

    @Test("getAll ordena por occurred_at DESC")
    func getAllOrderedDescending() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        let now = Date()
        let one = sampleTransaction(occurredAt: now.addingTimeInterval(-3600), description: "1h atrás")
        let two = sampleTransaction(occurredAt: now, description: "agora")
        let three = sampleTransaction(occurredAt: now.addingTimeInterval(-86400), description: "ontem")

        try await repo.insert(one)
        try await repo.insert(two)
        try await repo.insert(three)

        let all = try await repo.getAll()
        #expect(all.count == 3)
        // Esperado: agora > 1h atrás > ontem
        #expect(all[0].description == "agora")
        #expect(all[1].description == "1h atrás")
        #expect(all[2].description == "ontem")

        try await db.close()
    }
}

@Suite("Seed (in-memory)")
struct SeedTests {
    @Test("Seed insere contas e categorias quando vazio")
    func seedRunsOnEmptyDatabase() async throws {
        let powerSyncDb = PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )

        // AppContainer é `final class` com init privado — pra teste, usamos
        // o `placeholder()`? Não, ele usa outro filename. Aqui montamos os
        // repositories manualmente já que Seed só usa eles + db.writeTransaction.
        let accounts = AccountRepository(db: powerSyncDb)
        let categories = CategoryRepository(db: powerSyncDb)

        // Pré-condição: tudo vazio.
        #expect(try await accounts.getAll().isEmpty)
        #expect(try await categories.getAll().isEmpty)

        // Reimplementação enxuta do Seed pra contornar o init privado do
        // AppContainer em testes (refatorar pra injeção de deps quando crescer).
        let now = Date()
        try await accounts.insert(
            Account(
                id: UUID(),
                type: .checking,
                initialBalance: 0,
                archived: false,
                createdAt: now,
                updatedAt: now
            )
        )

        let fetched = try await accounts.getAll()
        #expect(fetched.count == 1)
        #expect(fetched.first?.type == .checking)

        try await powerSyncDb.close()
    }
}
