import Foundation
import Testing
@testable import GranaAi

@Suite("PeriodFilter.dateRange")
struct PeriodFilterTests {

    /// Calendar com timezone determinístico — testes não devem depender do
    /// fuso da máquina. Usar `gregorian` + UTC pra inputs/outputs previsíveis.
    private func makeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Helper: constrói uma `Date` específica no calendário de teste.
    private func date(
        _ y: Int, _ m: Int, _ d: Int,
        _ h: Int = 0, _ min: Int = 0, _ s: Int = 0,
        calendar: Calendar
    ) -> Date {
        let comps = DateComponents(
            calendar: calendar,
            year: y, month: m, day: d,
            hour: h, minute: min, second: s
        )
        return comps.date!
    }

    // MARK: - currentMonth

    @Test("currentMonth em 15/03/2026 → (01/03 00:00, 31/03 23:59:59)")
    func currentMonthMarch2026() {
        let cal = makeCalendar()
        let today = date(2026, 3, 15, 14, 30, 0, calendar: cal)

        let (from, to) = PeriodFilter.currentMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2026, 3, 1,  0,  0,  0, calendar: cal))
        #expect(to   == date(2026, 3, 31, 23, 59, 59, calendar: cal))
    }

    @Test("currentMonth em fevereiro de ano não-bissexto (2026) → 28 dias")
    func currentMonthFebruary2026() {
        let cal = makeCalendar()
        let today = date(2026, 2, 10, calendar: cal)

        let (from, to) = PeriodFilter.currentMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2026, 2, 1, calendar: cal))
        #expect(to   == date(2026, 2, 28, 23, 59, 59, calendar: cal))
    }

    @Test("currentMonth em fevereiro de ano bissexto (2024) → 29 dias")
    func currentMonthFebruary2024Leap() {
        let cal = makeCalendar()
        let today = date(2024, 2, 10, calendar: cal)

        let (from, to) = PeriodFilter.currentMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2024, 2, 1, calendar: cal))
        #expect(to   == date(2024, 2, 29, 23, 59, 59, calendar: cal))
    }

    // MARK: - previousMonth

    @Test("previousMonth em 15/03/2026 → (01/02 00:00, 28/02 23:59:59)")
    func previousMonthFromMarch2026() {
        let cal = makeCalendar()
        let today = date(2026, 3, 15, calendar: cal)

        let (from, to) = PeriodFilter.previousMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2026, 2, 1, calendar: cal))
        #expect(to   == date(2026, 2, 28, 23, 59, 59, calendar: cal))
    }

    @Test("previousMonth em março/2024 → fevereiro com 29 dias (bissexto)")
    func previousMonthFromMarch2024Leap() {
        let cal = makeCalendar()
        let today = date(2024, 3, 15, calendar: cal)

        let (from, to) = PeriodFilter.previousMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2024, 2, 1, calendar: cal))
        #expect(to   == date(2024, 2, 29, 23, 59, 59, calendar: cal))
    }

    @Test("previousMonth atravessa virada de ano (01/01/2026 → dez/2025)")
    func previousMonthYearWrap() {
        let cal = makeCalendar()
        let today = date(2026, 1, 5, calendar: cal)

        let (from, to) = PeriodFilter.previousMonth.dateRange(calendar: cal, today: today)

        #expect(from == date(2025, 12, 1,  calendar: cal))
        #expect(to   == date(2025, 12, 31, 23, 59, 59, calendar: cal))
    }

    // MARK: - rolling N meses

    @Test("last6Months em 15/03/2026 → (01/10/2025 00:00, 15/03/2026 mid-day)")
    func last6MonthsFromMarch2026() {
        let cal = makeCalendar()
        let today = date(2026, 3, 15, 14, 30, 0, calendar: cal)

        let (from, to) = PeriodFilter.last6Months.dateRange(calendar: cal, today: today)

        // 6 meses = março + 5 anteriores → outubro/2025
        #expect(from == date(2025, 10, 1, calendar: cal))
        #expect(to == today)
    }

    @Test("last12Months em 15/03/2026 → começa em 01/04/2025")
    func last12MonthsFromMarch2026() {
        let cal = makeCalendar()
        let today = date(2026, 3, 15, calendar: cal)

        let (from, to) = PeriodFilter.last12Months.dateRange(calendar: cal, today: today)

        // 12 meses = março + 11 anteriores → abril/2025
        #expect(from == date(2025, 4, 1, calendar: cal))
        #expect(to == today)
    }

    @Test("last12Months atravessa viradas de ano corretamente")
    func last12MonthsYearWrap() {
        let cal = makeCalendar()
        let today = date(2026, 2, 10, calendar: cal)

        let (from, _) = PeriodFilter.last12Months.dateRange(calendar: cal, today: today)
        // fev/2026 + 11 anteriores → mar/2025
        #expect(from == date(2025, 3, 1, calendar: cal))
    }

    // MARK: - scope

    @Test("scope: mês único vs. multi-mês")
    func scopeDichotomy() {
        #expect(PeriodFilter.currentMonth.scope  == .singleMonth)
        #expect(PeriodFilter.previousMonth.scope == .singleMonth)
        #expect(PeriodFilter.last6Months.scope   == .multiMonth)
        #expect(PeriodFilter.last12Months.scope  == .multiMonth)
        let custom: PeriodFilter = .custom(from: Date(), to: Date())
        #expect(custom.scope == .singleMonth)
    }

    // MARK: - custom

    @Test("custom retorna exatamente os valores passados")
    func customPassthrough() {
        let cal = makeCalendar()
        let from = date(2025, 6, 1,  calendar: cal)
        let to   = date(2025, 6, 30, 23, 59, 59, calendar: cal)

        let (rFrom, rTo) = PeriodFilter.custom(from: from, to: to)
            .dateRange(calendar: cal, today: Date())

        #expect(rFrom == from)
        #expect(rTo == to)
    }
}
