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

@Test func padariaRuleClassifiesWithGranaAppTaxonomyFixture() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: .current,
        transactions: [
            Transaction(
                id: "tx-padaria-real-taxonomy",
                description: "PADARIA CENTRAL",
                amountInMinorUnits: -1890,
                currencyCode: "BRL"
            ),
        ],
        taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
        context: ClassificationContext(locale: "pt-BR")
    )

    let response = try service.classify(request)

    #expect(response == ClassificationResponse(version: .current, results: [
        ClassificationResult(
            transactionID: "tx-padaria-real-taxonomy",
            outcome: .classified(categoryID: "alimentacao", subcategoryID: "padarias")
        ),
    ]))
}

@Test func recurringCardMerchantRulesClassifyWithGranaAppTaxonomyFixture() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: .current,
        transactions: try FixtureStore.classificationV1Transactions("transactions-recurring-card-merchants.json"),
        taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
        context: ClassificationContext(locale: "pt-BR")
    )
    let expected = try FixtureStore.classificationV1Response("response-recurring-card-merchants.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func broadTravelWordsDoNotClassifyWhenTheyAreNotMerchantPrefixes() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: .current,
        transactions: [
            Transaction(id: "tx-blue-shirt", description: "CAMISA AZUL", currencyCode: "BRL"),
            Transaction(id: "tx-hotel-course", description: "HOTELARIA CURSO", currencyCode: "BRL"),
        ],
        taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
        context: ClassificationContext(locale: "pt-BR")
    )

    let response = try service.classify(request)

    #expect(response == ClassificationResponse(version: .current, results: [
        ClassificationResult(transactionID: "tx-blue-shirt", outcome: .fallback(reason: .unknown)),
        ClassificationResult(transactionID: "tx-hotel-course", outcome: .fallback(reason: .unknown)),
    ]))
}

@Test func userReviewedUnknownRulesClassifyWithGranaAppTaxonomyFixture() throws {
    let service = ClassificationService()
    let request = ClassificationRequest(
        version: .current,
        transactions: try FixtureStore.classificationV1Transactions("transactions-user-reviewed-unknowns.json"),
        taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
        context: ClassificationContext(locale: "pt-BR")
    )
    let expected = try FixtureStore.classificationV1Response("response-user-reviewed-unknowns.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func memoryClassifiesBeforeDeterministicRules() throws {
    let memory = LocalClassificationMemory(fileURL: temporaryMemoryURL())
    try memory.learn(
        LearningRequest(
            version: .current,
            taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
            confirmedClassifications: [
                ConfirmedClassification(
                    description: "  padaria   central  ",
                    categoryID: "compras",
                    subcategoryID: "roupas-e-calcados"
                ),
            ]
        )
    )

    let service = ClassificationService(memory: memory)
    let request = ClassificationRequest(
        version: .current,
        transactions: [
            Transaction(id: "tx-padaria", description: "PADARIA CENTRAL", currencyCode: "BRL"),
        ],
        taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
        context: ClassificationContext(locale: "pt-BR")
    )

    let response = try service.classify(request)

    #expect(response == ClassificationResponse(version: .current, results: [
        ClassificationResult(
            transactionID: "tx-padaria",
            outcome: .classified(categoryID: "compras", subcategoryID: "roupas-e-calcados", source: .memory)
        ),
    ]))
}

@Test func memoryFallsThroughWhenSavedSelectionIsAbsentFromTaxonomy() throws {
    let memory = LocalClassificationMemory(fileURL: temporaryMemoryURL())
    try memory.learn(
        LearningRequest(
            version: .current,
            taxonomy: try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json"),
            confirmedClassifications: [
                ConfirmedClassification(
                    description: "PADARIA CENTRAL",
                    categoryID: "compras",
                    subcategoryID: "roupas-e-calcados"
                ),
            ]
        )
    )

    let service = ClassificationService(memory: memory)
    let request = try FixtureStore.classificationV1Request("request-padaria.json")
    let expected = try FixtureStore.classificationV1Response("response-padaria.json")

    let response = try service.classify(request)

    #expect(response == expected)
}

@Test func memoryLearnOverwritesPreviousSelectionForSameNormalizedDescription() throws {
    let memoryURL = temporaryMemoryURL()
    let memory = LocalClassificationMemory(fileURL: memoryURL)
    let taxonomy = try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json")

    try memory.learn(
        LearningRequest(
            version: .current,
            taxonomy: taxonomy,
            confirmedClassifications: [
                ConfirmedClassification(
                    description: "Zara.com",
                    categoryID: "streaming-e-apps",
                    subcategoryID: "apps-e-softwares"
                ),
            ]
        )
    )
    try memory.learn(
        LearningRequest(
            version: .current,
            taxonomy: taxonomy,
            confirmedClassifications: [
                ConfirmedClassification(
                    description: "  zara.com ",
                    categoryID: "compras",
                    subcategoryID: "roupas-e-calcados"
                ),
            ]
        )
    )

    let snapshot = try JSONDecoder().decode(StoredClassificationMemory.self, from: Data(contentsOf: memoryURL))

    #expect(snapshot.entries == [
        StoredClassificationMemoryEntry(
            normalizedDescription: "ZARA.COM",
            categoryID: "compras",
            subcategoryID: "roupas-e-calcados"
        ),
    ])
}

@Test func corruptedMemoryFailsClassificationInsteadOfFallingBackSilently() throws {
    let memoryURL = temporaryMemoryURL()
    try FileManager.default.createDirectory(
        at: memoryURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("not-json".utf8).write(to: memoryURL)

    let service = ClassificationService(memory: LocalClassificationMemory(fileURL: memoryURL))
    let request = try FixtureStore.classificationV1Request("request-padaria.json")

    #expect(throws: DecodingError.self) {
        try service.classify(request)
    }
}

@Test func granaAppTaxonomyFixtureDecodesToContractShape() throws {
    let taxonomy = try FixtureStore.classificationV1Taxonomy("taxonomy-granaapp.json")

    #expect(taxonomy.categories.count == 23)
    #expect(taxonomy.categories.flatMap(\.subcategories).count == 136)

    let alimentacao = try #require(taxonomy.categories.first { $0.id == "alimentacao" })
    #expect(alimentacao.name == "Alimentação")
    #expect(alimentacao.subcategories.contains(Subcategory(id: "padarias", name: "Padarias")))
}

private func temporaryMemoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("grana-ai-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("memory.v1.json")
}

@Test func requestDecodesFromJSONContract() throws {
    let data = try FixtureStore.classificationV1Data("request-padaria.json")

    let request = try JSONDecoder().decode(ClassificationRequest.self, from: data)

    #expect(request.version == .current)
    #expect(request.transactions.first?.id == "tx-padaria")
    #expect(request.taxonomy.categories.first?.subcategories.first?.id == "padarias")
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
    {"results":[{"categoryId":"alimentacao","outcome":"classified","subcategoryId":"padarias","transactionId":"tx-padaria"}],"version":"classification.v1"}
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
