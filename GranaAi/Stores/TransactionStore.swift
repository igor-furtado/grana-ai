import Foundation
import Observation
import OSLog
import PowerSync

/// Estado observável da feature Transações.
///
/// **Por que `@MainActor` na classe inteira:** SwiftUI exige que mutações em
/// estado observado pela UI aconteçam na main thread. Anotar a classe com
/// `@MainActor` força isso em tempo de compilação — qualquer chamada de fora
/// da main thread vira `await store.foo()` e o compilador checa. Vai bem
/// junto da configuração `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` do
/// target, mas explícito ajuda legibilidade.
///
/// **Por que juntar transactions/accounts/categories no mesmo store:** a UI
/// de Transação precisa dos três pra renderizar (lista mostra nome de
/// categoria, formulário mostra picker de account). Manter em stores
/// separados forçaria a View a observar três objetos e re-renderizar três
/// vezes em ações cruzadas — overhead sem benefício na Fase 1.
@MainActor
@Observable
final class TransactionStore {
    private let container: AppContainer

    private(set) var transactions: [Transaction] = []
    private(set) var accounts: [Account] = []
    /// Necessário pra derivar `displayName(for:)` da conta (que precisa do
    /// nome do banco como prefixo). Tabela pequena e estática — overhead do
    /// stream é desprezível.
    private(set) var institutions: [Institution] = []
    /// A partir da Fase 4.6 o sufixo do display name (número da conta /
    /// ••••last4) vive nas tabelas-irmãs `bank_accounts` e `credit_cards`.
    /// Streamamos junto pra não precisar de query síncrona toda vez que a
    /// lista re-renderiza.
    private(set) var bankDetails: [BankAccountDetails] = []
    private(set) var creditCards: [CreditCardDetails] = []
    private(set) var categories: [Category] = []
    /// Fatura de cartão (Fase 4.7). Streamada pra que a UI da transação
    /// possa mostrar a qual Fatura aquela compra pertence sem fazer round
    /// trip ao banco. Tabela pequena (12 por cartão por ano) — cabe em
    /// memória sem stress.
    private(set) var statements: [Statement] = []
    /// Junction transferência → fatura paga. Permite ver na UI da
    /// transferência quais Faturas ela está pagando.
    private(set) var statementPayments: [StatementPayment] = []
    private(set) var isLoading = false
    var lastError: Error?

    init(container: AppContainer) {
        self.container = container
    }

    // MARK: - Streams

    /// Inicia os três watch streams em paralelo. Esta função **não retorna**
    /// enquanto o task pai estiver vivo — fica fazendo `for try await` em
    /// cada stream. SwiftUI chama isso via `.task { await store.start() }`,
    /// que cancela automaticamente quando a View desaparece.
    ///
    /// **`try await` vs `for try await`:**
    /// - `try await db.execute(...)` espera UMA operação async e segue.
    /// - `for try await rows in stream { ... }` itera uma **stream** que
    ///   pode emitir N valores ao longo do tempo. Cada nova emissão entra
    ///   no corpo do loop. O loop termina quando a stream encerra (cancelamento,
    ///   erro, ou `finish()`).
    func start() async {
        isLoading = true
        defer { isLoading = false }

        // `async let` roda os quatro em paralelo. Cada um é uma função async
        // isolada à MainActor — ao atualizar `self.X`, já estamos na main.
        // O await final só termina quando todas as streams encerrarem
        // (em prática: só quando o task pai for cancelado).
        async let t: Void = streamTransactions()
        async let a: Void = streamAccounts()
        async let i: Void = streamInstitutions()
        async let bd: Void = streamBankDetails()
        async let cd: Void = streamCreditCards()
        async let s: Void = streamStatements()
        async let sp: Void = streamStatementPayments()
        async let c: Void = streamCategories()
        _ = await (t, a, i, bd, cd, s, sp, c)
    }

