import Foundation
import OSLog

/// Monta os argumentos do `claude` CLI pro pipeline de categorização.
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

    /// Item de input pra IA — descrição + valor + data por linha.
    struct Item: Sendable, Encodable {
        let index: Int
        let description: String
        /// Valor com sinal pra IA inferir kind do contexto (CSV/XLSX trazem
        /// sinal antes de normalizar; isso ajuda o modelo a decidir income vs
        /// expense quando a descrição é ambígua, ex: "PIX RECEBIDO" vs "PIX ENVIADO").
        let signedAmount: String
        let date: String   // "yyyy-MM-dd"

        enum CodingKeys: String, CodingKey {
            case index
            case description
            case signedAmount = "signed_amount"
            case date
        }
    }

    /// Few-shot pulled da tabela `categorization_corrections`. Slug em vez de
    /// UUID pra alinhar com o output esperado.
    struct FewShotExample: Sendable {
        let normalizedDescription: String
        let correctedCategorySlug: String
        let correctedSubcategoryName: String?
    }

    /// Categoria raiz exposta pro modelo (resolução slug→UUID acontece no service).
    struct CategoryOption: Sendable {
        let slug: String
        let name: String
        let kind: String           // "expense" | "income" | "transfer"
        let subcategories: [String]
    }

    /// Empacota tudo que o `ClaudeCLIClient.runStructured(...)` precisa.
    struct CLIInvocation: Sendable {
        let systemPrompt: String
        let userPrompt: String
        let jsonSchema: String
    }

    /// Monta a invocação completa pro CLI.
    static func buildInvocation(
        items: [Item],
        categories: [CategoryOption],
        fewShots: [FewShotExample]
    ) throws -> CLIInvocation {
        let systemPrompt = renderSystemPrompt(categories: categories)
        let userPrompt = try renderUserPrompt(items: items, fewShots: fewShots)
        let schema = try jsonSchemaString()

        return CLIInvocation(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            jsonSchema: schema
        )
    }

    // MARK: - System prompt

    private static func renderSystemPrompt(categories: [CategoryOption]) -> String {
        var lines: [String] = []
        lines.append("Você é um classificador de transações financeiras pessoais em português brasileiro.")
        lines.append("")
        lines.append("FORMATO DE SAÍDA OBRIGATÓRIO: sua resposta inteira deve ser UM ÚNICO objeto JSON, começando com `{` e terminando com `}`. NADA antes (sem \"Claro\", \"Aqui está\", \"Vou classificar\", etc), NADA depois, SEM markdown (sem ```json ... ```), SEM comentários. Se você escrever qualquer caractere antes da `{` inicial, o parser quebra e o usuário fica sem categorização.")
        lines.append("")
        lines.append("Sua tarefa: para cada transação recebida, escolher uma categoria raiz e (quando aplicável) uma subcategoria da taxonomia abaixo. O objeto JSON deve ter a chave `results` com um array contendo um item por transação.")
        lines.append("")
        lines.append("Regras:")
        lines.append("- Use SEMPRE o `slug` da categoria raiz no campo `category_slug` (não o nome).")
        lines.append("- `subcategory_name` deve ser exatamente um dos nomes listados sob aquela categoria raiz. Se nenhum encaixa, omita ou deixe nulo.")
        lines.append("- `confidence` é um número entre 0.0 e 1.0 — sua estimativa real de acerto. Quando a descrição for ambígua, abaixe a confidence.")
        lines.append("- Se a transação não se encaixar em nenhuma categoria, use o slug `nao-classificado` com confidence 0.0.")
        lines.append("- O sinal do valor (`signed_amount`) ajuda a desambiguar: positivo costuma ser entrada (income/transfer), negativo costuma ser saída (expense).")
        lines.append("- Lançamentos como PIX, TED, DOC e transferências entre contas próprias usam a raiz `transferencias`.")
        lines.append("")
        lines.append("Taxonomia disponível:")
        for cat in categories {
            lines.append("- \(cat.slug) (\(cat.name)) [\(cat.kind)]:")
            for sub in cat.subcategories {
                lines.append("    - \(sub)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - User prompt

    private static func renderUserPrompt(
        items: [Item],
        fewShots: [FewShotExample]
    ) throws -> String {
        var sections: [String] = []

        if !fewShots.isEmpty {
            sections.append("Exemplos de correções recentes do usuário (use-as como referência forte para padrões semelhantes):")
            var fewShotLines: [String] = []
            for shot in fewShots {
                var line = "- \"\(shot.normalizedDescription)\" → \(shot.correctedCategorySlug)"
                if let sub = shot.correctedSubcategoryName {
                    line += " / \(sub)"
                }
                fewShotLines.append(line)
            }
            sections.append(fewShotLines.joined(separator: "\n"))
            sections.append("")
        }

        sections.append("Classifique as transações abaixo. Devolva um item de saída para CADA `index`.")
        sections.append("")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(items)
        guard let payloadString = String(data: payload, encoding: .utf8) else {
            throw AIError.decoding(
                NSError(domain: "CategorizationPrompt", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Falha ao serializar transações para o prompt"
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
                                "description": "Índice da transação no input."
                            ],
                            "category_slug": [
                                "type": "string",
                                "description": "Slug exato da categoria raiz da taxonomia."
                            ],
                            "subcategory_name": [
                                "type": ["string", "null"],
                                "description": "Nome exato da subcategoria, opcional."
                            ],
                            "confidence": [
                                "type": "number",
                                "minimum": 0.0,
                                "maximum": 1.0,
                                "description": "Confiança da classificação entre 0 e 1."
                            ],
                            "reasoning": [
                                "type": ["string", "null"],
                                "description": "Justificativa curta, opcional. Não inclua dados sensíveis."
                            ]
                        ],
                        "required": ["index", "category_slug", "confidence"]
                    ]
                ]
            ],
            "required": ["results"]
        ]

        let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw AIError.responseParse("Falha ao serializar schema JSON")
        }
        return str
    }

    // MARK: - Parsing da resposta

    /// Resultado decodificado do JSON estruturado.
    struct ClassificationResult: Sendable, Hashable {
        let index: Int
        let categorySlug: String
        let subcategoryName: String?
        let confidence: Double
        let reasoning: String?
    }

    /// Wrapper externo que o modelo devolve (depois de unwrap do `result` do CLI).
    private struct StructuredResponse: Decodable {
        let results: [ResultItem]

        struct ResultItem: Decodable {
            let index: Int
            let categorySlug: String
            let subcategoryName: String?
            let confidence: Double
            let reasoning: String?

            enum CodingKeys: String, CodingKey {
                case index
                case categorySlug = "category_slug"
                case subcategoryName = "subcategory_name"
                case confidence
                case reasoning
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
           let decoded = try? decoder.decode(StructuredResponse.self, from: extracted) {
            return decoded.results.map(Self.normalize)
        }

        let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<não-UTF8>"
        log.ai.error("CategorizationPrompt: resposta não-JSON do Claude CLI — preview: \(String(preview), privacy: .public)")
        throw AIError.decoding(firstError)
    }

    private static func normalize(_ item: StructuredResponse.ResultItem) -> ClassificationResult {
        ClassificationResult(
            index: item.index,
            categorySlug: item.categorySlug,
            subcategoryName: item.subcategoryName.flatMap { $0.isEmpty ? nil : $0 },
            confidence: max(0.0, min(1.0, item.confidence)),
            reasoning: item.reasoning.flatMap { $0.isEmpty ? nil : $0 }
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
                    let slice = text[start...index]
                    return Data(slice.utf8)
                }
            default:
                break
            }
        }
        return nil
    }
}
