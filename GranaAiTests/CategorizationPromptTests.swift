import Foundation
import Testing
@testable import GranaAi

@Suite("CategorizationPrompt")
struct CategorizationPromptTests {
    @Test("buildRequest preserva taxonomia, contas e exemplos do app")
    func buildRequestPreservesClientPayload() throws {
        let request = CategorizationPrompt.buildRequest(
            items: [
                .init(
                    index: 0,
                    description: "mercado",
                    sign: "expense",
                    accountContext: "Conta Corrente",
                    sourceHint: nil
                ),
            ],
            items: [],
            categories: [
                .init(
                    slug: "alimentacao",
                    name: "Alimentação",
                    kind: "expense",
                    subcategories: ["Supermercados"]
                ),
            ],
            ownAccounts: [
                .init(
                    name: "Banco Inter",
                    typeDisplay: "Conta Corrente",
                    institutionName: "Inter"
                ),
            ],
            fewShots: [
                .init(
                    normalizedDescription: "ifood",
                    correctedCategorySlug: "alimentacao",
                    correctedSubcategoryName: "Restaurantes"
                ),
            ],
            taxonomyVersion: 7
        )

        #expect(request.taxonomyVersion == 7)
        #expect(request.items.count == 1)
        #expect(request.categories.count == 1)
        #expect(request.ownAccounts.count == 1)
        #expect(request.fewShots.count == 1)
        #expect(request.categories[0].slug == "alimentacao")
        #expect(request.fewShots[0].correctedCategorySlug == "alimentacao")
    }

    @Test("parseResults lê resposta JSON estruturada do backend")
    func parseResultsStructuredBackendJSON() throws {
        let payload = """
        {"results":[{"index":0,"category_slug":"alimentacao","subcategory_name":"Supermercados","confidence":0.91}],"metadata":{"provider":"openai","model":"gpt-5.4-mini","from_cache":0,"from_ai":1,"fallback_count":0}}
        """

        let results = try CategorizationPrompt.parseResults(from: Data(payload.utf8))

        #expect(results.count == 1)
        #expect(results[0].index == 0)
        #expect(results[0].categorySlug == "alimentacao")
        #expect(results[0].subcategoryName == "Supermercados")
        #expect(results[0].confidence == 0.91)
    }
}
