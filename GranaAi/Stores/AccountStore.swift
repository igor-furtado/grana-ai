import Foundation
import Observation
import OSLog

/// Estado observável da feature Contas — lista de `Account` + lookup de
/// `Institution`. Separado do `TransactionStore` porque a tela de Contas não
/// precisa carregar transactions/categories (que são caros pra streamar) e o
/// CRUD de conta tem sua própria UI.
@MainActor
@Observable
final class AccountStore {
    private let container: AppContainer

    private(set) var accounts: [Account] = []
    private(set) var institutions: [Institution] = []
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
        async let b: Void = streamBalances()
        _ = await (a, i, b)
    }

    private func streamAccounts() async {
        do {
            for try await rows in try container.accounts.watchAll() {
                accounts = rows
            }
        } catch is CancellationError {
        } catch {
            lastError = error
            ErrorCenter.shared.report(error)
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
            ErrorCenter.shared.report(error)
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
            ErrorCenter.shared.report(error)
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
    /// `institutions` em mãos pode resolver sem passar pelo store.
    func displayName(for account: Account) -> String {
        Account.displayName(for: account, institutions: institutions)
    }

    // MARK: - Mutations

    func create(
        type: AccountType,
        initialBalance: Decimal,
        institutionId: UUID?,
        branchId: String?,
        accountNumber: String?,
        cardLastFour: String?,
        currency: String
    ) async throws {
        let now = Date()
        let account = Account(
            id: UUID(),
            type: type,
            initialBalance: initialBalance,
            archived: false,
            institutionId: institutionId,
            branchId: branchId,
            accountNumber: accountNumber,
            cardLastFour: cardLastFour,
            currency: currency,
            createdAt: now,
            updatedAt: now
        )
        try await container.accounts.insert(account)
    }

    func update(_ account: Account) async throws {
        var copy = account
        copy.updatedAt = Date()
        try await container.accounts.update(copy)
    }

    func delete(id: UUID) async throws {
        try await container.accounts.delete(id: id)
    }

    /// Toggle de arquivamento. Conta arquivada some dos pickers do form de
    /// transação e dos totais do dashboard, mas mantém histórico vinculado.
    func setArchived(_ account: Account, archived: Bool) async throws {
        var copy = account
        copy.archived = archived
        copy.updatedAt = Date()
        try await container.accounts.update(copy)
    }
}
