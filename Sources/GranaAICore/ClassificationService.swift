import Foundation

public struct ClassificationService: Sendable {
    public init() {}

    public func classify(_ request: ClassificationRequest) throws -> ClassificationResponse {
        try validate(request)

        let results = request.transactions.map { transaction in
            ClassificationResult(transactionID: transaction.id, outcome: classify(transaction, using: request.taxonomy))
        }

        return ClassificationResponse(version: .current, results: results)
    }

    private func validate(_ request: ClassificationRequest) throws {
        guard request.version == .current else {
            throw ClassificationContractError(
                code: .unsupportedVersion,
                message: "Unsupported contract version: \(request.version.rawValue)"
            )
        }

        guard request.taxonomy.isValid else {
            throw ClassificationContractError(
                code: .invalidTaxonomy,
                message: "Taxonomy must include at least one valid category."
            )
        }
    }

    private func classify(_ transaction: Transaction, using taxonomy: Taxonomy) -> ClassificationOutcome {
        if transaction.description.range(
            of: "PADARIA",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil,
            taxonomy.contains(categoryID: "alimentacao", subcategoryID: "padaria")
        {
            return .classified(
                categoryID: "alimentacao",
                subcategoryID: "padaria"
            )
        }

        return .fallback(reason: .unknown)
    }
}
