import CoreXLSX
import Foundation

/// Leitor de XLSX. Estratégia:
/// 1. Abre o pacote via `XLSXFile(filepath:)`.
/// 2. Pega a primeira worksheet (suficiente pro caso de uso "extrato bancário"
///    — bancos sempre exportam uma única aba).
/// 3. Resolve shared strings: XLSX guarda strings repetidas num pool central
///    referenciado por índice; sem a tabela, células de texto vêm como números.
/// 4. Achata em `[[String]]` respeitando a coluna máxima encontrada
///    (linhas curtas viram linhas paddadas com `""`, pra alinhamento estável
///    com o `ColumnMapping`).
struct XLSXReader: SpreadsheetReader {

    func readRows(from url: URL) throws -> [[String]] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ImportError.fileUnreadable(url)
        }

        // Shared strings pode não existir em planilhas que só têm números —
        // tratar `nil` como tabela vazia, não como erro.
        let sharedStrings = (try? file.parseSharedStrings()) ?? nil

        guard let workbook = try file.parseWorkbooks().first,
              let firstSheetRef = try file.parseWorksheetPathsAndNames(workbook: workbook).first else {
            throw ImportError.emptySheet
        }
        let worksheet = try file.parseWorksheet(at: firstSheetRef.path)
        let sheetRows = worksheet.data?.rows ?? []
        if sheetRows.isEmpty {
            throw ImportError.emptySheet
        }

        // Algumas planilhas vêm com linhas e colunas "esparsas" (sem células
        // pra colunas em branco). Determinar a largura máxima primeiro pra que
        // toda row tenha o mesmo número de colunas, simplificando o mapping
        // por índice no parser.
        var maxColumn = 0
        for row in sheetRows {
            for cell in row.cells {
                let columnIndex = Self.columnIndex(from: cell.reference.column)
                if columnIndex + 1 > maxColumn { maxColumn = columnIndex + 1 }
            }
        }

        var result: [[String]] = []
        result.reserveCapacity(sheetRows.count)

        for row in sheetRows {
            var line = Array(repeating: "", count: maxColumn)
            for cell in row.cells {
                let columnIndex = Self.columnIndex(from: cell.reference.column)
                let value = Self.stringValue(of: cell, sharedStrings: sharedStrings)
                if columnIndex < line.count {
                    line[columnIndex] = value
                }
            }
            result.append(line)
        }

        return result
    }

    /// Converte uma `Cell` em string. Ordem de precedência:
    /// 1. Shared string (tipo `s` em XLSX): texto fica num pool central
    ///    referenciado por índice; sem resolver, a célula vira número.
    /// 2. Valor cru (números, datas serializadas como serial number XLSX).
    ///
    /// **Datas:** XLSX guarda data como número de dias desde 1900-01-01 (ou
    /// 1904 no formato Mac legado). Não convertemos aqui — o `ImportParser`
    /// recebe `dateFormat` do template e parseia. Se o usuário tiver uma
    /// planilha com data serial, ele troca pro formato de número e parser
    /// trata. Casos comuns (extratos brasileiros) já vêm como string formatada.
    private static func stringValue(
        of cell: Cell,
        sharedStrings: SharedStrings?
    ) -> String {
        if let shared = sharedStrings, let resolved = cell.stringValue(shared) {
            return resolved
        }
        return cell.value ?? ""
    }

    /// `"A"` → 0, `"B"` → 1, ..., `"AA"` → 26. Base 26 com dígitos `A-Z`.
    private static func columnIndex(from column: ColumnReference) -> Int {
        var result = 0
        for ch in column.value.uppercased() {
            guard let scalar = ch.asciiValue, scalar >= 65, scalar <= 90 else { continue }
            result = result * 26 + Int(scalar - 64)
        }
        return result - 1
    }
}
