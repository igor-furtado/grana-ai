import Foundation
import Observation
import OSLog

/// Estado observável da feature Contas — lista de `Account` + lookups de
/// `Institution`, `BankAccountDetails` e `CreditCardDetails`. Separado do
/// `TransactionStore` porque a tela de Contas não precisa carregar
/// transactions/categories (que são caros pra streamar) e o CRUD de conta tem
/// sua própria UI.
@MainActor
@Observable
final class AccountStore {
    /// Container exposto pra Views que precisam abrir streams adicionais
    /// (ex: `CreditCardDetailView` lista lançamentos por fatura via
    /// `transactions.watchByStatement`). Mantido `let` — caller usa só
    /// pra leitura.
    let container: AppContainer

    private(set) var accounts: [Account] = []
    private(set) var institutions: [Institution] = []
    private(set) var bankDetails: [BankAccountDetails] = []
    private(set) var creditCards: [CreditCardDetails] = []
    /// Faturas de cartão (Fase 4.7). Alimenta o "Próxima fatura" no card e
    /// no dashboard. Tabela pequena (12 por cartão por ano) — cabe em
    /// memória sem stress.
    private(set) var statements: [Statement] = []
    /// Saldo atual (inicial + Σ transações com sinal) por id de conta. Vazio
    /// até a primeira emissão do stream — a UI cai pro `initialBalance` nesse
    /// instante.
    private(set) var balances: [UUID: Decimal] = [:]
    private(set) var isLoading = false
    var lastError: Error?

    init(container: AppContainer) {
        self.container = container
    }

    /// Roda os watch streams em paralelo. Pattern idêntico ao
    /// `TransactionStore.start()` — `.task` na View garante cancelamento.
    func start() async {
        isLoading = true
        defer { isLoading = false }

        async let a: Void = streamAccounts()
        async let i: Void = streamInstitutions()
        async let bd: Void = streamBankDetails()
        async let cd: Void = streamCreditCards()
        async let s: Void = streamStatements()
        async let b: Void = streamBalances()
        _ = await (a, i, bd, cd, s, b)
    }

