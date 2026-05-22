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
    private(set) var isLoading = false
    var lastError: Error?

    init(container: AppContainer) {
        self.container = container
    }

    /// Roda os dois watch streams em paralelo. Pattern idêntico ao
    /// `TransactionStore.start()` — `.task` na View garante cancelamento.
    func start() async {
        isLoading = true
        defer { isLoading = false }

        async let a: Void = streamAccounts()
        async let i: Void = streamInstitutions()
        _ = await (a, i)
    }

    private func streamAccounts() async {
        do {
            for try await rows in try container.accounts.watchAll() {
                self.accounts = rows
            }
        } catch is CancellationError {
        } catch {
            self.lastError = error
            ErrorCenter.shared.report(error)
        }
    }

    private func streamInstitutions() async {
        do {
            for try await rows in try container.institutions.watchAll() {
                self.institutions = rows
            }
        } catch is CancellationError {
        } catch {
            self.lastError = error
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

    // MARK: - Mutations

    func create(
        name: String,
        type: AccountType,
        initialBalance: Decimal,
        institutionId: UUID?,
        branchId: String?,
        accountNumber: String?,
        currency: String
    ) async throws {
        let now = Date()
        let account = Account(
            id: UUID(),
            name: name,
            type: type,
            initialBalance: initialBalance,
            archived: false,
            institutionId: institutionId,
            branchId: branchId,
            accountNumber: accountNumber,
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
