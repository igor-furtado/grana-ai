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
        #expect(InstitutionKind.fromCode(" 077 ") == .inter) // tolera whitespace
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

    /// Cria uma conta corrente com `BankAccountDetails`. A Fase 4.6 dividiu o
    /// schema e o `findByBankIdentity` agora faz JOIN com `bank_accounts` —
    /// inserir só a Account não é suficiente.
    private func makeCheckingAccount(
        in repo: AccountRepository,
        accountId: UUID = UUID(),
        institutionId: UUID,
        branchId: String?,
        accountNumber: String
    ) async throws {
        let now = Date()
        let account = Account(
            id: accountId,
            type: .checking,
            initialBalance: 0,
            archived: false,
            institutionId: institutionId,
            currency: "BRL",
            createdAt: now,
            updatedAt: now
        )
        let details = BankAccountDetails(
            accountId: accountId,
            branchId: branchId,
            accountNumber: accountNumber,
            createdAt: now,
            updatedAt: now
        )
        try await repo.insert(account, bankDetails: details)
    }

    @Test("Match exato por institution + branch + account_number")
    func exactMatch() async throws {
        let db = makeDatabase()
        let repo = AccountRepository(db: db)

        let instId = UUID()
        let accountId = UUID()
        try await makeCheckingAccount(
            in: repo,
            accountId: accountId,
            institutionId: instId,
            branchId: "0001-9",
            accountNumber: "310013887"
        )

        let found = try await repo.findByBankIdentity(
            institutionId: instId,
            branchId: "0001-9",
            accountNumber: "310013887"
        )
        try #require(found != nil)
        #expect(found?.id == accountId)

        try await db.close()
    }

    @Test("Não match com número de conta diferente")
    func noMatchDifferentNumber() async throws {
        let db = makeDatabase()
        let repo = AccountRepository(db: db)

        let instId = UUID()
        try await makeCheckingAccount(
            in: repo, institutionId: instId,
            branchId: "0001", accountNumber: "111"
        )

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
        try await makeCheckingAccount(
            in: repo, institutionId: instId,
            branchId: nil, accountNumber: "333"
        )

        let found = try await repo.findByBankIdentity(
            institutionId: instId, branchId: nil, accountNumber: "333"
        )
        try #require(found != nil)

        let details = try await repo.bankDetails(for: #require(found?.id))
        #expect(details?.accountNumber == "333")

        try await db.close()
    }
}

@Suite("TransactionRepository.findByExternalId")
struct TransactionRepositoryOFXTests {
    private func makeDatabase() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
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
