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
    private let database: AppDatabase

    private(set) var transactions: [Transaction] = []
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    private(set) var isLoading = false
    var lastError: Error?

    init(database: AppDatabase) {
        self.database = database
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

        // `async let` roda os três em paralelo. Cada um é uma função async
        // isolada à MainActor — ao atualizar `self.X`, já estamos na main.
        // O await final só termina quando todas as streams encerrarem
        // (em prática: só quando o task pai for cancelado).
        async let t: Void = streamTransactions()
        async let a: Void = streamAccounts()
        async let c: Void = streamCategories()
        _ = await (t, a, c)
    }

    private func streamTransactions() async {
        do {
            let stream = try database.transactions.watchAll()
            for try await rows in stream {
                self.transactions = rows
            }
        } catch is CancellationError {
            // .task foi cancelado pela SwiftUI — comportamento esperado.
        } catch {
            self.lastError = error
            ErrorCenter.shared.report(error)
        }
    }

    private func streamAccounts() async {
        do {
            let stream = try database.accounts.watchAll()
            for try await rows in stream {
                self.accounts = rows
            }
        } catch is CancellationError {
        } catch {
            self.lastError = error
            ErrorCenter.shared.report(error)
        }
    }

    private func streamCategories() async {
        do {
            let stream = try database.categories.watchAll()
            for try await rows in stream {
                self.categories = rows
            }
        } catch is CancellationError {
        } catch {
            self.lastError = error
            ErrorCenter.shared.report(error)
        }
    }

    // MARK: - Mutations

    /// Cria uma transação nova. A UI só passa os campos do formulário;
    /// o store preenche id, createdAt e updatedAt.
    func add(
        accountId: UUID,
        categoryId: UUID,
        subcategoryId: UUID?,
        amount: Decimal,
        occurredAt: Date,
        description: String,
        notes: String?
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
            createdAt: now,
            updatedAt: now
        )
        try await database.transactions.insert(transaction)
        // Não precisamos atualizar `self.transactions` manualmente — o watch
        // stream emite o novo estado automaticamente.
    }

    func update(_ transaction: Transaction) async throws {
        var copy = transaction
        copy.updatedAt = Date()
        try await database.transactions.update(copy)
    }

    func delete(id: UUID) async throws {
        try await database.transactions.delete(id: id)
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
           let parent = category(for: parentId) {
            return parent.icon
        }
        return nil
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    var rootCategories: [Category] {
        categories.filter { $0.parentId == nil }
    }

    func subcategories(of parentId: UUID) -> [Category] {
        categories.filter { $0.parentId == parentId }
    }
}
