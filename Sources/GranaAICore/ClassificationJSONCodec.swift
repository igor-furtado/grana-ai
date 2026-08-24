import Foundation

public struct ClassificationJSONCodec: Sendable {
    public init() {}

    public func decodeRequest(from data: Data) throws -> ClassificationRequest {
        try decodeJSONPayload(from: data) {
            try JSONDecoder().decode(ClassificationRequest.self, from: data)
        }
    }

    public func decodeLearningRequest(from data: Data) throws -> LearningRequest {
        try decodeJSONPayload(from: data) {
            try JSONDecoder().decode(LearningRequest.self, from: data)
        }
    }

    public func encodeResponse(_ response: ClassificationResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public func encodeError(_ error: ClassificationContractError) throws -> Data {
        try JSONEncoder().encode(error)
    }

    private func decodeJSONPayload<T>(from data: Data, decode: () throws -> T) throws -> T {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClassificationContractError(
                code: .invalidJSON,
                message: "Invalid JSON payload."
            )
        }

        do {
            return try decode()
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
