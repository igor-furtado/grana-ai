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
        case categoryID = "categoryId"
        case subcategoryID = "subcategoryId"
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        let outcomeValue = try container.decode(String.self, forKey: .outcome)

        switch outcomeValue {
        case "classified":
            let categoryID = try container.decode(String.self, forKey: .categoryID)
            let subcategoryID = try container.decodeIfPresent(String.self, forKey: .subcategoryID)
            let source = try container.decodeIfPresent(ClassificationSource.self, forKey: .source)
            outcome = .classified(
                categoryID: categoryID,
                subcategoryID: subcategoryID,
                source: source
            )
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
        case let .classified(categoryID, subcategoryID, source):
            try container.encode("classified", forKey: .outcome)
            try container.encode(categoryID, forKey: .categoryID)
            try container.encodeIfPresent(subcategoryID, forKey: .subcategoryID)
            try container.encodeIfPresent(source, forKey: .source)
        case let .fallback(reason):
            try container.encode("fallback", forKey: .outcome)
            try container.encode(reason, forKey: .fallbackReason)
        }
    }
}

public enum ClassificationOutcome: Equatable, Sendable {
    case classified(categoryID: String, subcategoryID: String?, source: ClassificationSource? = nil)
    case fallback(reason: FallbackReason)
}

public enum ClassificationSource: String, Codable, Equatable, Sendable {
    case memory
}

public enum FallbackReason: String, Codable, Equatable, Sendable {
    case unknown
}

public struct LearningRequest: Codable, Equatable, Sendable {
    public let version: ContractVersion
    public let taxonomy: Taxonomy
    public let confirmedClassifications: [ConfirmedClassification]

    public init(
        version: ContractVersion,
        taxonomy: Taxonomy,
        confirmedClassifications: [ConfirmedClassification]
    ) {
        self.version = version
        self.taxonomy = taxonomy
        self.confirmedClassifications = confirmedClassifications
    }
}

public struct ConfirmedClassification: Codable, Equatable, Sendable {
    public let description: String
    public let categoryID: String
    public let subcategoryID: String?

    public init(description: String, categoryID: String, subcategoryID: String?) {
        self.description = description
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
    }

    private enum CodingKeys: String, CodingKey {
        case description
        case categoryID = "categoryId"
        case subcategoryID = "subcategoryId"
    }
}
