import Foundation
import Observation
import OSLog

/// Estado observável do Dashboard.
///
/// **Diferença em relação ao `TransactionStore` (Fase 1):**
/// O `TransactionStore` consome **streams** via `watch` e re-renderiza
/// automaticamente a cada mudança no banco. Este faz **leituras one-shot**
/// via `getAll` e só recalcula quando `refresh()` é chamado. Trade-off:
/// dashboard não atualiza se o usuário adicionar uma transação em outra aba
/// — mas ganha em performance (não recomputa todas as agregações a cada
/// keystroke num formulário em outra tela).
///
/// Quando o usuário voltar pro dashboard, o `.task { await store.refresh() }`
/// na View dispara o recálculo.
@MainActor
@Observable
final class DashboardStore {
    private let database: AppDatabase

    /// Filtro de período corrente. `didSet` dispara `refresh()` em background
    /// — padrão SwiftUI-friendly: a View binda `$store.filter` no Picker e
    /// trocas do usuário re-disparam o cálculo automaticamente.
    ///
    /// Cada troca cancela o `refreshTask` anterior. Sem isso, alternar
    /// rapidamente entre presets ("mês atual" → "6 meses" → "12 meses")
    /// dispara refreshes concorrentes cuja ordem de retorno não é garantida
    /// — o estado podia ficar com `expensesByCategory` de uma chamada
    /// intermediária enquanto `monthlyByKind` era do filtro final.
    var filter: PeriodFilter = .currentMonth {
        didSet {
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    private var refreshTask: Task<Void, Never>?

    private(set) var totalBalance: Decimal = 0
    private(set) var periodExpenses: Decimal = 0
    private(set) var periodIncome: Decimal = 0
    /// Sempre 0 até a Fase 6 (Investimentos). O card mostra "—" via flag
    /// `placeholder` no `MetricCard` enquanto a feature não chega.
    private(set) var investmentValue: Decimal = 0
    /// Acumulado de despesas por categoria raiz, sempre populado — em
    /// `singleMonth` usa a janela do mês, em `multiMonth` usa os 6/12 meses.
    /// O mesmo `CategoryBarChart` consome em ambos os modos.
    private(set) var expensesByCategory: [CategoryTotal] = []
    /// Populadas só em `scope == .singleMonth`. Zeradas no multi-mês pra
    /// evitar estado stale (ex: usuário alterna "mês atual" → "12 meses" →
    /// "mês atual" e veria momentaneamente os dados anteriores).
    private(set) var weekdayExpenses: [WeekdayTotal] = []
    /// Populadas só em `scope == .multiMonth`. Mesma lógica de zeramento.
    private(set) var monthlyByKind: [MonthlyKindTotal] = []
    /// Usado só pelo layout iPhone (lista das 5 últimas transações no topo).
    private(set) var lastFiveTransactions: [Transaction] = []
    private(set) var isLoading = false
    var lastError: Error?

    init(database: AppDatabase) {
        self.database = database
    }

    /// Recalcula as agregações. Bifurca pelo `scope` do filtro — em mês único
    /// roda só queries mensais; em multi-mês roda só longitudinais. Evita 4
    /// queries SQL inúteis a cada troca de filtro (ex: gráfico diário em
    /// janela de 12 meses = 360 buckets que ninguém vai renderizar).
    ///
    /// Tudo em paralelo via `async let`. PowerSync serializa internamente,
    /// mas o `async let` deixa o código declarativo e evita latência somada.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let (from, to) = filter.dateRange()

        do {
            // Comuns aos dois modos: cards do topo + última 5 (iPhone).
            async let balanceTask = computeTotalBalance()
            async let expensesTask = database.transactions.sum(kind: .expense, from: from, to: to)
            async let incomeTask   = database.transactions.sum(kind: .income,  from: from, to: to)
            async let lastFiveTask = lastFive()

            let (balance, expenses, income, lastFive) =
                try await (balanceTask, expensesTask, incomeTask, lastFiveTask)

            self.totalBalance = balance
            self.periodExpenses = expenses
            self.periodIncome = income
            self.lastFiveTransactions = lastFive

            switch filter.scope {
            case .singleMonth:
                async let byCategoryTask = database.transactions.totalsByCategory(
                    kind: .expense, from: from, to: to
                )
                async let byWeekdayTask = database.transactions.weekdayTotals(
                    kind: .expense, from: from, to: to
                )
                let (byCategory, byWeekday) = try await (byCategoryTask, byWeekdayTask)
                self.expensesByCategory = byCategory
                self.weekdayExpenses = byWeekday
                self.monthlyByKind = []

            case .multiMonth:
                // `totalsByCategory` na janela 6/12m dá o acumulado por
                // categoria — mesmo formato consumido pelo `CategoryBarChart`
                // do singleMonth, só com `from/to` mais largos.
                async let byCategoryTask = database.transactions.totalsByCategory(
                    kind: .expense, from: from, to: to
                )
                async let monthlyByKindTask = database.transactions.monthlyTotalsByKind(
                    from: from, to: to
                )
                let (byCategory, monthlyKind) =
                    try await (byCategoryTask, monthlyByKindTask)
                self.expensesByCategory = byCategory
                self.monthlyByKind = monthlyKind
                self.weekdayExpenses = []
            }

            self.lastError = nil
        } catch {
            self.lastError = error
            log.database.error("DashboardStore.refresh falhou: \(String(describing: error))")
        }
    }

    // MARK: - Cálculos derivados

    /// Saldo total = soma de saldos iniciais + (receitas − despesas) lifetime.
    /// Transferências (`kind = .transfer`) **não entram** — são neutras de
    /// saldo no MVP (PIX enviado + PIX recebido idealmente zeram).
    private func computeTotalBalance() async throws -> Decimal {
        // "Lifetime" = sem filtro de período. Janela gigante via
        // `Date.distantPast → .distantFuture` cobre qualquer transação real.
        let lifetimeFrom = Date.distantPast
        let lifetimeTo = Date.distantFuture

        async let initialTask = database.accounts.sumInitialBalance()
        async let incomeTask = database.transactions.sum(kind: .income,  from: lifetimeFrom, to: lifetimeTo)
        async let expenseTask = database.transactions.sum(kind: .expense, from: lifetimeFrom, to: lifetimeTo)

        let (initial, income, expense) = try await (initialTask, incomeTask, expenseTask)
        return initial + income - expense
    }

    private func lastFive() async throws -> [Transaction] {
        // `getAll` já ordena por occurred_at DESC; pegamos o prefix.
        let all = try await database.transactions.getAll()
        return Array(all.prefix(5))
    }
}
