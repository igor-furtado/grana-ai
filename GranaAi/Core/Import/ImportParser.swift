import Foundation

/// Converte uma matriz crua de células `[[String]]` em `[ImportPreviewRow]`
/// aplicando o `ColumnMapping` do template selecionado.
///
/// Responsabilidades:
/// - aplicar `headerRowsToSkip` (pula as N primeiras linhas físicas);
/// - resolver data via `DateFormatter` configurado no template;
/// - resolver valor via `Decimal(string:locale:)` respeitando o separador
///   decimal escolhido (vírgula BR ou ponto US);
/// - reconciliar débito/crédito → `amount` único com sinal (débito vira
///   negativo, crédito vira positivo — convenção confirmada na Fase 3);
/// - tratar BRL com `R$`, espaços e parênteses como negativo (alguns extratos
///   formatam `(123,45)` em vez de `-123,45`).
///
/// **Não consulta o banco** — `findPotentialDuplicates` é responsabilidade
/// do `ImportStore` (parser permanece síncrono e puramente funcional, fácil
/// de testar).
struct ImportParser {
    let mapping: ColumnMapping
    let dateFormat: String
    let decimalSeparator: String

    /// Locale derivado do `decimalSeparator`. `Decimal(string:locale:)` usa o
    /// `decimalSeparator` do locale pra decidir o que é ponto e o que é
    /// vírgula. Usamos `pt_BR` quando `,` é decimal e `en_US_POSIX` quando `.`
    /// é decimal — sem isso, "1.234,56" não parseia em locale en e "1,234.56"
    /// não parseia em locale pt.
    private var numberLocale: Locale {
        decimalSeparator == "," ? Locale(identifier: "pt_BR") : Locale(identifier: "en_US_POSIX")
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = dateFormat
        // POSIX evita que o "MMM" venha localizado e quebre quando o usuário
        // mudar o idioma do sistema.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }

    /// Parsea todas as rows. Linhas inválidas continuam na lista com status
    /// apropriado — UI mostra elas em vermelho/amarelo, usuário decide.
    func parse(rows: [[String]]) -> [ImportPreviewRow] {
        guard mapping.isComplete else { return [] }

        let formatter = dateFormatter
        let locale = numberLocale

        let startIndex = max(0, mapping.headerRowsToSkip)
        guard rows.count > startIndex else { return [] }

        var result: [ImportPreviewRow] = []
        result.reserveCapacity(rows.count - startIndex)

        for (offset, cells) in rows[startIndex...].enumerated() {
            let rowIndex = startIndex + offset
            result.append(parseRow(cells: cells, rowIndex: rowIndex, formatter: formatter, locale: locale))
        }

        return result
    }

    private func parseRow(
        cells: [String],
        rowIndex: Int,
        formatter: DateFormatter,
        locale: Locale
    ) -> ImportPreviewRow {
        // Skip completamente em branco — não vale gerar erro, só ignorar.
        if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .missingFields, derived: nil)
        }

