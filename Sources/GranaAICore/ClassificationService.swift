import Foundation

public struct ClassificationService: Sendable {
    private let deterministicRules: [DeterministicRule]

    public init() {
        self.deterministicRules = DeterministicRuleCatalog.current
    }

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
        for rule in deterministicRules {
            if let outcome = rule.outcome(for: transaction, taxonomy: taxonomy) {
                return outcome
            }
        }

        return .fallback(reason: .unknown)
    }
}
