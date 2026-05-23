import Foundation

/// Filtro temporal do dashboard.
///
/// O filtro tem dois "modos" implícitos:
/// - **Mês único** (`currentMonth`, `previousMonth`, `custom`): faz sentido
///   ver donut de categoria do mês + barras diárias.
/// - **Multi-mês** (`last6Months`, `last12Months`): faz sentido ver série
///   temporal — barras empilhadas mês × categoria, receita vs. despesa por mês.
///
/// `scope` expõe essa dicotomia pra UI decidir quais gráficos renderizar
/// — em vez de espalhar `switch self` por toda a `DashboardView`.
enum PeriodFilter: Hashable, Identifiable {
    case currentMonth
    case previousMonth
    case last6Months
    case last12Months
    case custom(from: Date, to: Date)

    var id: String {
        switch self {
        case .currentMonth: "current"
        case .previousMonth: "previous"
        case .last6Months: "last6"
        case .last12Months: "last12"
        case let .custom(from, to):
            "custom-\(from.timeIntervalSince1970)-\(to.timeIntervalSince1970)"
        }
    }

    var displayName: String {
        switch self {
        case .currentMonth: "Mês atual"
        case .previousMonth: "Mês anterior"
        case .last6Months: "Últimos 6 meses"
        case .last12Months: "Últimos 12 meses"
        case .custom: "Customizado"
        }
    }

    enum Scope { case singleMonth, multiMonth }

    /// "Que tipo de visualização este filtro pede?" — usado pela View pra
    /// alternar entre gráficos mensais e gráficos longitudinais.
    var scope: Scope {
        switch self {
        case .currentMonth, .previousMonth, .custom: .singleMonth
        case .last6Months, .last12Months: .multiMonth
        }
    }

    /// Resolve o intervalo concreto (início → fim, inclusivo nas duas pontas).
    /// Mês único termina no último segundo do mês; multi-mês termina no
    /// momento da chamada (`today`) — não tem "fim do mês" pra rolling window.
    ///
    /// **Por que injetar `calendar` e `today` com default:** torna a função
    /// testável sem depender do relógio real. Em produção a chamada fica
    /// `period.dateRange()` (defaults entram); em teste passamos um `today`
    /// fixo e um `Calendar` com timezone determinístico, e validamos a saída.
    ///
    /// **Por que `Calendar.date(byAdding:)` em vez de aritmética com
    /// `TimeInterval`:** somar `30 * 86400` segundos pra "ir pro próximo mês"
    /// dá errado em transições de horário de verão (DST) e em meses com 28/29/31
    /// dias. `Calendar` entende o calendário gregoriano de verdade — meses,
    /// anos bissextos, segundos intercalares — e retorna a Date correta.
    func dateRange(
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> (from: Date, to: Date) {
        switch self {
        case .currentMonth:
            return monthRange(containing: today, calendar: calendar)
        case .previousMonth:
            guard let prev = calendar.date(byAdding: .month, value: -1, to: today) else {
                return monthRange(containing: today, calendar: calendar)
            }
            return monthRange(containing: prev, calendar: calendar)
        case .last6Months:
            return rollingMonths(count: 6, calendar: calendar, today: today)
        case .last12Months:
            return rollingMonths(count: 12, calendar: calendar, today: today)
        case let .custom(from, to):
            return (from, to)
        }
    }

    // MARK: - Helpers

    private func monthRange(
        containing date: Date,
        calendar: Calendar
    ) -> (from: Date, to: Date) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: comps),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: start),
              let end = calendar.date(byAdding: .second, value: -1, to: startOfNextMonth)
        else {
            return (date, date)
        }
        return (start, end)
    }

    /// "Últimos N meses" = início do mês N-1 meses atrás → `today`. Inclui
    /// o mês corrente parcial — é a definição usada por Mint/Monarch/YNAB
    /// e a esperada pelo usuário ("últimos 6 meses" inclui o que tá rolando).
    private func rollingMonths(
        count: Int,
        calendar: Calendar,
        today: Date
    ) -> (from: Date, to: Date) {
        let startOfThisMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today
        let from = calendar.date(
            byAdding: .month, value: -(count - 1), to: startOfThisMonth
        ) ?? today
        return (from, today)
    }
}
