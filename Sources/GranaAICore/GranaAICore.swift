import Foundation

public enum GranaAICore {
    public static let currentContractVersion = ContractVersion.current
}

public struct ContractVersion: Codable, Equatable, Sendable {
    public static let current = ContractVersion(rawValue: "classification.v1")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ClassificationRequest: Codable, Equatable, Sendable {
    public let version: ContractVersion
    public let transactions: [Transaction]
    public let taxonomy: Taxonomy
    public let context: ClassificationContext

    public init(
        version: ContractVersion,
        transactions: [Transaction],
        taxonomy: Taxonomy,
        context: ClassificationContext
    ) {
        self.version = version
        self.transactions = transactions
        self.taxonomy = taxonomy
        self.context = context
    }
}

public struct ClassificationJSONCodec: Sendable {
    public init() {}

    public func decodeRequest(from data: Data) throws -> ClassificationRequest {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClassificationContractError(
                code: .invalidJSON,
                message: "Invalid JSON payload."
            )
        }

        do {
            return try JSONDecoder().decode(ClassificationRequest.self, from: data)
        } catch let error as DecodingError where error.isMissingTaxonomy {
            throw ClassificationContractError(
                code: .missingTaxonomy,
                message: "Classification request must include taxonomy."
            )
        } catch let error as DecodingError where error.isMissingContext {
            throw ClassificationContractError(
                code: .missingContext,
                message: "Classification request must include context."
            )
        } catch {
            throw ClassificationContractError(
                code: .malformedPayload,
                message: "Malformed classification request payload."
            )
        }
    }

    public func encodeResponse(_ response: ClassificationResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public func encodeError(_ error: ClassificationContractError) throws -> Data {
        try JSONEncoder().encode(error)
    }
}

public struct Transaction: Codable, Equatable, Sendable {
    public let id: String
    public let description: String
    public let amountInMinorUnits: Int?
    public let currencyCode: String?

    public init(
        id: String,
        description: String,
        amountInMinorUnits: Int? = nil,
        currencyCode: String? = nil
    ) {
        self.id = id
        self.description = description
        self.amountInMinorUnits = amountInMinorUnits
        self.currencyCode = currencyCode
    }
}

public struct Taxonomy: Codable, Equatable, Sendable {
    public let categories: [Category]

    public init(categories: [Category]) {
        self.categories = categories
    }
}

public struct Category: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subcategories: [Subcategory]

    public init(id: String, name: String, subcategories: [Subcategory] = []) {
        self.id = id
        self.name = name
        self.subcategories = subcategories
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subcategories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subcategories = try container.decodeIfPresent([Subcategory].self, forKey: .subcategories) ?? []
    }
}

public struct Subcategory: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ClassificationContext: Codable, Equatable, Sendable {
    public let locale: String?

    public init(locale: String? = nil) {
        self.locale = locale
    }
}

public struct ClassificationResponse: Codable, Equatable, Sendable {
    public let version: ContractVersion
    public let results: [ClassificationResult]

    public init(version: ContractVersion, results: [ClassificationResult]) {
        self.version = version
        self.results = results
    }
}

public struct ClassificationResult: Codable, Equatable, Sendable {
    public let transactionID: String
    public let outcome: ClassificationOutcome

    public init(transactionID: String, outcome: ClassificationOutcome) {
        self.transactionID = transactionID
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case transactionID = "transactionId"
        case outcome
        case fallbackReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        let outcomeValue = try container.decode(String.self, forKey: .outcome)

        switch outcomeValue {
        case "fallback":
            let reason = try container.decode(FallbackReason.self, forKey: .fallbackReason)
            outcome = .fallback(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome,
                in: container,
                debugDescription: "Unsupported classification outcome: \(outcomeValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionID, forKey: .transactionID)

        switch outcome {
        case let .fallback(reason):
            try container.encode("fallback", forKey: .outcome)
            try container.encode(reason, forKey: .fallbackReason)
        }
    }
}

public enum ClassificationOutcome: Equatable, Sendable {
    case fallback(reason: FallbackReason)
}

public enum FallbackReason: String, Codable, Equatable, Sendable {
    case noStrategyAvailable = "no_strategy_available"
}

public struct ClassificationContractError: Codable, Equatable, Error, Sendable {
    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public enum Code: String, Codable, Equatable, Sendable {
        case invalidJSON = "invalid_json"
        case missingTaxonomy = "missing_taxonomy"
        case missingContext = "missing_context"
        case malformedPayload = "malformed_payload"
        case unsupportedVersion = "unsupported_version"
        case invalidTaxonomy = "invalid_taxonomy"
        case internalError = "internal_error"
    }
}

public struct ClassificationService: Sendable {
    public init() {}

    public func classify(_ request: ClassificationRequest) throws -> ClassificationResponse {
        try validate(request)

        let results = request.transactions.map { transaction in
            ClassificationResult(
                transactionID: transaction.id,
                outcome: .fallback(reason: .noStrategyAvailable)
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
}

private extension Taxonomy {
    var isValid: Bool {
        !categories.isEmpty && categories.allSatisfy(\.isValid)
    }
}

private extension DecodingError {
    var isMissingTaxonomy: Bool {
        isMissingKey("taxonomy")
    }

    var isMissingContext: Bool {
        isMissingKey("context")
    }

    private func isMissingKey(_ keyName: String) -> Bool {
        switch self {
        case let .keyNotFound(key, _):
            key.stringValue == keyName
        default:
            false
        }
    }
}

private extension Category {
    var isValid: Bool {
        !id.isEmpty && !name.isEmpty && subcategories.allSatisfy(\.isValid)
    }
}

private extension Subcategory {
    var isValid: Bool {
        !id.isEmpty && !name.isEmpty
    }
}
