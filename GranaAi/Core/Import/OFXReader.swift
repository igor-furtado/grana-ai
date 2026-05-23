import Foundation

/// Leitor de OFX (Open Financial Exchange). Suporta as duas variantes que
/// aparecem em extratos brasileiros:
///
/// - **OFX 1.x SGML** — o header tradicional `OFXHEADER:100` seguido por
///   tags estilo `<TAG>valor` (elementos simples não têm `</TAG>` de
///   fechamento; aggregates como `<STMTTRN>...</STMTTRN>` têm). Charset
///   geralmente `1252` (Windows-1252).
///
/// - **OFX 2.x XML** — header `<?xml version="1.0"?>` seguido por XML
///   bem-formado. Charset declarado no XML.
///
/// **Estratégia:** unificar tudo num parser SGML lenient. Pra OFX 2.x,
/// tags fechadas `</TAG>` ainda funcionam — o parser aceita ambos os estilos.
/// Não montamos uma árvore de objetos genérica; vamos direto pros nós que
/// importam (`SONRS/FI`, `STMTRS`, `STMTTRN`, `LEDGERBAL`).
struct OFXReader {
    enum DecodingError: Error {
        case unreadable(URL)
        case noStatements
    }

    func read(from url: URL) throws -> OFXDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileUnreadable(url)
        }
        return try read(data: data)
    }

    /// Exposto pra teste: parseia direto de `Data` (sem tocar disco).
    func read(data: Data) throws -> OFXDocument {
        let (headerInfo, bodyText) = Self.splitHeaderAndBody(data: data)

        let scanner = Scanner(text: bodyText)
        let root = scanner.parse()

        let statements = Self.extractStatements(from: root)
        if statements.isEmpty {
            throw ImportError.noValidRows
        }

        return OFXDocument(
            version: headerInfo.version,
            encoding: headerInfo.encoding,
            charset: headerInfo.charset,
            statements: statements
        )
    }

    // MARK: - Header + body separation

    private struct HeaderInfo {
        var version: String
        var encoding: String
        var charset: String?
    }

    /// Separa o cabeçalho SGML (`OFXHEADER:100\nDATA:OFXSGML\n...`) do corpo.
    /// Decodifica a partir do `CHARSET` declarado — extratos do Inter usam
    /// `1252` (Windows-1252) com acentos. OFX 2.x: detecta header XML e
    /// decodifica como UTF-8.
    ///
    /// Marcado `private` porque o retorno usa `HeaderInfo` (private). Quem
    /// chama é só o `read(data:)` aqui dentro.
    private static func splitHeaderAndBody(data: Data) -> (HeaderInfo, String) {
        // Tentar UTF-8 primeiro pra ler o header (que é sempre ASCII puro).
        // Se falhar, tenta Latin1 (sempre decodifica bytes).
        let probe = String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .isoLatin1) ?? ""

        // OFX 2.x: começa com `<?xml`. Body é tudo, charset vem do XML decl.
        if probe.hasPrefix("<?xml") {
            // Procurar encoding="..." no header XML.
            let encoding: String = {
                if let range = probe.range(of: #"encoding=\"[^\"]+\""#, options: .regularExpression),
                   let q1 = probe[range].range(of: "\""),
                   let q2 = probe[range].range(
                       of: "\"",
                       range: probe.index(after: q1.lowerBound) ..< probe[range].endIndex
                   )
                {
                    return String(probe[range][probe.index(after: q1.lowerBound) ..< q2.lowerBound])
                }
                return "UTF-8"
            }()

            let text = decode(data: data, charsetHint: encoding) ?? probe
            return (HeaderInfo(version: "200", encoding: encoding, charset: nil), text)
        }

        // OFX 1.x: parse linha-a-linha do header até linha em branco.
        var version = "102"
        var encoding = "USASCII"
        var charset: String? = nil

        var bodyStartLine = 0
        let lines = probe.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        var i = 0
        while i < lines.count {
            let raw = String(lines[i])
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                bodyStartLine = i + 1
                break
            }
            // Header é `CHAVE:valor`, tudo ASCII.
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).uppercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "VERSION": version = value
                case "ENCODING": encoding = value
                case "CHARSET": charset = value
                default: break
                }
            }
            i += 1
        }

        let bodyProbe = lines.dropFirst(bodyStartLine).joined(separator: "\n")
        let text = decode(data: data, charsetHint: charset, encodingHint: encoding) ?? bodyProbe

        // Re-tirar o cabeçalho do texto decodificado (precisamos só do body).
        let bodyOnly: String
        if let range = text.range(of: "<OFX>") {
            bodyOnly = String(text[range.lowerBound...])
        } else {
            bodyOnly = text
        }

        return (HeaderInfo(version: version, encoding: encoding, charset: charset), bodyOnly)
    }

    /// Decodifica `Data` respeitando `CHARSET` e `ENCODING` do OFX 1.x.
    /// `1252` → Windows-1252; `USASCII` → ASCII; default → Latin1 (fail-safe,
    /// nunca falha em decodificar bytes arbitrários).
    static func decode(data: Data, charsetHint: String?, encodingHint: String? = nil) -> String? {
        let cs = charsetHint?.uppercased() ?? ""
        let enc = encodingHint?.uppercased() ?? ""

        if cs == "1252" || cs == "WINDOWS-1252" {
            return String(data: data, encoding: .windowsCP1252)
        }
        if enc == "UTF-8" || cs == "UTF-8" {
            return String(data: data, encoding: .utf8)
        }
        if enc == "USASCII" {
            // Bancos brasileiros frequentemente declaram USASCII mas mandam
            // acentos em CP1252. Tentar CP1252 primeiro, fallback pra ASCII.
            return String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .ascii)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - SGML/XML scanner

    /// Nó da árvore intermediária. Aggregate = tem filhos; element = tem
    /// `value` text. Não persistimos — só ponte pro `extractStatements`.
    final class Node {
        let name: String
        var value: String = ""
        var children: [Node] = []
        weak var parent: Node?

        init(name: String, parent: Node?) {
            self.name = name
            self.parent = parent
        }

        func firstChild(_ name: String) -> Node? {
            children.first { $0.name == name }
        }

        func allChildren(_ name: String) -> [Node] {
            children.filter { $0.name == name }
        }

        /// Busca recursiva — útil pra achar `STMTRS`/`CCSTMTRS` etc. soltos
        /// em qualquer profundidade. Retorna a primeira ocorrência por DFS.
        func find(_ name: String) -> Node? {
            for child in children {
                if child.name == name { return child }
                if let nested = child.find(name) { return nested }
            }
            return nil
        }

        func findAll(_ name: String) -> [Node] {
            var result: [Node] = []
            for child in children {
                if child.name == name { result.append(child) }
                result.append(contentsOf: child.findAll(name))
            }
            return result
        }
    }

    /// Tokeniza tags + texto e monta a árvore. Cabe num único pass.
    ///
    /// Regras:
    /// - `<TAG>` abre um nó. Se já há um nó aberto com texto pendente, esse
    ///   nó vira "element" (folha) e fecha implicitamente.
    /// - `</TAG>` fecha o nó mais próximo com esse nome subindo no stack.
    /// - Texto solto vira o `value` do nó aberto.
    final class Scanner {
        private let text: String
        private var index: String.Index

        init(text: String) {
            self.text = text
            self.index = text.startIndex
        }

        func parse() -> Node {
            let root = Node(name: "__ROOT__", parent: nil)
            var current = root

            while index < text.endIndex {
                // Pular whitespace inicial.
                skipWhitespace()
                guard index < text.endIndex else { break }

                if text[index] == "<" {
                    let tag = readTag()
                    if tag.isEmpty { continue }
                    if tag.hasPrefix("/") {
                        // Fechamento. Subir no stack até o tag de mesmo nome.
                        let name = String(tag.dropFirst()).uppercased()
                        var cursor: Node? = current
                        while let c = cursor, c.name != name {
                            cursor = c.parent
                        }
                        if let target = cursor, target !== root {
                            current = target.parent ?? root
                        }
                    } else if tag.hasPrefix("?") || tag.hasPrefix("!") {
                        // `<?xml ...?>` e comentários — ignorar.
                        continue
                    } else {
                        let name = tag.uppercased()
                        // OFX 1.x: novo `<TAG>` no mesmo nível significa que
                        // o irmão anterior (se for um element simples sem
                        // fechamento) está terminado. Como esse parser já
                        // trata texto + tag, o "fechar implícito" ocorre
                        // naturalmente: o nó atual virou o pai do anterior?
                        // Não — em OFX 1.x, elementos simples NÃO viram pai.
                        //
                        // Solução: se o `current` é um "element" (tem `value`
                        // não vazio e ainda nenhum filho), ele é folha e
                        // termina ao encontrar próxima tag. Vamos pro pai
                        // antes de abrir o novo.
                        if !current.value.isEmpty && current.children.isEmpty && current !== root {
                            current = current.parent ?? root
                        }
                        let node = Node(name: name, parent: current)
                        current.children.append(node)
                        current = node
                    }
                } else {
                    // Texto livre até próximo `<`. Acumula no `value` do nó atual.
                    let textChunk = readText()
                    if !textChunk.isEmpty {
                        current.value += textChunk
                    }
                }
            }
            return root
        }

        private func skipWhitespace() {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
        }

        /// Lê `<...>` (sem os delimitadores) avançando o cursor além do `>`.
        private func readTag() -> String {
            guard index < text.endIndex, text[index] == "<" else { return "" }
            index = text.index(after: index)
            var buffer = ""
            while index < text.endIndex {
                let ch = text[index]
                if ch == ">" {
                    index = text.index(after: index)
                    break
                }
                buffer.append(ch)
                index = text.index(after: index)
            }
            return buffer.trimmingCharacters(in: .whitespaces)
        }

        private func readText() -> String {
            var buffer = ""
            while index < text.endIndex, text[index] != "<" {
                buffer.append(text[index])
                index = text.index(after: index)
            }
            return decodeEntities(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// Decoding mínimo de entidades XML — só o necessário pra OFX 2.x e
        /// pra MEMOs com `&amp;` que aparecem em alguns bancos.
        private func decodeEntities(_ s: String) -> String {
            s
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
        }
    }

    // MARK: - Extraction

    /// Caminha a árvore parseada e materializa os `OFXStatement`. Suporta
    /// múltiplos `STMTRS` (extratos com várias contas), e suporta tanto
    /// posicionamento direto `OFX > BANKMSGSRSV1 > STMTTRNRS > STMTRS` quanto
    /// variações vistas em alguns OFXs do Bradesco/Itaú.
    static func extractStatements(from root: Node) -> [OFXStatement] {
        // Cabeçalho institucional do arquivo (`SONRS > FI`). Pode estar
        // ausente; statement-level também trazem BANKID, então é fallback.
        let fiNode = root.find("SONRS")?.firstChild("FI")
        let fileLevelHeader = OFXInstitutionHeader(
            organization: fiNode?.firstChild("ORG")?.value.nonEmpty,
            fid: fiNode?.firstChild("FID")?.value.nonEmpty
        )

        var result: [OFXStatement] = []
        for stmt in root.findAll("STMTRS") {
            if let parsed = parseStatement(stmt, fileLevelHeader: fileLevelHeader) {
                result.append(parsed)
            }
        }
        return result
    }

    private static func parseStatement(
        _ stmt: Node,
        fileLevelHeader: OFXInstitutionHeader
    ) -> OFXStatement? {
        let currency = stmt.firstChild("CURDEF")?.value.nonEmpty ?? "BRL"

        guard let acctNode = stmt.firstChild("BANKACCTFROM") else { return nil }
        guard let acctIdNode = acctNode.firstChild("ACCTID")?.value.nonEmpty,
              let bankIdNode = acctNode.firstChild("BANKID")?.value.nonEmpty
              ?? fileLevelHeader.fid
        else {
            return nil
        }
        let branchId = acctNode.firstChild("BRANCHID")?.value.nonEmpty
        let account = OFXAccountKey(
            bankId: bankIdNode,
            branchId: branchId,
            accountId: acctIdNode
        )

        let transactions = (stmt.firstChild("BANKTRANLIST")?.allChildren("STMTTRN") ?? [])
            .compactMap { parseTransaction($0) }

        let balance: OFXBalance? = {
            guard let bal = stmt.firstChild("LEDGERBAL"),
                  let amount = parseAmount(bal.firstChild("BALAMT")?.value),
                  let asOf = parseOFXDateTime(bal.firstChild("DTASOF")?.value)
            else {
                return nil
            }
            return OFXBalance(amount: amount, asOf: asOf)
        }()

        return OFXStatement(
            currency: currency,
            institutionHeader: fileLevelHeader,
            account: account,
            transactions: transactions,
            balance: balance
        )
    }

    private static func parseTransaction(_ node: Node) -> OFXTransaction? {
        guard let fitid = node.firstChild("FITID")?.value.nonEmpty,
              let amount = parseAmount(node.firstChild("TRNAMT")?.value),
              let date = parseOFXDateTime(node.firstChild("DTPOSTED")?.value)
        else {
            return nil
        }
        let trnType = node.firstChild("TRNTYPE")?.value.uppercased() ?? "OTHER"

        return OFXTransaction(
            trnType: trnType,
            datePosted: date,
            amount: amount,
            fitid: fitid,
            name: node.firstChild("NAME")?.value.nonEmpty,
            memo: node.firstChild("MEMO")?.value.nonEmpty,
            checkNumber: node.firstChild("CHECKNUM")?.value.nonEmpty,
            refNumber: node.firstChild("REFNUM")?.value.nonEmpty
        )
    }

    /// `TRNAMT` é decimal com ponto (formato OFX é fixo, independente de
    /// locale). Aceita negativo, positivo e leading whitespace.
    static func parseAmount(_ raw: String?) -> Decimal? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        // Alguns bancos colocam vírgula como decimal mesmo em OFX (errado mas
        // existe). Trocar pra ponto antes de parsear com locale POSIX.
        if s.contains(","), !s.contains(".") {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// `DTPOSTED` e `DTASOF`: formato OFX é `YYYYMMDD` ou
    /// `YYYYMMDDHHMMSS[.XXX][TZ:offset]`. Implementação tolerante: pega só
    /// `YYYYMMDD` e ignora hora/tz quando presentes — pra Fase 3 a granularidade
    /// "dia" basta.
    static func parseOFXDateTime(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 8 else {
            return nil
        }
        let datePart = String(raw.prefix(8))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: datePart)
    }
}

private extension String {
    /// Retorna `nil` se a string trimmada for vazia. Atalho útil pra `OFX
    /// vem com tag aberta sem valor`.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