        guard let dateIdx = mapping.date,
              let descIdx = mapping.description,
              let rawDate = cells[safe: dateIdx]?.trimmingCharacters(in: .whitespaces),
              let rawDescription = cells[safe: descIdx]?.trimmingCharacters(in: .whitespaces) else {
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .missingFields, derived: nil)
        }

        guard let date = formatter.date(from: rawDate) else {
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .invalidDate(raw: rawDate), derived: nil)
        }

        let amountResult = resolveAmount(cells: cells, locale: locale)
        switch amountResult {
        case .invalid(let raw):
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .invalidAmount(raw: raw), derived: nil)
        case .missing:
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .missingFields, derived: nil)
        case .ok(let amount):
            let notes: String? = {
                guard let idx = mapping.notes,
                      let raw = cells[safe: idx]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { return nil }
                return raw
            }()

            let derived = DerivedTransaction(
                occurredAt: date,
                amount: amount,
                description: rawDescription,
                notes: notes
            )
            return ImportPreviewRow(rowIndex: rowIndex, rawCells: cells, status: .valid, derived: derived)
        }
    }

    private enum AmountResolution {
        case ok(Decimal)
        case invalid(String)
        case missing
    }

    /// Resolve o `amount` final com sinal. Três caminhos:
    ///
    /// 1. **Valor unificado** (`mapping.amount` definido) — uma coluna só,
    ///    sinal já presente no texto. Aceita "(123,45)" como negativo.
    /// 2. **Débito + Crédito separados** — uma das duas é preenchida; débito
    ///    vira negativo, crédito positivo. Convenção brasileira clássica.
    /// 3. **Ambas vazias** — linha sem valor, marca `missing`.
    private func resolveAmount(cells: [String], locale: Locale) -> AmountResolution {
        if let idx = mapping.amount {
            guard let raw = cells[safe: idx]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return .missing
            }
            if let parsed = Self.parseBRLAmount(raw, locale: locale) {
                return .ok(parsed)
            }
            return .invalid(raw)
        }

        // Débito/Crédito.
        let debitRaw = mapping.debit
            .flatMap { cells[safe: $0]?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let creditRaw = mapping.credit
            .flatMap { cells[safe: $0]?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }

        if debitRaw == nil && creditRaw == nil {
            return .missing
        }

        // Bancos geralmente preenchem só UMA das duas colunas. Se preencherem
        // ambas (raro mas acontece em exportações estranhas), tratamos crédito
        // − débito — preserva o caso simétrico sem inventar regra nova.
        var total: Decimal = 0
        var sawAny = false

        if let raw = debitRaw {
            guard let parsed = Self.parseBRLAmount(raw, locale: locale) else {
                return .invalid(raw)
            }
            // Magnitude (alguns bancos exportam débito com sinal negativo já;
            // outros como positivo. Tomamos o módulo e aplicamos o sinal).
            let magnitude = parsed < 0 ? -parsed : parsed
            total -= magnitude
            sawAny = true
        }
        if let raw = creditRaw {
            guard let parsed = Self.parseBRLAmount(raw, locale: locale) else {
                return .invalid(raw)
            }
            let magnitude = parsed < 0 ? -parsed : parsed
            total += magnitude
            sawAny = true
        }

        if !sawAny { return .missing }
        // Linha onde débito e crédito existem mas dão exatamente zero é caso
        // degenerado: tratamos como `.missing` (vira `.missingFields` no
        // status), que é semanticamente mais próximo do que aconteceu — a
        // linha não representa movimentação real. Antes marcávamos
        // `.invalid` com mensagem "Valor inválido", o que confundia o
        // usuário porque o parsing funcionou; o problema é semântico.
        if total == 0 {
            return .missing
        }
        return .ok(total)
    }

    /// Parser tolerante a formatos brasileiros: aceita "R$", espaços,
    /// separadores de milhar, sinal de menos, e parênteses como negativo
    /// ("(123,45)" → -123.45). `Decimal(string:locale:)` faz o resto
    /// respeitando o decimal separator do locale.
    nonisolated static func parseBRLAmount(_ raw: String, locale: Locale) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s.removeFirst()
            s.removeLast()
        }

        // Remover símbolo de moeda e espaços internos. Não removemos vírgula
        // nem ponto — quem decide é o `locale`.
        s = s.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: "BRL", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // NBSP
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if s.hasPrefix("+") { s.removeFirst() }
        if s.hasPrefix("-") {
            negative.toggle()
            s.removeFirst()
        }

        guard let value = Decimal(string: s, locale: locale) else { return nil }
        return negative ? -value : value
    }
}

/// Subscript seguro: `array[safe: i]` retorna `nil` em vez de crashar quando
/// o índice está fora. Útil pra rows curtas/esparsas onde a coluna mapeada
/// pode não existir.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
