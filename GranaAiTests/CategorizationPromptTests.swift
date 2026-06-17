import Foundation
import Testing
@testable import GranaAi

@Suite("CategorizationPrompt")
struct CategorizationPromptTests {
    @Test("JSON schema exige todas as propriedades do item, incluindo subcategoria nula")
    func jsonSchemaRequiresAllItemProperties() throws {
        let invocation = try CategorizationPrompt.buildInvocation(
            items: [
                .init(
                    index: 0,
                    description: "mercado",
                    sign: "expense",
                    accountContext: "Conta Corrente",
                    sourceHint: nil
                ),
            ],
            categories: [],
            ownAccounts: [],
            fewShots: []
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(invocation.jsonSchema.utf8)) as? [String: Any]
        )
        let properties = try #require(object["properties"] as? [String: Any])
        let results = try #require(properties["results"] as? [String: Any])
        let items = try #require(results["items"] as? [String: Any])
        let required = try #require(items["required"] as? [String])

        #expect(required.contains("index"))
        #expect(required.contains("category_slug"))
        #expect(required.contains("subcategory_name"))
        #expect(required.contains("confidence"))
    }
}