    private func streamAccounts() async {
        do {
            for try await rows in try container.accounts.watchAll() {
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
            for try await rows in try container.institutions.watchAll() {
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

    private func streamBalances() async {
        do {
            for try await dict in try container.accounts.watchBalances() {
                balances = dict
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            NoticeCenter.shared.report(error)
        }
    }

    // MARK: - Lookups

    func institution(for id: UUID) -> Institution? {
        institutions.first { $0.id == id }
    }

    func institution(forAccount account: Account) -> Institution? {
        guard let id = account.institutionId else { return nil }
        return institution(for: id)
    }

    func bankDetails(for accountId: UUID) -> BankAccountDetails? {
        bankDetails.first { $0.accountId == accountId }
    }

    func creditCard(for accountId: UUID) -> CreditCardDetails? {
        creditCards.first { $0.accountId == accountId }
    }

    /// Statement em aberto mais próxima do fechamento pra uma conta-cartão
    /// (i.e., a "próxima fatura" do usuário). `nil` quando o cartão não
    /// teve nenhuma compra ainda (sem Statement criada).
    func nextStatement(for accountId: UUID) -> Statement? {
        statements
            .filter { $0.accountId == accountId && $0.paidAt == nil }
            .min(by: { $0.closingDate < $1.closingDate })
    }

    /// Saldo atual da conta. Cai pro `initialBalance` enquanto o stream de
    /// balances ainda não emitiu (primeira renderização) — evita um "R$ 0,00"
    /// piscando antes do valor real.
    func currentBalance(for account: Account) -> Decimal {
        balances[account.id] ?? account.initialBalance
    }

    /// Nome derivado da conta pra exibição. Como `Account` não armazena nome a
    /// partir da Fase 4.5, o display vem da combinação `instituição + tipo +
    /// identificador específico` (número da conta pra bancos, ••••last4 pra
    /// cartão). Reusa a versão estática — qualquer caller que tenha
    /// `institutions`/`bankDetails`/`creditCards` em mãos pode resolver sem
    /// passar pelo store.
    func displayName(for account: Account) -> String {
        Account.displayName(
            for: account,
            institutions: institutions,
            bankAccounts: bankDetails,
            creditCards: creditCards
        )
    }

    // MARK: - Mutations

    func create(
        type: AccountType,
        initialBalance: Decimal,
        institutionId: UUID?,
        currency: String,
        bankDetails: BankAccountDetailsInput? = nil,
        creditCardDetails: CreditCardDetailsInput? = nil
    ) async throws {
        let now = Date()
        let accountId = UUID()
        let account = Account(
            id: accountId,
            type: type,
            initialBalance: initialBalance,
            archived: false,
            institutionId: institutionId,
            currency: currency,
            createdAt: now,
            updatedAt: now
        )

        let bank = bankDetails.map {
            BankAccountDetails(
                accountId: accountId,
                branchId: $0.branchId,
                accountNumber: $0.accountNumber,
                createdAt: now,
                updatedAt: now
            )
        }
        let card = creditCardDetails.map {
            CreditCardDetails(
                accountId: accountId,
                cardLastFour: $0.cardLastFour,
                creditLimit: $0.creditLimit,
                statementClosingDay: $0.statementClosingDay,
                paymentDueDay: $0.paymentDueDay,
                createdAt: now,
                updatedAt: now
            )
        }

        try await container.accounts.insert(
            account,
            bankDetails: bank,
            creditCardDetails: card
        )
    }

    func update(
        _ account: Account,
        bankDetails: BankAccountDetailsInput? = nil,
        creditCardDetails: CreditCardDetailsInput? = nil
    ) async throws {
        var copy = account
        copy.updatedAt = Date()
        let now = copy.updatedAt

        let bank = bankDetails.map {
            BankAccountDetails(
                accountId: account.id,
                branchId: $0.branchId,
                accountNumber: $0.accountNumber,
                createdAt: now,
                updatedAt: now
            )
        }
        let card = creditCardDetails.map {
            CreditCardDetails(
                accountId: account.id,
                cardLastFour: $0.cardLastFour,
                creditLimit: $0.creditLimit,
                statementClosingDay: $0.statementClosingDay,
                paymentDueDay: $0.paymentDueDay,
                createdAt: now,
                updatedAt: now
            )
        }

        try await container.accounts.update(
            copy,
            bankDetails: bank,
            creditCardDetails: card
        )
    }

    func delete(id: UUID) async throws {
        try await container.accounts.delete(id: id)
    }

    /// Toggle de arquivamento. Conta arquivada some dos pickers do form de
    /// transação e dos totais do dashboard, mas mantém histórico vinculado.
    /// Não toca em details (preserva agência/cartão pra reativação).
    func setArchived(_ account: Account, archived: Bool) async throws {
        var copy = account
        copy.archived = archived
        copy.updatedAt = Date()
        // Repassa os details existentes pra `update` não dropar eles no
        // delete-then-insert da tabela-irmã.
        let bank = bankDetails.first { $0.accountId == account.id }
            .map { BankAccountDetailsInput(branchId: $0.branchId, accountNumber: $0.accountNumber) }
        let card = creditCards.first { $0.accountId == account.id }
            .map {
                CreditCardDetailsInput(
                    cardLastFour: $0.cardLastFour,
                    creditLimit: $0.creditLimit,
                    statementClosingDay: $0.statementClosingDay,
                    paymentDueDay: $0.paymentDueDay
                )
            }
        try await update(copy, bankDetails: bank, creditCardDetails: card)
    }
}

/// DTO de entrada pra `AccountStore.create`/`update`. Carrega só o que o
/// usuário digitou — `accountId`/`createdAt`/`updatedAt` o store define.
struct BankAccountDetailsInput: Hashable {
    var branchId: String?
    var accountNumber: String
}

struct CreditCardDetailsInput: Hashable {
    var cardLastFour: String
    var creditLimit: Decimal?
    var statementClosingDay: Int
    var paymentDueDay: Int
}
