import Foundation
import PowerSync
import Testing
@testable import GranaAi

@Suite("InstitutionRepository (in-memory)")
struct InstitutionRepositoryTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("Insert + findByCode")
    func insertAndFindByCode() async throws {
        let db = makeDatabase()
        let repo = InstitutionRepository(db: db)

        let now = Date()
        let inter = Institution(
            id: UUID(), code: "077", name: "Banco Inter",
            kind: .inter, createdAt: now, updatedAt: now
        )
        try await repo.insert(inter)

        let fetched = try await repo.findByCode("077")
        try #require(fetched != nil)
        #expect(fetched?.id == inter.id)
        #expect(fetched?.kind == .inter)

        let missing = try await repo.findByCode("999")
        #expect(missing == nil)

        try await db.close()
    }

    @Test("InstitutionKind.fromCode resolve Inter")
    func kindFromCode() {
        #expect(InstitutionKind.fromCode("077") == .inter)
        #expect(InstitutionKind.fromCode(" 077 ") == .inter)   // tolera whitespace
        #expect(InstitutionKind.fromCode("341") == .other)
    }
}

@Suite("AccountRepository.findByBankIdentity")
struct AccountRepositoryBankIdentityTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("Match exato por institution + branch + account")
    func exactMatch() async throws {
        let db = makeDatabase()
        let repo = AccountRepository(db: db)

        let instId = UUID()
        let now = Date()
        let account = Account(
            id: UUID(),
            name: "Inter principal",
            type: .checking,
            initialBalance: 0,
            archived: false,
            institutionId: instId,
            branchId: "0001-9",
            accountNumber: "310013887",
            currency: "BRL",
            createdAt: now,
            updatedAt: now
        )
        try await repo.insert(account)

        let found = try await repo.findByBankIdentity(
            institutionId: instId,
            branchId: "0001-9",
            accountNumber: "310013887"
        )
        try #require(found != nil)
        #expect(found?.id == account.id)

        try await db.close()
    }

    @Test("Não match com número de conta diferente")
    func noMatchDifferentNumber() async throws {
        let db = makeDatabase()
        let repo = AccountRepository(db: db)

        let instId = UUID()
        let now = Date()
        try await repo.insert(Account(
            id: UUID(), name: "X", type: .checking, initialBalance: 0,
            archived: false, institutionId: instId, branchId: "0001",
            accountNumber: "111", currency: "BRL",
            createdAt: now, updatedAt: now
        ))

        let found = try await repo.findByBankIdentity(
            institutionId: instId, branchId: "0001", accountNumber: "222"
        )
        #expect(found == nil)

        try await db.close()
    }

    @Test("branchId NULL bate com branchId NULL na query")
    func nullBranchMatches() async throws {
        let db = makeDatabase()
        let repo = AccountRepository(db: db)

        let instId = UUID()
        let now = Date()
        try await repo.insert(Account(
            id: UUID(), name: "X", type: .checking, initialBalance: 0,
            archived: false, institutionId: instId,
            branchId: nil, accountNumber: "333", currency: "BRL",
            createdAt: now, updatedAt: now
        ))

        let found = try await repo.findByBankIdentity(
            institutionId: instId, branchId: nil, accountNumber: "333"
        )
        try #require(found != nil)
        #expect(found?.accountNumber == "333")

        try await db.close()
    }
}

@Suite("TransactionRepository.insertMultipleBatches + findByExternalId")
struct TransactionRepositoryOFXTests {

    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
    }

    @Test("insertMultipleBatches grava instituições, contas e batches atomicamente")
    func multiBatchAtomic() async throws {
        let db = makeDatabase()
        let txRepo = TransactionRepository(db: db)
        let acctRepo = AccountRepository(db: db)
        let instRepo = InstitutionRepository(db: db)
        let batchRepo = ImportBatchRepository(db: db)

        let categoryId = UUID()
        let instId = UUID()
        let accountId1 = UUID()
        let accountId2 = UUID()
        let now = Date()

        let institution = Institution(
            id: instId, code: "077", name: "Inter", kind: .inter,
            createdAt: now, updatedAt: now
        )
        let acc1 = Account(
            id: accountId1, name: "Conta 1", type: .checking, initialBalance: 0,
            archived: false, institutionId: instId, branchId: "0001", accountNumber: "111",
            currency: "BRL", createdAt: now, updatedAt: now
        )
        let acc2 = Account(
            id: accountId2, name: "Conta 2", type: .savings, initialBalance: 0,
            archived: false, institutionId: instId, branchId: "0001", accountNumber: "222",
            currency: "BRL", createdAt: now, updatedAt: now
        )

        let batch1 = ImportBatch(
            id: UUID(), sourceFilename: "f.ofx", sourceKind: .ofx,
            templateId: nil, accountId: accountId1, rowCount: 1,
            importedAt: now, createdAt: now, updatedAt: now
        )
        let tx1 = GranaAi.Transaction(
            id: UUID(), accountId: accountId1, categoryId: categoryId,
            subcategoryId: nil, amount: 10, occurredAt: now,
            description: "t1", notes: nil,
            importBatchId: batch1.id, externalId: "FIT-1",
            createdAt: now, updatedAt: now
        )
        let batch2 = ImportBatch(
            id: UUID(), sourceFilename: "f.ofx", sourceKind: .ofx,
            templateId: nil, accountId: accountId2, rowCount: 1,
            importedAt: now, createdAt: now, updatedAt: now
        )
        let tx2 = GranaAi.Transaction(
            id: UUID(), accountId: accountId2, categoryId: categoryId,
            subcategoryId: nil, amount: -20, occurredAt: now,
            description: "t2", notes: nil,
            importBatchId: batch2.id, externalId: "FIT-2",
            createdAt: now, updatedAt: now
        )

        try await txRepo.insertMultipleBatches(
            institutions: [institution],
            accounts: [acc1, acc2],
            batchesWithTransactions: [(batch1, [tx1]), (batch2, [tx2])]
        )

        #expect(try await instRepo.findByCode("077") != nil)
        #expect(try await acctRepo.getAll().count == 2)
        #expect(try await batchRepo.getAll().count == 2)
        #expect(try await txRepo.getAll().count == 2)

        try await db.close()
    }

    @Test("findByExternalId acha duplicata exata FITID + conta")
    func findExternalDuplicate() async throws {
        let db = makeDatabase()
        let repo = TransactionRepository(db: db)

        let accountId = UUID()
        let categoryId = UUID()
        let now = Date()
        let tx = GranaAi.Transaction(
            id: UUID(), accountId: accountId, categoryId: categoryId,
            subcategoryId: nil, amount: 1, occurredAt: now,
            description: "x", notes: nil,
            importBatchId: nil, externalId: "FIT-XYZ",
            createdAt: now, updatedAt: now
        )
        try await repo.insert(tx)

        let dup = try await repo.findByExternalId(accountId: accountId, externalId: "FIT-XYZ")
        try #require(dup != nil)
        #expect(dup?.id == tx.id)

        // Mesma FITID mas conta diferente — não bate.
        let otherAccount = try await repo.findByExternalId(accountId: UUID(), externalId: "FIT-XYZ")
        #expect(otherAccount == nil)

        // FITID diferente — não bate.
        let otherId = try await repo.findByExternalId(accountId: accountId, externalId: "FIT-ABC")
        #expect(otherId == nil)

        try await db.close()
    }
}
