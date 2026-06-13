import Foundation

/// Resolver de janela de Fatura: dado o ciclo de fechamento configurado num
/// cartão (`statementClosingDay`/`paymentDueDay`) e a data de uma transação,
/// devolve `(closingDate, dueDate)` da Fatura que cobre aquela transação.
///
/// **Regra do fechamento:** a Fatura "fecha em X" inclui transações de
/// `(fechamento anterior, fechamento atual]`. Ou seja, uma compra no dia
/// `closingDay` já entra na Fatura que fecha naquele dia (último dia do ciclo
/// inclusivo). Uma compra no dia seguinte abre o próximo ciclo.
///
/// **`calendar` injetável** pra testes determinísticos (fixar TZ e referência
/// temporal sem depender da máquina rodando o teste).
struct StatementWindow: Equatable {
    let openingDate: Date
    let closingDate: Date
    let dueDate: Date

    nonisolated static func resolve(
        closingDay: Int,
        paymentDueDay: Int,
        on date: Date,
        calendar: Calendar = .current
    ) -> StatementWindow {
        let cal = calendar
        let transactionDay = cal.startOfDay(for: date)
        var month = cal.dateComponents([.year, .month], from: transactionDay)
        var closingDate = makeDate(in: month, preferredDay: closingDay, calendar: cal)
        if transactionDay > closingDate {
            let monthStart = cal.date(from: month) ?? transactionDay
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            month = cal.dateComponents([.year, .month], from: nextMonth)
            closingDate = makeDate(in: month, preferredDay: closingDay, calendar: cal)
        }

        var dueMonth = cal.dateComponents([.year, .month], from: closingDate)
        var dueDate = makeDate(in: dueMonth, preferredDay: paymentDueDay, calendar: cal)
        if dueDate <= closingDate {
            let monthStart = cal.date(from: dueMonth) ?? closingDate
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            dueMonth = cal.dateComponents([.year, .month], from: nextMonth)
            dueDate = makeDate(in: dueMonth, preferredDay: paymentDueDay, calendar: cal)
        }

        let currentMonthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: closingDate)
        ) ?? closingDate
        let previousMonth = cal.date(byAdding: .month, value: -1, to: currentMonthStart)
            ?? currentMonthStart
        let previousClosing = makeDate(
            in: cal.dateComponents([.year, .month], from: previousMonth),
            preferredDay: closingDay,
            calendar: cal
        )
        let openingDate = cal.date(byAdding: .day, value: 1, to: previousClosing)
            ?? previousClosing

        return StatementWindow(
            openingDate: openingDate,
            closingDate: closingDate,
            dueDate: dueDate
        )
    }

    private nonisolated static func makeDate(
        in month: DateComponents,
        preferredDay: Int,
        calendar: Calendar
    ) -> Date {
        guard let monthStart = calendar.date(from: month),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return calendar.startOfDay(for: calendar.date(from: month) ?? Date())
        }
        var components = month
        components.day = min(preferredDay, dayRange.count)
        return calendar.startOfDay(for: calendar.date(from: components) ?? monthStart)
    }
}
