import Foundation
import PowerSync
import Testing
@testable import GranaAi

@Suite("StatementWindow")
struct StatementWindowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Ajusta fechamento e vencimento para o último dia do mês")
    func clampsShortMonths() throws {
        let date = try #require(calendar.date(from: DateComponents(
            year: 2024,
            month: 2,
            day: 15
        )))
        let window = StatementWindow.resolve(
            closingDay: 31,
            paymentDueDay: 31,
            on: date,
            calendar: calendar
        )

        #expect(calendar.component(.day, from: window.closingDate) == 29)
        #expect(calendar.component(.day, from: window.dueDate) == 31)
        #expect(calendar.component(.month, from: window.dueDate) == 3)
    }
}

@Suite("Projeção cronológica de faturas")
struct StatementProjectionTests {
    private struct Fixture {
        let db: any PowerSyncDatabaseProtocol
        let transactions: TransactionRepository
        let statements: StatementRepository
        let checkingId: UUID
        let cardId: UUID
        let expenseId: UUID
        let transferId: UUID
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makeFixture() async throws -> Fixture {
        let db = PowerSyncDatabase(
            schema: appSchema,
            dbFilename: ":memory:",
            logger: DefaultLogger()
        )
        let accounts = AccountRepository(db: db)
        let categories = CategoryRepository(db: db)
        let transactions = TransactionRepository(db: db)
        let statements = StatementRepository(db: db)
        let now = date(2025, 1, 1)
        let checkingId = UUID()
        let cardId = UUID()
        let expenseId = UUID()
        let transferId = UUID()

        try await accounts.insert(Account(
            id: checkingId,
            type: .checking,
            initialBalance: 0,
            archived: false,
            createdAt: now,
            updatedAt: now
        ))
        try await accounts.insert(
            Account(
                id: cardId,
                type: .creditCard,
                initialBalance: 0,
                archived: false,
                createdAt: now,
                updatedAt: now
            ),
            creditCardDetails: CreditCardDetails(
                accountId: cardId,
                cardLastFour: "1234",
                creditLimit: nil,
                statementClosingDay: 10,
                paymentDueDay: 20,
                createdAt: now,
                updatedAt: now
            )
        )
        try await categories.insert(Category(
            id: expenseId,
            parentId: nil,
            name: "Compras",
            kind: .expense,
            slug: "shopping",
            createdAt: now
        ))
        try await categories.insert(Category(
            id: transferId,
            parentId: nil,
            name: "Transferências",
            kind: .transfer,
            slug: "transfer",
            createdAt: now
        ))

        return Fixture(
            db: db,
            transactions: transactions,
            statements: statements,
            checkingId: checkingId,
            cardId: cardId,
            expenseId: expenseId,
            transferId: transferId
        )
    }

    private func transaction(
        accountId: UUID,
        categoryId: UUID,
        amount: Decimal,
        occurredAt: Date,
        destinationAccountId: UUID? = nil,
        refundOfTransactionId: UUID? = nil
    ) -> GranaAi.Transaction {
        GranaAi.Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: nil,
            amount: amount,
            occurredAt: occurredAt,
            description: "Teste",
            notes: nil,
            destinationAccountId: destinationAccountId,
            refundOfTransactionId: refundOfTransactionId,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
    }

    @Test("Estorno em junho reduz o ciclo de junho")
    func refundUsesOwnCycle() async throws {
        let fixture = try await makeFixture()
        let purchase = transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 100,
            occurredAt: date(2025, 5, 5)
        )
        try await fixture.transactions.insert(purchase)
        try await fixture.transactions.insert(transaction(
            accountId: fixture.cardId,
            categoryId: fixture.transferId,
            amount: 40,
            occurredAt: date(2025, 6, 5),
            refundOfTransactionId: purchase.id
        ))

        let statements = try await fixture.statements.getAll()
            .sorted { $0.closingDate < $1.closingDate }
        try #require(statements.count == 2)
        #expect(statements[0].netAmount == 100)
        #expect(statements[1].netAmount == -40)

        let refund = try #require(
            try await fixture.transactions.getAll()
                .first(where: { $0.refundOfTransactionId == purchase.id })
        )
        #expect(refund.categoryId == fixture.expenseId)
        try await fixture.db.close()
    }

    @Test("Múltiplos estornos não ultrapassam a compra")
    func refundCannotExceedPurchase() async throws {
        let fixture = try await makeFixture()
        let purchase = transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 100,
            occurredAt: date(2025, 5, 5)
        )
        try await fixture.transactions.insert(purchase)
        try await fixture.transactions.insert(transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 60,
            occurredAt: date(2025, 6, 1),
            refundOfTransactionId: purchase.id
        ))

        await #expect(throws: PowerSyncError.self) {
            try await fixture.transactions.insert(transaction(
                accountId: fixture.cardId,
                categoryId: fixture.expenseId,
                amount: 50,
                occurredAt: date(2025, 6, 2),
                refundOfTransactionId: purchase.id
            ))
        }
        #expect(try await fixture.transactions.getAll().count == 2)
        try await fixture.db.close()
    }

    @Test("Pagamento é dividido entre as dívidas mais antigas")
    func paymentSplitsChronologically() async throws {
        let fixture = try await makeFixture()
        try await fixture.transactions.insert(transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 100,
            occurredAt: date(2025, 4, 5)
        ))
        try await fixture.transactions.insert(transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 100,
            occurredAt: date(2025, 5, 5)
        ))
        let payment = transaction(
            accountId: fixture.checkingId,
            categoryId: fixture.transferId,
            amount: 150,
            occurredAt: date(2025, 5, 20),
            destinationAccountId: fixture.cardId
        )
        try await fixture.transactions.insert(payment)

        let allocations = try await fixture.statements.payments(
            forTransaction: payment.id
        )
        #expect(allocations.count == 2)
        #expect(allocations.map(\.appliedAmount).reduce(0, +) == 150)
        try await fixture.db.close()
    }

    @Test("Pagamento com sobra é rejeitado atomicamente")
    func rejectsUnappliedPayment() async throws {
        let fixture = try await makeFixture()
        try await fixture.transactions.insert(transaction(
            accountId: fixture.cardId,
            categoryId: fixture.expenseId,
            amount: 100,
            occurredAt: date(2025, 5, 5)
        ))

        await #expect(throws: PowerSyncError.self) {
            try await fixture.transactions.insert(transaction(
                accountId: fixture.checkingId,
                categoryId: fixture.transferId,
                amount: 101,
                occurredAt: date(2025, 5, 20),
                destinationAccountId: fixture.cardId
            ))
        }
        #expect(try await fixture.transactions.getAll().count == 1)
        try await fixture.db.close()
    }
}
