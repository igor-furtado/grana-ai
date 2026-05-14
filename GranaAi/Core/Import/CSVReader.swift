import Foundation

/// Parser CSV manual, sem dependência externa. Trata:
/// - delimitador `,` ou `;` (autodetecção pela primeira linha não-vazia),
/// - aspas duplas envolvendo célula (`"foo, bar"`),
/// - aspas duplas escapadas (`""`) dentro de célula entre aspas,
/// - BOM UTF-8 inicial (`\u{FEFF}`),
/// - line endings `\r\n`, `\n` e `\r` legados.
///
/// **Por que não usar `String.components(separatedBy:)`:** quebra em vírgulas
/// dentro de aspas. Extratos brasileiros costumam ter "Descrição: PIX, ENVIADO"
/// como célula única — split ingênuo cortaria errado.
struct CSVReader: SpreadsheetReader {

    func readRows(from url: URL) throws -> [[String]] {
        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.fileUnreadable(url)
        }
        guard let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.fileUnreadable(url)
        }
        return parse(text: raw)
    }

    /// Exposto pra teste: faz o parse a partir de uma string já carregada.
    func parse(text: String) -> [[String]] {
        var input = text
        // BOM UTF-8 vira caractere fantasma na primeira célula se não removido.
        if input.hasPrefix("\u{FEFF}") {
            input.removeFirst()
        }

        let delimiter = autodetectDelimiter(in: input)

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var insideQuotes = false

        var index = input.startIndex
        while index < input.endIndex {
            let ch = input[index]

            if insideQuotes {
                if ch == "\"" {
                    // Lookahead pra `""` (aspa escapada).
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "\"" {
                        currentCell.append("\"")
                        index = input.index(after: next)
                        continue
                    }
                    insideQuotes = false
                    index = input.index(after: index)
                    continue
                }
                currentCell.append(ch)
                index = input.index(after: index)
                continue
            }

            // Fora de aspas.
            if ch == "\"" {
                insideQuotes = true
                index = input.index(after: index)
                continue
            }
            if ch == delimiter {
                currentRow.append(currentCell)
                currentCell = ""
                index = input.index(after: index)
                continue
            }
            if ch == "\n" || ch == "\r" {
                currentRow.append(currentCell)
                rows.append(currentRow)
                currentCell = ""
                currentRow = []
                // Pular `\r\n` como UMA quebra: se for `\r`, e o próximo é `\n`,
                // avança dois.
                if ch == "\r" {
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "\n" {
                        index = input.index(after: next)
                        continue
                    }
                }
                index = input.index(after: index)
                continue
            }

            currentCell.append(ch)
            index = input.index(after: index)
        }

        // Última célula/linha (caso o arquivo não termine com newline).
        if !currentCell.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }

        return rows
    }

    /// Conta `,` vs `;` na primeira linha não-vazia (fora de aspas) e escolhe
    /// o que aparecer mais. Default `,` quando empata. Cobre o caso BR onde
    /// muitos bancos exportam com `;` (Excel BR usa `;` por causa do decimal
    /// `,`).
    ///
    /// Limitamos a varredura a `Self.autodetectSampleSize` caracteres pra
    /// que CSVs de uma só linha (sem newline) não façam um sweep do arquivo
    /// inteiro. A primeira linha não-vazia caberia bem dentro desse limite
    /// em qualquer extrato real.
    private static let autodetectSampleSize = 4096

    private func autodetectDelimiter(in text: String) -> Character {
        var insideQuotes = false
        var commaCount = 0
        var semicolonCount = 0

        for ch in text.prefix(Self.autodetectSampleSize) {
            if ch == "\"" {
                insideQuotes.toggle()
                continue
            }
            if insideQuotes { continue }
            if ch == "\n" || ch == "\r" {
                if commaCount > 0 || semicolonCount > 0 { break }
                continue
            }
            if ch == "," { commaCount += 1 }
            if ch == ";" { semicolonCount += 1 }
        }

        return semicolonCount > commaCount ? ";" : ","
    }
}
