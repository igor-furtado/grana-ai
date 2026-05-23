import Foundation

/// Leitor do CSV de fatura do Banco Inter (cartão de crédito).
///
/// **Esquema fixo conhecido** — diferente dos CSVs genéricos removidos na
/// Fase 3, este parser conhece exatamente o layout do banco e não aceita
/// mapeamento manual de colunas. Adicionar outro banco no futuro deve criar
/// um reader irmão (`NubankCreditCardCSVReader`, etc.), não um framework.
///
/// **Quirk de encoding crítico:** o arquivo é UTF-8 com BOM, mas o **conteúdo**
/// está duplo-encodado (bytes UTF-8 foram interpretados como Latin-1 e
/// re-serializados como UTF-8). "Lançamento" virou "LanÃ§amento", "R$ "
/// (com NBSP) virou "R$Â ", "à vista" virou "Ã  vista". Pra recuperar o texto
/// original: decodifica como UTF-8 → re-codifica cada char como Latin-1 →
/// decodifica esses bytes como UTF-8.
///
/// **Skip de valores negativos:** a fatura inclui linhas de pagamento da
/// fatura anterior (`"PAGAMENTO ON LINE"`, `"PAGTO DEBITO AUTOMATICO"`) e
/// eventuais estornos. Ambas têm valor negativo. Como o pagamento será
/// modelado como **transferência** vinda do extrato bancário e estornos não
/// têm contrapartida na fatura líquida que o usuário quer ver, **toda linha
/// com valor negativo é pulada**. Conta quantas foram puladas pra reportar
/// na UI.
struct InterCreditCardCSVReader {
    /// Resultado da leitura: linhas válidas (todas positivas) + contagem de
    /// linhas negativas puladas + ano/mês inferido da maior data do arquivo
    /// (usado pro batch tag, não pra filtro).
    struct Statement {
        let rows: [Row]
        let skippedNegativeCount: Int
    }

    struct Row: Hashable {
        let date: Date
        let description: String
        /// Categoria do Inter (SUPERMERCADO, TRANSPORTE, etc). Mantida como
        /// `notes` da transação — útil pra usuário ver o que o Inter sugeriu,
        /// mas **não** é usada pra mapear na nossa taxonomia (a IA faz).
        let interCategory: String
        /// "Compra à vista" ou "Parcela N/M". Vai pra `notes` também e entra
        /// no `external_id` sintético pra distinguir parcelas do mesmo mês.
        let tipo: String
        /// Magnitude positiva (decimal). Negativos foram filtrados antes.
        let amount: Decimal
    }

