import Foundation
import OSLog

/// Monta a entrada do Codex CLI pro pipeline de categorização.
///
/// **Estratégia:**
/// - `system` lista TODAS as categorias raiz do `CategorySeedData` com suas
///   subcategorias. Slugs em vez de UUIDs — UUIDs do seed mudam por banco;
///   slugs são estáveis (ver `CategorySeedData.slug`).
/// - `user` traz as N transações em JSON compacto + few-shots
///   de correções recentes anexados como contexto.
/// - `--json-schema` do CLI força output estruturado — sem isso o modelo
///   pode responder em prosa.
///
/// **`nonisolated`:** chamado do service rodando off-main.
nonisolated enum CategorizationPrompt {
    /// Item de input pra IA — descrição + valor + data + conta por linha.
    struct Item: Encodable {
        let index: Int
        let description: String
        /// Valor com sinal pra IA inferir kind do contexto (CSV/XLSX trazem
        /// sinal antes de normalizar; isso ajuda o modelo a decidir income vs
        /// expense quando a descrição é ambígua, ex: "PIX RECEBIDO" vs "PIX ENVIADO").
        let sign: String // "income" | "expense" | "unknown"
        /// Conta onde a transação está sendo registrada (nome + tipo). Permite
        /// à IA entender o contexto: ex. uma compra dentro de uma conta-cartão
        /// nunca é transferência — é despesa direta no cartão.
        let accountContext: String
        /// Categoria sugerida pelo sistema de origem (ex: coluna "Categoria"
        /// do CSV do Inter: SUPERMERCADO, BARES, TRANSPORTE). **Não é nossa
        /// taxonomia**, mas reduz incerteza em descrições genéricas. `nil`
        /// quando a fonte não fornece.
        let sourceHint: String?

        enum CodingKeys: String, CodingKey {
            case index
            case description
            case sign
            case accountContext = "account_context"
            case sourceHint = "source_hint"
        }
    }

    /// Few-shot pulled da tabela `categorization_corrections`. Slug em vez de
    /// UUID pra alinhar com o output esperado.
    struct FewShotExample {
        let normalizedDescription: String
        let correctedCategorySlug: String
        let correctedSubcategoryName: String?
    }

    /// Categoria raiz exposta pro modelo (resolução slug→UUID acontece no service).
    struct CategoryOption {
        let slug: String
        let name: String
        let kind: String // "expense" | "income" | "transfer"
        let subcategories: [String]
    }

    /// Conta do usuário exposta pro modelo. Serve pra decidir se uma
    /// transação é transferência entre contas próprias (raiz `transferencias`)
    /// ou movimento com terceiro (categoriza pela natureza).
    struct OwnAccountInfo {
        let name: String
        let typeDisplay: String // "Conta Corrente", "Poupança", etc
        let institutionName: String?
    }

    /// Empacota tudo que o `CodexCLIClient.runStructured(...)` precisa.
    struct CLIInvocation {
        let systemPrompt: String
        let userPrompt: String
        let jsonSchema: String
    }

    /// Monta a invocação completa pro CLI.
    static func buildInvocation(
        items: [Item],
        categories: [CategoryOption],
        ownAccounts: [OwnAccountInfo],
        fewShots: [FewShotExample]
    ) throws -> CLIInvocation {
        let systemPrompt = renderSystemPrompt(categories: categories, ownAccounts: ownAccounts)
        let userPrompt = try renderUserPrompt(items: items, fewShots: fewShots)
        let schema = try jsonSchemaString()

        return CLIInvocation(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            jsonSchema: schema
        )
    }

    // MARK: - System prompt

    private static func renderSystemPrompt(
        categories: [CategoryOption],
        ownAccounts: [OwnAccountInfo]
    ) -> String {
        var lines: [String] = []
        lines.append("Você classifica transações financeiras pessoais em pt-BR.")
        lines
            .append(
                "SAÍDA: UM objeto JSON apenas, sem markdown, sem texto antes/depois. Chave `results` = array, um item por transação de entrada."
            )
        lines.append("")
        lines.append("CAMPOS DE SAÍDA:")
        lines.append("- `category_slug`: slug exato da raiz (não o nome).")
        lines.append("- `subcategory_name`: nome exato listado sob aquela raiz, ou null.")
        lines.append("- `confidence` (0–1): estimativa real; ambíguo → baixe.")
        lines.append("- Sem encaixe na taxonomia → slug `nao-classificado` + confidence 0.0.")
        lines.append("")
        lines.append("CAMPOS DE ENTRADA:")
        lines.append("- `sign`: `income`, `expense` ou `unknown`.")
        lines.append("- `account_context` (nome · tipo da conta):")
        lines
            .append(
                "    · Cartão de Crédito → toda compra é despesa direta pela natureza. NUNCA `transferencias`. IOF/tarifas → `impostos-e-taxas`."
            )
        lines.append("    · Demais contas → segue a regra de `transferencias` abaixo.")
        lines
            .append(
                "- `source_hint` (opcional, categoria do banco origem): dica forte pra desambiguar. Mapeie: SUPERMERCADO/RESTAURANTES/BARES→`alimentacao-e-supermercado` · TRANSPORTE→`transporte` · VIAGEM→`viagem` · DROGARIA/SAUDE→`saude-e-medicina` · ENTRETENIMENTO/CULTURA→`entretenimento-e-lazer` · VESTUARIO/COMPRAS/CONSTRUCAO→`compras-pessoais` · SERVICOS→`contas-e-servicos` ou `compras-pessoais` pelo contexto · PAGAMENTOS→avalie · OUTROS→ignore. Se a descrição contradiz o hint claramente, siga a descrição."
            )
        lines.append("")
        lines.append("REGRA CRÍTICA — `transferencias` (sai do dashboard, USE COM CUIDADO):")
        lines
            .append(
                "- USE apenas quando a descrição indica movimentação entre contas DO USUÁRIO listadas abaixo: contraparte bate com nome/instituição de uma conta listada; OU termos \"transferência entre contas\", \"TED própria\"; OU \"aplicação/resgate <produto>\" com conta listada pra esse produto."
            )
        lines
            .append(
                "- NÃO USE quando: contraparte é terceiro (pessoa, empresa, comércio, empregador, governo) → classifique pela natureza · pagamento de fatura de cartão → `creditos-e-emprestimos`/\"Cartão de Crédito\" · investimento sem conta listada pro produto → saída vira `investimentos-e-poupanca`, entrada vira `renda-e-pagamentos`/\"Juros de Investimentos\" ou \"Dividendos\" · descrição genérica \"PIX RECEBIDO/ENVIADO\" sem contraparte → `nao-classificado` confidence baixa."
            )
        lines.append("- Em dúvida, NÃO use `transferencias` — errar pela natureza é melhor que sumir do dashboard.")
        lines.append("")

        if ownAccounts.isEmpty {
            lines.append("Contas do usuário: nenhuma cadastrada — nunca use `transferencias`.")
        } else {
            lines.append("Contas do usuário:")
            for account in ownAccounts {
                var line = "- \(account.name) [\(account.typeDisplay)]"
                if let institution = account.institutionName, !institution.isEmpty {
                    line += " — \(institution)"
                }
                lines.append(line)
            }
        }
        lines.append("")
        lines.append("Taxonomia:")
        for cat in categories {
            lines.append("- \(cat.slug) [\(cat.kind)]: \(cat.subcategories.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - User prompt

    private static func renderUserPrompt(
        items: [Item],
        fewShots _: [FewShotExample]
    ) throws -> String {
        var sections: [String] = []

        sections.append("Classifique as transações abaixo. Devolva um item de saída para CADA `index`.")
        sections.append("")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(items)
        guard let payloadString = String(data: payload, encoding: .utf8) else {
            throw AIError.decoding(
                NSError(domain: "CategorizationPrompt", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Falha ao serializar transações para o prompt",
                ])
            )
        }
        sections.append(payloadString)

        return sections.joined(separator: "\n")
    }

    // MARK: - JSON Schema (passado pro CLI via `--json-schema`)

    /// Schema do output esperado. JSON literal — o CLI passa pro modelo via
    /// structured-output, garantindo aderência sem precisar de tool_use.
    private static func jsonSchemaString() throws -> String {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "results": [
                    "type": "array",
                    "description": "Uma entrada por transação recebida, na ordem dos índices.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "index": [
                                "type": "integer",
                                "description": "Índice da transação no input.",
                            ],
                            "category_slug": [
                                "type": "string",
                                "description": "Slug exato da categoria raiz da taxonomia.",
                            ],
                            "subcategory_name": [
                                "type": ["string", "null"],
                                "description": "Nome exato da subcategoria, opcional.",
                            ],
                            "confidence": [
                                "type": "number",
                                "minimum": 0.0,
                                "maximum": 1.0,
                                "description": "Confiança da classificação entre 0 e 1.",
                            ],
                        ],
                        "required": ["index", "category_slug", "subcategory_name", "confidence"],
                    ],
                ],
            ],
            "required": ["results"],
        ]

        let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw AIError.responseParse("Falha ao serializar schema JSON")
        }
        return str
    }

    // MARK: - Parsing da resposta

    /// Resultado decodificado do JSON estruturado.
    struct ClassificationResult: Hashable {
        let index: Int
        let categorySlug: String
        let subcategoryName: String?
        let confidence: Double
    }

    /// Wrapper externo que o modelo devolve (depois de unwrap do `result` do CLI).
    private struct StructuredResponse: Decodable {
        let results: [ResultItem]

        struct ResultItem: Decodable {
            let index: Int
            let categorySlug: String
            let subcategoryName: String?
            let confidence: Double?

            enum CodingKeys: String, CodingKey {
                case index
                case categorySlug = "category_slug"
                case subcategoryName = "subcategory_name"
                case confidence
            }
        }
    }

    /// Decodifica a resposta JSON (já desempacotada do wrapper do CLI).
    ///
    /// **Tolerante a prose.** `--json-schema` do CLI não é estritamente
    /// enforçado quando se usa auth de assinatura (vs. API key) — o modelo
    /// pode responder em prosa com o JSON embutido. Esta função:
    /// 1. Tenta parse direto. Se passar, ótimo.
    /// 2. Se falhar, extrai o primeiro bloco `{...}` balanceado e tenta de novo.
    /// 3. Se falhar de novo, loga os primeiros 500 chars da resposta crua pra
    ///    diagnóstico e lança `AIError.decoding`.
    static func parseResults(from data: Data) throws -> [ClassificationResult] {
        let decoder = JSONDecoder()

        let firstError: Error
        do {
            let decoded = try decoder.decode(StructuredResponse.self, from: data)
            return decoded.results.map(Self.normalize)
        } catch {
            firstError = error
        }

        if let extracted = extractFirstJSONObject(from: data),
           let decoded = try? decoder.decode(StructuredResponse.self, from: extracted)
        {
            return decoded.results.map(Self.normalize)
        }

        let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<não-UTF8>"
        log.ai
            .error(
                "CategorizationPrompt: resposta não-JSON do Codex CLI — preview: \(String(preview), privacy: .public)"
            )
        throw AIError.decoding(firstError)
    }

    private static func normalize(_ item: StructuredResponse.ResultItem) -> ClassificationResult {
        ClassificationResult(
            index: item.index,
            categorySlug: item.categorySlug,
            subcategoryName: item.subcategoryName.flatMap { $0.isEmpty ? nil : $0 },
            confidence: item.confidence.map { max(0.0, min(1.0, $0)) } ?? 0.0
        )
    }

    /// Extrai o primeiro objeto JSON balanceado (`{...}`) da resposta,
    /// ignorando prose, fences markdown (` ```json `) e texto ao redor.
    /// Conta chaves com awareness de strings e escapes — não é regex.
    private static func extractFirstJSONObject(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var escapeNext = false

        for index in text.indices {
            let ch = text[index]

            if escapeNext {
                escapeNext = false
                continue
            }

            if inString {
                if ch == "\\" { escapeNext = true }
                else if ch == "\"" { inString = false }
                continue
            }

            switch ch {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { startIndex = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start = startIndex {
                    let slice = text[start ... index]
                    return Data(slice.utf8)
                }
            default:
                break
            }
        }
        return nil
    }
}
