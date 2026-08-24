import Foundation

public struct ClassificationService: Sendable {
    private let deterministicRules: [DeterministicRule]
    private let memory: LocalClassificationMemory?

    public init(memory: LocalClassificationMemory? = nil) {
        self.deterministicRules = DeterministicRuleCatalog.current
        self.memory = memory
    }

    public func classify(_ request: ClassificationRequest) throws -> ClassificationResponse {
        try validate(request)
        let memorySnapshot = try memory?.loadSnapshot()

        let results = try request.transactions.map { transaction in
            ClassificationResult(
                transactionID: transaction.id,
                outcome: try classify(transaction, using: request.taxonomy, memorySnapshot: memorySnapshot)
            )
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

    private func classify(
        _ transaction: Transaction,
        using taxonomy: Taxonomy,
        memorySnapshot: LocalClassificationMemorySnapshot?
    ) throws -> ClassificationOutcome {
        if let outcome = memorySnapshot?.outcome(for: transaction, taxonomy: taxonomy) {
            return outcome
        }

        for rule in deterministicRules {
            if let outcome = rule.outcome(for: transaction, taxonomy: taxonomy) {
                return outcome
            }
        }

        return .fallback(reason: .unknown)
    }
}