    func read(from url: URL) throws -> Statement {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileUnreadable(url)
        }
        return try read(data: data)
    }

    func read(data: Data) throws -> Statement {
        let text = Self.decodeMojibake(data: data)

        let rawRows = Self.parseCSV(text: text)
        guard let header = rawRows.first else {
            throw ImportError.noValidRows
        }

        try Self.validateHeader(header)

        var parsed: [Row] = []
        var skippedNegative = 0
        // O índice "humano" do erro começa em 1 contando o header — assim
        // a mensagem "Linha N: data inválida" corresponde ao que o usuário
        // vê abrindo o CSV em outro programa.
        for (idx, fields) in rawRows.dropFirst().enumerated() {
            let rowNumber = idx + 2

            guard fields.count == header.count else {
                throw ImportError.csvRowFieldCount(row: rowNumber, expected: header.count, got: fields.count)
            }

            let dateStr = fields[0]
            let description = Self.normalizeDescription(fields[1])
            let interCategory = fields[2]
            let tipo = fields[3]
            let valueStr = fields[4]

            guard let date = Self.parseDate(dateStr) else {
                throw ImportError.dateParseFailed(row: rowNumber, raw: dateStr)
            }
            guard let amount = Self.parseAmount(valueStr) else {
                throw ImportError.amountParseFailed(row: rowNumber, raw: valueStr)
            }

            if amount < 0 {
                skippedNegative += 1
                continue
            }

            parsed.append(Row(
                date: date,
                description: description,
                interCategory: interCategory,
                tipo: tipo,
                amount: amount
            ))
        }

        if parsed.isEmpty {
            throw ImportError.noValidRows
        }

        return Statement(rows: parsed, skippedNegativeCount: skippedNegative)
    }

    // MARK: - Encoding (mojibake double-decode)

    /// Recupera o texto original do CSV do Inter. O arquivo é UTF-8 com BOM
    /// mas o conteúdo foi double-encoded (UTF-8 bytes → Latin-1 chars → UTF-8
    /// bytes). Inverte o processo. Se a re-decodificação falhar (arquivo
    /// estranho), cai pro decode UTF-8 direto pra não bloquear o usuário.
    static func decodeMojibake(data: Data) -> String {
        // Strip BOM (EF BB BF) se presente.
        var bytes = data
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes = bytes.subdata(in: 3 ..< bytes.count)
        }

        guard let utf8 = String(data: bytes, encoding: .utf8) else {
            // Fallback: arquivo não é UTF-8 — tenta Latin-1 direto.
            return String(data: bytes, encoding: .isoLatin1) ?? ""
        }

        // Tenta re-encodar como Latin-1; se cada char couber (sempre couber
        // se o conteúdo for Latin-1 puro disfarçado de UTF-8), decoda esses
        // bytes como UTF-8.
        if let latin1Bytes = utf8.data(using: .isoLatin1, allowLossyConversion: false),
           let recovered = String(data: latin1Bytes, encoding: .utf8)
        {
            return recovered
        }

        // Algum char fora do range Latin-1 → não é mojibake duplo, devolve
        // como veio.
        return utf8
    }

    // MARK: - CSV parsing

    /// Parser CSV minimalista — separador `,`, campos quoted com `"`,
    /// escape de `"` dentro de string via `""`. CRLF ou LF como quebra de
    /// linha. Suficiente pro formato do Inter; não tenta ser RFC 4180 completo.
    ///
    /// Implementação por índice em `Array(text)` pra permitir lookahead
    /// explícito (`chars[i+1]`) no caso de aspas escapada `""` — fica
    /// linear de ler.
    static func parseCSV(text: String) -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if inQuotes {
                if ch == "\"" {
                    // Lookahead: "" dentro de string = aspas escapada.
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    currentField.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    // CRLF fora de aspas: o \r anterior caiu no `default`
                    // abaixo e foi pro field. Limpa o trailing \r aqui.
                    if currentField.hasSuffix("\r") {
                        currentField.removeLast()
                    }
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy(\.isEmpty) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                default:
                    currentField.append(ch)
                }
            }
            i += 1
        }

        // Última linha sem newline final.
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy(\.isEmpty) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    private static let expectedHeader = ["Data", "Lançamento", "Categoria", "Tipo", "Valor"]

    private static func validateHeader(_ header: [String]) throws {
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalized == expectedHeader else {
            throw ImportError.csvHeaderMismatch(expected: expectedHeader, got: normalized)
        }
    }

    // MARK: - Date / amount

    /// `dd/MM/yyyy` em pt_BR. Timezone do usuário — a fatura traz só o dia,
    /// então usar local evita drift por UTC.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = TimeZone.current
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        dateFormatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Valor no formato `R$ 14,00` ou `-R$ 5.391,95`. Entre `R$` e o número
    /// existe um NBSP (U+00A0), não um espaço normal. A função tolera tanto
    /// space quanto NBSP pra robustez.
    static func parseAmount(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        var isNegative = false
        if s.hasPrefix("-") {
            isNegative = true
            s.removeFirst()
        }

        // Remove "R$" e qualquer espaço (regular ou NBSP) entre prefixo e número.
        if s.hasPrefix("R$") {
            s.removeFirst(2)
        }
        s = s.filter { !$0.isWhitespace && $0 != "\u{00A0}" }

        // pt-BR: "." é separador de milhar, "," é decimal. Converte pra
        // formato Decimal-friendly.
        s = s.replacingOccurrences(of: ".", with: "")
        s = s.replacingOccurrences(of: ",", with: ".")

        guard let value = Decimal(string: s) else { return nil }
        return isNegative ? -value : value
    }

    // MARK: - Description normalization

    /// O Inter grava descrições com colchete largo de espaços pra alinhar
    /// "merchant + cidade" em colunas de monoespaço (ex:
    /// `"Uber UBER  TRIP HELP U SAO PAULO     BRA"`). Compacta múltiplos
    /// espaços em um único — o dedup e a IA respondem melhor sem o ruído.
    static func normalizeDescription(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Regex `\s+` cobre NBSP também — `isWhitespace` na lib do Swift
        // inclui NBSP.
        return trimmed.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// `external_id` sintético pra dedup. O CSV do Inter não tem ID único
    /// por linha, então construímos a chave a partir de (data + descrição +
    /// valor + tipo). `tipo` no hash diferencia parcelas (Parcela 1/3 vs
    /// 2/3) que apareceriam idênticas senão.
    ///
    /// Prefixo `inter-cc:` distingue do `FITID` do OFX caso descrição/valor
    /// coincidam por acaso entre fontes distintas.
    static func makeExternalId(date: Date, description: String, amount: Decimal, tipo: String) -> String {
        let dateStr = isoDayFormatter.string(from: date)
        let amountStr = NSDecimalNumber(decimal: amount).stringValue
        return "inter-cc:\(dateStr)|\(description)|\(amountStr)|\(tipo)"
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()
}
