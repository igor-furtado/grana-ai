import Foundation
import Testing
@testable import GranaAi

@Suite("CSVReader")
struct CSVReaderTests {
    private let reader = CSVReader()

    @Test("Parse simples com delimitador vírgula")
    func simpleComma() {
        let csv = """
        Data,Descrição,Valor
        2026-03-15,Mercado,123.45
        2026-03-16,Restaurante,67.80
        """
        let rows = reader.parse(text: csv)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Data", "Descrição", "Valor"])
        #expect(rows[1] == ["2026-03-15", "Mercado", "123.45"])
        #expect(rows[2] == ["2026-03-16", "Restaurante", "67.80"])
    }

    @Test("Autodetecta delimitador ;")
    func semicolonDelimiter() {
        let csv = """
        Data;Descrição;Valor
        15/03/2026;PIX RECEBIDO;1.234,56
        """
        let rows = reader.parse(text: csv)
        #expect(rows.count == 2)
        #expect(rows[1] == ["15/03/2026", "PIX RECEBIDO", "1.234,56"])
    }

    @Test("Aspas envolvendo célula com vírgula")
    func quotedCellWithComma() {
        let csv = "Descrição,Valor\n\"PIX, ENVIADO\",100.00"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 2)
        #expect(rows[1][0] == "PIX, ENVIADO")
        #expect(rows[1][1] == "100.00")
    }

    @Test("Aspas duplas escapadas dentro de célula entre aspas")
    func escapedQuotes() {
        let csv = "a,\"contém \"\"aspas\"\" no meio\",c"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 1)
        #expect(rows[0] == ["a", "contém \"aspas\" no meio", "c"])
    }

    @Test("BOM UTF-8 inicial é removido")
    func bomStripping() {
        let csv = "\u{FEFF}Data,Valor\n2026-01-01,10"
        let rows = reader.parse(text: csv)
        // Se BOM não fosse removido, a primeira célula viraria "\u{FEFF}Data".
        #expect(rows[0][0] == "Data")
    }

    @Test("Line endings CRLF tratados como uma quebra única")
    func crlfLineEndings() {
        let csv = "a,b\r\nc,d\r\ne,f"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 3)
        #expect(rows[0] == ["a", "b"])
        #expect(rows[1] == ["c", "d"])
        #expect(rows[2] == ["e", "f"])
    }

    @Test("Células vazias preservadas")
    func emptyCells() {
        let csv = "a,,c\n,b,\n,,"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 3)
        #expect(rows[0] == ["a", "", "c"])
        #expect(rows[1] == ["", "b", ""])
        #expect(rows[2] == ["", "", ""])
    }

    @Test("Quebra de linha dentro de célula entre aspas é mantida")
    func newlineInsideQuotedCell() {
        let csv = "a,\"linha 1\nlinha 2\",c"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 1)
        #expect(rows[0] == ["a", "linha 1\nlinha 2", "c"])
    }

    @Test("Arquivo sem newline final ainda captura última linha")
    func noTrailingNewline() {
        let csv = "a,b\nc,d"
        let rows = reader.parse(text: csv)
        #expect(rows.count == 2)
        #expect(rows[1] == ["c", "d"])
    }
}