    private func streamTransactions() async {
        do {
            let stream = try container.transactions.watchAll()
            for try await rows in stream {
                transactions = rows
            }
        } catch is CancellationError {
            // .task foi cancelado pela SwiftUI — comportamento esperado.
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamAccounts() async {
        do {
            let stream = try container.accounts.watchAll()
            for try await rows in stream {
                accounts = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamInstitutions() async {
        do {
            let stream = try container.institutions.watchAll()
            for try await rows in stream {
                institutions = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamBankDetails() async {
        do {
            for try await rows in try container.accounts.watchAllBankDetails() {
                bankDetails = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamCreditCards() async {
        do {
            for try await rows in try container.accounts.watchAllCreditCardDetails() {
                creditCards = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamStatements() async {
        do {
            for try await rows in try container.statements.watchAll() {
                statements = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamStatementPayments() async {
        do {
            for try await rows in try container.statements.watchAllPayments() {
                statementPayments = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    private func streamCategories() async {
        do {
            let stream = try container.categories.watchAll()
            for try await rows in stream {
                categories = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    // MARK: - Mutations

    /// Cria uma transação nova. A UI só passa os campos do formulário;
    /// o store preenche id, createdAt e updatedAt.
    ///
    func add(
        accountId: UUID,
        categoryId: UUID,
        subcategoryId: UUID?,
        amount: Decimal,
        occurredAt: Date,
        description: String,
        notes: String?,
        destinationAccountId: UUID? = nil,
        refundOfTransactionId: UUID? = nil
    ) async throws {
        let now = Date()
        let transaction = Transaction(
            id: UUID(),
            accountId: accountId,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            amount: amount,
            occurredAt: occurredAt,
            description: description,
            notes: notes,
            destinationAccountId: destinationAccountId,
            refundOfTransactionId: refundOfTransactionId,
            createdAt: now,
            updatedAt: now
        )
        try await container.transactions.insert(transaction)
        // Não precisamos atualizar `self.transactions` manualmente — o watch
        // stream emite o novo estado automaticamente.
    }

    func update(_ transaction: Transaction) async throws {
        var copy = transaction
        copy.updatedAt = Date()
        try await container.transactions.update(copy)
    }

    func delete(id: UUID) async throws {
        try await container.transactions.delete(id: id)
    }

    // MARK: - Helpers para a UI

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    /// Ícone "efetivo" da categoria. Se a categoria for raiz, retorna o ícone
    /// dela (resolvido via slug). Se for subcategoria, retorna o ícone do pai
    /// (porque por design só raízes têm slug — ver `Category.icon`).
    func icon(for categoryId: UUID) -> CategoryIcon? {
        guard let cat = category(for: categoryId) else { return nil }
        if let icon = cat.icon { return icon }
        if let parentId = cat.parentId,
           let parent = category(for: parentId)
        {
            return parent.icon
        }
        return nil
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: - Statement helpers (Fase 4.7)

    /// Statement à qual a transação pertence (compra de cartão). `nil` pra
    /// transações em conta corrente ou transferências.
    func statement(for transaction: Transaction) -> Statement? {
        guard let id = transaction.statementId else { return nil }
        return statements.first { $0.id == id }
    }

    /// Statements em aberto de uma conta-cartão, ordenadas por `closing_date`
    /// crescente (mais antiga primeiro). Usada pelo picker de pagamento.
    func openStatements(for accountId: UUID) -> [Statement] {
        statements
            .filter { $0.accountId == accountId && $0.remainingAmount > 0 }
            .sorted { $0.closingDate < $1.closingDate }
    }

    func refundablePurchases(
        accountId: UUID?,
        occurredAt: Date,
        excluding transactionId: UUID? = nil
    ) -> [Transaction] {
        guard let accountId else { return [] }
        return transactions
            .filter {
                $0.accountId == accountId
                    && $0.id != transactionId
                    && $0.refundOfTransactionId == nil
                    && $0.destinationAccountId == nil
                    && $0.occurredAt <= occurredAt
                    && remainingRefundableAmount(for: $0) > 0
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    func remainingRefundableAmount(for purchase: Transaction) -> Decimal {
        let refunded = transactions
            .filter { $0.refundOfTransactionId == purchase.id }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return max(0, purchase.amount - refunded)
    }

    func automaticPaymentPreview(
        accountId: UUID,
        amount: Decimal,
        occurredAt: Date
    ) -> [(statement: Statement, amount: Decimal)] {
        var remaining = amount
        var result: [(Statement, Decimal)] = []
        for statement in openStatements(for: accountId) where remaining > 0 {
            let hasEntryByPaymentDate = transactions.contains {
                $0.statementId == statement.id && $0.occurredAt <= occurredAt
            }
            guard hasEntryByPaymentDate else { continue }
            let applied = min(statement.remainingAmount, remaining)
            guard applied > 0 else { continue }
            result.append((statement, applied))
            remaining -= applied
        }
        return result
    }

    /// Payments aplicados a uma Statement (lista de transferências que
    /// pagaram parte/total). `nil` em vez de array vazio quando a Statement
    /// não existe — distingue do caso "existe mas ninguém pagou ainda".
    func payments(for statement: Statement) -> [StatementPayment] {
        statementPayments.filter { $0.statementId == statement.id }
    }

    /// Total já aplicado a uma Statement via payments — soma do
    /// `appliedAmount` de todos os payments daquela Statement.
    func appliedAmount(to statement: Statement) -> Decimal {
        payments(for: statement).reduce(Decimal(0)) { $0 + $1.appliedAmount }
    }

    /// Saldo restante de uma Statement (`total - applied`). Pode ficar
    /// negativo em caso de overpayment.
    func remainingAmount(of statement: Statement) -> Decimal {
        statement.remainingAmount
    }

    func institution(for id: UUID) -> Institution? {
        institutions.first { $0.id == id }
    }

    /// Nome derivado da conta — espelha `AccountStore.displayName(for:)`. Cada
    /// store tem sua cópia porque carrega institutions sob demanda da feature.
    func displayName(for account: Account) -> String {
        Account.displayName(
            for: account,
            institutions: institutions,
            bankAccounts: bankDetails,
            creditCards: creditCards
        )
    }

    var rootCategories: [Category] {
        categories.filter { $0.parentId == nil }
    }

    func subcategories(of parentId: UUID) -> [Category] {
        categories.filter { $0.parentId == parentId }
    }
}
