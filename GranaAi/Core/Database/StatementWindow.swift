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
/// Implementação usa `Calendar.nextDate(...)` que resolve corner cases de
/// meses curtos automaticamente (ex: closingDay=31 em fevereiro → 28/29).
///
/// **`calendar` injetável** pra testes determinísticos (fixar TZ e referência
/// temporal sem depender da máquina rodando o teste).
struct StatementWindow: Equatable {
    let closingDate: Date
    let dueDate: Date

    static func resolve(
        closingDay: Int,
        paymentDueDay: Int,
        on date: Date,
        calendar: Calendar = .current
    ) -> StatementWindow {
        let cal = calendar
        // `closingDate` = próxima ocorrência de `closingDay` **na ou após**
        // `date`. Implementação: começar de (date − 1s) e procurar forward
        // pelo `nextDate`. Se `date.day == closingDay`, devolve `date`
        // mesmo (regra inclusiva).
        let searchStart = cal.startOfDay(for: date).addingTimeInterval(-1)
        let closingDate = nextDate(matchingDay: closingDay, after: searchStart, calendar: cal)

        // `dueDate` = próxima ocorrência de `paymentDueDay` **após**
        // `closingDate`. Se `paymentDueDay > closingDay`, cai no mesmo mês
        // do `closingDate`; se for menor ou igual, rola pro mês seguinte.
        let dueDate = nextDate(matchingDay: paymentDueDay, after: closingDate, calendar: cal)

        return StatementWindow(closingDate: closingDate, dueDate: dueDate)
    }

    /// Próxima data com `day == targetDay` estritamente após `reference`.
    /// `Calendar.nextDate` com `matching: DateComponents(day: targetDay)`
    /// já trata meses curtos via `matchingPolicy: .nextTime` (cai pro dia
    /// existente mais próximo no mês problema).
    private static func nextDate(matchingDay targetDay: Int, after reference: Date, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.day = targetDay
        guard let next = calendar.nextDate(
            after: reference,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            // Fallback impossível na prática (calendário gregoriano sempre
            // tem um match em algum mês), mas mantém o tipo não-opcional.
            return reference
        }
        // Normaliza pra início do dia (00:00:00) — Statements são "do dia",
        // não de um instante específico. Sem isso, dois Statements criadas
        // em horários diferentes do mesmo `closingDay` seriam consideradas
        // distintas pelo `findByClosingDate`.
        return calendar.startOfDay(for: next)
    }
}
