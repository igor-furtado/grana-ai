import Foundation
import PowerSync
import Testing
@testable import GranaAi

@Suite("ImportBatchRepository (in-memory)")
struct ImportBatchRepositoryTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    private func sampleBatch(
        accountId: UUID = UUID(),
        rowCount: Int = 3
    ) -> ImportBatch {
        let now = Date()
        return ImportBatch(
            id: UUID(),
            sourceFilename: "extrato.csv",
            sourceKind: .csv,
            templateId: nil,
            accountId: accountId,
            rowCount: rowCount,
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    private func sampleTransaction(
        accountId: UUID,
        categoryId: UUID,
        batchId: UUID,
        amount: Decimal = 10
    ) -> GranaAi.Transaction {
        let now = Date()
        return GranaAi.Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: nil,
            amount: amount,
            occurredAt: now,
            description: "import row",
            notes: nil,
            importBatchId: batchId,
            createdAt: now,
            updatedAt: now
        )
    }

    @Test("Insert + getById roundtrip")
    func insertAndGetById() async throws {
        let db = makeDatabase()
        let repo = ImportBatchRepository(db: db)

        let batch = sampleBatch()
        try await repo.insert(batch)

        let fetched = try await repo.getById(batch.id)
        try #require(fetched != nil)
        #expect(fetched?.id == batch.id)
        #expect(fetched?.sourceFilename == "extrato.csv")
        #expect(fetched?.sourceKind == .csv)
        #expect(fetched?.rowCount == 3)

        try await db.close()
    }

    @Test("Delete apaga batch e transactions associadas (cascade)")
    func deleteCascades() async throws {
        let db = makeDatabase()
        let batchRepo = ImportBatchRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let accountId = UUID()
        let categoryId = UUID()
        let batch = sampleBatch(accountId: accountId, rowCount: 2)
        try await batchRepo.insert(batch)

        let t1 = sampleTransaction(accountId: accountId, categoryId: categoryId, batchId: batch.id)
        let t2 = sampleTransaction(accountId: accountId, categoryId: categoryId, batchId: batch.id)
        try await txRepo.insert(t1)
        try await txRepo.insert(t2)

        // Sanity: transactions estão lá e linkadas ao batch.
        let all = try await txRepo.getAll()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.importBatchId == batch.id })

        // Apaga o batch — transactions devem sumir junto.
        try await batchRepo.delete(id: batch.id)

        #expect(try await batchRepo.getById(batch.id) == nil)
        #expect(try await txRepo.getAll().isEmpty)

        try await db.close()
    }

    @Test("Delete NÃO mexe em transactions manuais (sem batch)")
    func deleteIsolatedFromManualTransactions() async throws {
        let db = makeDatabase()
        let batchRepo = ImportBatchRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let accountId = UUID()
        let categoryId = UUID()
        let batch = sampleBatch(accountId: accountId, rowCount: 1)
        try await batchRepo.insert(batch)

        let imported = sampleTransaction(accountId: accountId, categoryId: categoryId, batchId: batch.id)
        try await txRepo.insert(imported)

        // Transaction manual: import_batch_id == nil.
        let now = Date()
        let manual = GranaAi.Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: nil,
            amount: 50,
            occurredAt: now,
            description: "compra manual",
            notes: nil,
            importBatchId: nil,
            createdAt: now,
            updatedAt: now
        )
        try await txRepo.insert(manual)

        try await batchRepo.delete(id: batch.id)

        let remaining = try await txRepo.getAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == manual.id)
        #expect(remaining.first?.importBatchId == nil)

        try await db.close()
    }
}

