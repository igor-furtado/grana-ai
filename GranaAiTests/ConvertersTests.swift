import Foundation
import Testing
@testable import GranaAi

@Suite("Converters")
struct ConvertersTests {
    // MARK: - decimalToCents / centsToDecimal

    @Test("Roundtrip valores simples")
    func roundtripSimple() {
        let values: [Decimal] = [0, 1, 10, 100, 1000, 9_999_999]
        for v in values {
            let cents = Converters.decimalToCents(v)
            #expect(Converters.centsToDecimal(cents) == v)
        }
    }

    @Test("Roundtrip com casas decimais exatas")
    func roundtripDecimals() throws {
        // ATENÇÃO: `Decimal` literais (ex: `0.01 as Decimal`) passam por `Double`
        // antes de virarem Decimal — herdam erro binário (`0.01 ≠ exato 0.01`).
        // Pra testar EXATIDÃO, construímos via `Decimal(string:)` (parsing
        // direto em base 10) ou via `Decimal(N) / 100`. É como nossos Decimals
        // nascem em produção (sempre de `Int/100`, nunca de literal float).
        let cases: [(String, Int64)] = [
            ("0.01", 1),
            ("0.10", 10),
            ("1.00", 100),
            ("1.50", 150),
            ("12.34", 1234),
            ("1234.56", 123_456),
        ]
        for (decimalString, expectedCents) in cases {
            let decimal = try #require(Decimal(string: decimalString))
            #expect(Converters.decimalToCents(decimal) == expectedCents)
            #expect(Converters.centsToDecimal(expectedCents) == decimal)
        }
    }

    @Test("Valores negativos")
    func negativeValues() throws {
        #expect(Converters.decimalToCents(-1) == -100)
        let menos150 = try #require(Decimal(string: "-1.50"))
        #expect(Converters.decimalToCents(menos150) == -150)
        #expect(Converters.centsToDecimal(-150) == menos150)
    }

    @Test("Arredondamento half-up na 2ª casa")
    func roundingEdgeCases() throws {
        // `.plain` é half-away-from-zero: 0.5 arredonda pra cima (em módulo).
        // 1.005 * 100 = 100.5 → 101. Usamos `Decimal(string:)` pra garantir
        // que o input seja exatamente 1.005 (literal float seria inexato).
        let umMeio = try #require(Decimal(string: "1.005"))
        let doisMeio = try #require(Decimal(string: "2.005"))
        let umQuatro = try #require(Decimal(string: "1.004"))

        #expect(Converters.decimalToCents(umMeio) == 101)
        #expect(Converters.decimalToCents(doisMeio) == 201)

        // Abaixo de 0.5: sempre pra baixo.
        #expect(Converters.decimalToCents(umQuatro) == 100)
    }

    // MARK: - ISO8601

    @Test("ISO8601 roundtrip de Date")
    func iso8601Roundtrip() throws {
        // Usamos uma data específica (sem milissegundos pra evitar drift na
        // truncagem) e checamos que volta igual depois de string → date.
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 3, day: 15,
            hour: 10, minute: 30, second: 0
        )
        let date = try #require(components.date)

        let string = Converters.dateToString(date)
        let parsed = try #require(Converters.stringToDate(string))

        // Diferença em segundos deve ser <= 1ms (formatter inclui fractional).
        let delta = abs(parsed.timeIntervalSince(date))
        #expect(delta < 0.001)
    }

    @Test("ISO8601 string inválida retorna nil")
    func iso8601InvalidString() {
        #expect(Converters.stringToDate("not a date") == nil)
        #expect(Converters.stringToDate("") == nil)
    }
}
