import Foundation
import Testing
@testable import GranaAi

@Suite("ImportParser")
struct ImportParserTests {
    private func makeParser(
        amount: Int? = 2,
        debit: Int? = nil,
        credit: Int? = nil,
        dateFormat: String = "dd/MM/yyyy",
        decimalSeparator: String = ",",
        headerRowsToSkip: Int = 1
    ) -> ImportParser {
        let mapping = ColumnMapping(
            date: 0,
            description: 1,
            amount: amount,
            debit: debit,
            credit: credit,
            notes: nil,
            headerRowsToSkip: headerRowsToSkip
        )
        return ImportParser(
            mapping: mapping,
            dateFormat: dateFormat,
            decimalSeparator: decimalSeparator
        )
    }

    // MARK: - parseBRLAmount

    @Test("Valor BRL com R$ e separador de milhar")
    func brlWithThousands() {
        let locale = Locale(identifier: "pt_BR")
        #expect(ImportParser.parseBRLAmount("R$ 1.234,56", locale: locale) == Decimal(string: "1234.56"))
        #expect(ImportParser.parseBRLAmount("1.234,56", locale: locale) == Decimal(string: "1234.56"))
        #expect(ImportParser.parseBRLAmount("123,45", locale: locale) == Decimal(string: "123.45"))
    }

    @Test("Valor com parênteses vira negativo")
    func parenthesesNegative() {
        let locale = Locale(identifier: "pt_BR")
        #expect(ImportParser.parseBRLAmount("(123,45)", locale: locale) == Decimal(string: "-123.45"))
        #expect(ImportParser.parseBRLAmount("(R$ 1.000,00)", locale: locale) == Decimal(string: "-1000"))
    }

    @Test("Valor com sinal de menos explícito")
    func explicitMinus() {
        let locale = Locale(identifier: "pt_BR")
        #expect(ImportParser.parseBRLAmount("-50,00", locale: locale) == Decimal(string: "-50"))
        #expect(ImportParser.parseBRLAmount("-R$ 50,00", locale: locale) == Decimal(string: "-50"))
    }

    @Test("Valor com separador decimal ponto (locale en)")
    func englishDecimal() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(ImportParser.parseBRLAmount("1234.56", locale: locale) == Decimal(string: "1234.56"))
        #expect(ImportParser.parseBRLAmount("-12.50", locale: locale) == Decimal(string: "-12.50"))
    }

    @Test("Valor inválido retorna nil")
    func invalidAmount() {
        let locale = Locale(identifier: "pt_BR")
        #expect(ImportParser.parseBRLAmount("abc", locale: locale) == nil)
        #expect(ImportParser.parseBRLAmount("", locale: locale) == nil)
    }

    // MARK: - parse rows

    @Test("Data dd/MM/yyyy + amount unificado")
    func parseUnifiedAmount() {
        let parser = makeParser(amount: 2)
        let rows: [[String]] = [
            ["Data", "Descrição", "Valor"], // header, skipado
            ["15/03/2026", "Mercado XYZ", "-123,45"],
            ["16/03/2026", "Salário", "5.000,00"],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed.count == 2)

        #expect(parsed[0].status == .valid)
        #expect(parsed[0].derived?.amount == Decimal(string: "-123.45"))
        #expect(parsed[0].derived?.description == "Mercado XYZ")

        #expect(parsed[1].status == .valid)
        #expect(parsed[1].derived?.amount == Decimal(string: "5000"))
    }

    @Test("Débito vira negativo, crédito vira positivo")
    func debitCreditReconciliation() {
        let parser = makeParser(amount: nil, debit: 2, credit: 3)
        let rows: [[String]] = [
            ["Data", "Descrição", "Débito", "Crédito"],
            ["15/03/2026", "Compra mercado", "123,45", ""],
            ["16/03/2026", "PIX recebido", "", "500,00"],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed.count == 2)
        #expect(parsed[0].derived?.amount == Decimal(string: "-123.45"))
        #expect(parsed[1].derived?.amount == Decimal(string: "500"))
    }

    @Test("Débito já com sinal negativo na planilha continua negativo")
    func debitAlreadyNegative() {
        let parser = makeParser(amount: nil, debit: 2, credit: 3)
        let rows: [[String]] = [
            ["Data", "Descrição", "Débito", "Crédito"],
            ["15/03/2026", "X", "-123,45", ""],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed[0].status == .valid)
        #expect(parsed[0].derived?.amount == Decimal(string: "-123.45"))
    }

    @Test("Data inválida marca status invalidDate")
    func invalidDate() {
        let parser = makeParser()
        let rows: [[String]] = [
            ["Data", "Desc", "Valor"],
            ["xxx", "Y", "10,00"],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed.count == 1)
        if case let .invalidDate(raw) = parsed[0].status {
            #expect(raw == "xxx")
        } else {
            Issue.record("esperava .invalidDate, recebi \(parsed[0].status)")
        }
        #expect(parsed[0].derived == nil)
    }

    @Test("Valor inválido marca status invalidAmount")
    func invalidAmount2() {
        let parser = makeParser()
        let rows: [[String]] = [
            ["Data", "Desc", "Valor"],
            ["15/03/2026", "Y", "abc"],
        ]
        let parsed = parser.parse(rows: rows)
        if case let .invalidAmount(raw) = parsed[0].status {
            #expect(raw == "abc")
        } else {
            Issue.record("esperava .invalidAmount, recebi \(parsed[0].status)")
        }
    }

    @Test("Linha completamente vazia vira missingFields (não erro)")
    func emptyRow() {
        let parser = makeParser()
        let rows: [[String]] = [
            ["Data", "Desc", "Valor"],
            ["", "", ""],
            ["15/03/2026", "Y", "10,00"],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed.count == 2)
        #expect(parsed[0].status == .missingFields)
        #expect(parsed[1].status == .valid)
    }

    @Test("Formato ISO yyyy-MM-dd")
    func isoDateFormat() throws {
        let parser = makeParser(dateFormat: "yyyy-MM-dd")
        let rows: [[String]] = [
            ["Data", "Desc", "Valor"],
            ["2026-03-15", "Y", "10,00"],
        ]
        let parsed = parser.parse(rows: rows)
        #expect(parsed[0].status == .valid)
        let comps = try Calendar.current.dateComponents(
            [.year, .month, .day],
            from: #require(parsed[0].derived?.occurredAt)
        )
        #expect(comps.year == 2026)
        #expect(comps.month == 3)
        #expect(comps.day == 15)
    }

    @Test("Mapeamento incompleto retorna lista vazia")
    func incompleteMapping() {
        let mapping = ColumnMapping(date: 0, description: nil, amount: 1)
        let parser = ImportParser(mapping: mapping, dateFormat: "dd/MM/yyyy", decimalSeparator: ",")
        let rows: [[String]] = [["15/03/2026", "10,00"]]
        #expect(parser.parse(rows: rows).isEmpty)
    }
}