@Suite("TransactionRepository.insertBatch + findPotentialDuplicates")
struct TransactionRepositoryImportTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("insertBatch grava batch + N transactions atomicamente")
    func insertBatchAtomic() async throws {
        let db = makeDatabase()
        let txRepo = TransactionRepository(db: db)
        let batchRepo = ImportBatchRepository(db: db)

        let accountId = UUID()
        let categoryId = UUID()
        let batchId = UUID()
        let now = Date()

        let batch = ImportBatch(
            id: batchId,
            sourceFilename: "itau.xlsx",
            sourceKind: .xlsx,
            templateId: nil,
            accountId: accountId,
            rowCount: 3,
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )

        let transactions: [GranaAi.Transaction] = (0..<3).map { i in
            GranaAi.Transaction(
                id: UUID(),
                accountId: accountId,
                categoryId: categoryId,
                subcategoryId: nil,
                amount: Decimal(i + 1) * 10,
                occurredAt: now,
                description: "linha \(i)",
                notes: nil,
                importBatchId: batchId,
                createdAt: now,
                updatedAt: now
            )
        }

        try await txRepo.insertBatch(transactions, batch: batch)

        #expect(try await batchRepo.getById(batchId) != nil)
        let stored = try await txRepo.getAll()
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.importBatchId == batchId })

        try await db.close()
    }

    @Test("findPotentialDuplicates retorna match exato mesmo dia + valor + descrição")
    func findDuplicatesMatch() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        let accountId = UUID()
        let categoryId = UUID()

        // Calendário SP fixo (injetado em `findPotentialDuplicates`) pra que
        // o teste rode determinístico independente do fuso da máquina de CI.
        // O ponto deste teste é exatamente comparação por dia LOCAL — não
        // pelo dia UTC do timestamp.
        var spCalendar = Calendar(identifier: .gregorian)
        spCalendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!

        var components = DateComponents(
            calendar: spCalendar,
            timeZone: TimeZone(identifier: "America/Sao_Paulo"),
            year: 2026, month: 3, day: 15, hour: 10, minute: 0
        )
        let morning = components.date!
        components.hour = 23
        components.minute = 30
        let nightSameDay = components.date!
        components.day = 16
        let nextDay = components.date!

        // Existing transaction às 10h.
        let existing = GranaAi.Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: nil,
            amount: Decimal(string: "123.45")!,
            occurredAt: morning,
            description: "Mercado XYZ",
            notes: nil,
            importBatchId: nil,
            createdAt: morning,
            updatedAt: morning
        )
        try await repo.insert(existing)

        // Mesmo dia, mesmo valor, mesma descrição → match.
        let amountCents = Converters.decimalToCents(Decimal(string: "123.45")!)
        let matches = try await repo.findPotentialDuplicates(
            date: nightSameDay,
            amountCents: amountCents,
            description: "mercado xyz", // case-insensitive
            calendar: spCalendar
        )
        #expect(matches.count == 1)
        #expect(matches.first?.id == existing.id)

        // Dia diferente → não match.
        let otherDay = try await repo.findPotentialDuplicates(
            date: nextDay,
            amountCents: amountCents,
            description: "Mercado XYZ",
            calendar: spCalendar
        )
        #expect(otherDay.isEmpty)

        // Valor diferente → não match.
        let otherAmount = try await repo.findPotentialDuplicates(
            date: morning,
            amountCents: amountCents + 1,
            description: "Mercado XYZ",
            calendar: spCalendar
        )
        #expect(otherAmount.isEmpty)

        // Descrição diferente → não match.
        let otherDesc = try await repo.findPotentialDuplicates(
            date: morning,
            amountCents: amountCents,
            description: "Mercado ABC",
            calendar: spCalendar
        )
        #expect(otherDesc.isEmpty)

        try await db.close()
    }
}

@Suite("ImportTemplateRepository (in-memory)")
struct ImportTemplateRepositoryTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("Insert + getByName roundtrip preserva mapping JSON")
    func roundtrip() async throws {
        let db = makeDatabase()
        let repo = ImportTemplateRepository(db: db)

        let now = Date()
        let mapping = ColumnMapping(
            date: 0, description: 1, amount: nil,
            debit: 2, credit: 3, notes: nil,
            headerRowsToSkip: 1
        )
        let template = ImportTemplate(
            id: UUID(),
            name: "Itaú PJ",
            sourceKind: .xlsx,
            mapping: mapping,
            dateFormat: "dd/MM/yyyy",
            decimalSeparator: ",",
            defaultAccountId: nil,
            createdAt: now,
            updatedAt: now
        )
        try await repo.insert(template)

        let fetched = try await repo.getByName("Itaú PJ")
        try #require(fetched != nil)
        #expect(fetched?.mapping.date == 0)
        #expect(fetched?.mapping.debit == 2)
        #expect(fetched?.mapping.credit == 3)
        #expect(fetched?.mapping.amount == nil)
        #expect(fetched?.dateFormat == "dd/MM/yyyy")
        #expect(fetched?.decimalSeparator == ",")

        try await db.close()
    }
}
