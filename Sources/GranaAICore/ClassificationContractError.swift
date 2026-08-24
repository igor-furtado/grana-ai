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
