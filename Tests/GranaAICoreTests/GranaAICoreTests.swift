import Foundation
import Testing
@testable import GranaAICore
import GranaAITestSupport

@Test func exposesCurrentContractVersion() {
    #expect(GranaAICore.currentContractVersion.rawValue == "classification.v1")
}

@Test func validRequestReturnsFallbackForEachTransaction() throws {
    let service = ClassificationService()
    let request = try FixtureStore.classificationV1Request("request-fallback.json")
    let expected = try FixtureStore.classificationV1Response("response-fallback.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func padariaRuleClassifiesWhenTaxonomyAllowsIt() throws {
    let service = ClassificationService()
    let request = try FixtureStore.classificationV1Request("request-padaria.json")
    let expected = try FixtureStore.classificationV1Response("response-padaria.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func padariaRuleFallsBackWhenTaxonomyDoesNotAllowIt() throws {
    let service = ClassificationService()
    let request = try FixtureStore.classificationV1Request("request-padaria-without-padaria-taxonomy.json")
    let expected = try FixtureStore.classificationV1Response("response-padaria-without-padaria-taxonomy.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func padariaRuleFallsBackWhenSubcategoryDoesNotExist() throws {
    let service = ClassificationService()
    let request = try FixtureStore.classificationV1Request("request-padaria-without-padaria-subcategory.json")
    let expected = try FixtureStore.classificationV1Response("response-padaria-without-padaria-subcategory.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func requestDecodesFromJSONContract() throws {
    let data = try FixtureStore.classificationV1Data("request-padaria.json")

    let request = try JSONDecoder().decode(ClassificationRequest.self, from: data)

    #expect(request.version == .current)
    #expect(request.transactions.first?.id == "tx-padaria")
    #expect(request.taxonomy.categories.first?.subcategories.first?.id == "padaria")
    #expect(request.context.locale == "pt-BR")
}

@Test func categoryDecodesWithoutSubcategories() throws {
    let data = """
    {
      "id": "alimentacao",
      "name": "Alimentação"
    }
    """.data(using: .utf8)!

    let category = try JSONDecoder().decode(Category.self, from: data)

    #expect(category == Category(id: "alimentacao", name: "Alimentação"))
}

@Test func codecRejectsInvalidJSONWithStableError() throws {
    let codec = ClassificationJSONCodec()
    let data = try FixtureStore.classificationV1Data("error-invalid-json.txt")

    #expect(throws: ClassificationContractError(code: .invalidJSON, message: "Invalid JSON payload.")) {
        try codec.decodeRequest(from: data)
    }
}

@Test func codecRejectsMissingTaxonomyWithStableError() throws {
    let codec = ClassificationJSONCodec()
    let data = try FixtureStore.classificationV1Data("error-missing-taxonomy.json")

    #expect(throws: ClassificationContractError(code: .missingTaxonomy, message: "Classification request must include taxonomy.")) {
        try codec.decodeRequest(from: data)
    }
}

@Test func codecRejectsMissingContextWithStableError() throws {
    let codec = ClassificationJSONCodec()
    let data = try FixtureStore.classificationV1Data("error-missing-context.json")

    #expect(throws: ClassificationContractError(code: .missingContext, message: "Classification request must include context.")) {
        try codec.decodeRequest(from: data)
    }
}

@Test func responseEncodesToJSONContract() throws {
    let response = try FixtureStore.classificationV1Response("response-padaria.json")

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(ClassificationResponse.self, from: data)

    #expect(decoded == response)
}

@Test func responseUsesStableJSONFieldNames() throws {
    let response = try FixtureStore.classificationV1Response("response-padaria.json")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(response)
    let json = String(data: data, encoding: .utf8)

    #expect(json == """
    {"results":[{"categoryId":"alimentacao","outcome":"classified","subcategoryId":"padaria","transactionId":"tx-padaria"}],"version":"classification.v1"}
    """)
}

@Test func contractErrorUsesStableJSONCode() throws {
    let error = ClassificationContractError(
        code: .missingTaxonomy,
        message: "Classification request must include taxonomy."
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(error)
    let json = String(data: data, encoding: .utf8)

    #expect(json == """
    {"code":"missing_taxonomy","message":"Classification request must include taxonomy."}
    """)
}

@Test func unsupportedVersionReturnsStableError() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: ContractVersion(rawValue: "classification.v0"),
        transactions: [Transaction(id: "tx-1", description: "PADARIA CENTRAL", amountInMinorUnits: -1890, currencyCode: "BRL")],
        taxonomy: Taxonomy(categories: [Category(id: "alimentacao", name: "Alimentação")]),
        context: ClassificationContext(locale: "pt-BR")
    )

    #expect(throws: ClassificationContractError(code: .unsupportedVersion, message: "Unsupported contract version: classification.v0")) {
        try service.classify(request)
    }
}

@Test func invalidTaxonomyReturnsStableError() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: .current,
        transactions: [Transaction(id: "tx-1", description: "PADARIA CENTRAL", amountInMinorUnits: -1890, currencyCode: "BRL")],
        taxonomy: Taxonomy(categories: []),
        context: ClassificationContext(locale: "pt-BR")
    )

    #expect(throws: ClassificationContractError(code: .invalidTaxonomy, message: "Taxonomy must include at least one valid category.")) {
        try service.classify(request)
    }
}
