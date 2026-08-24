import Foundation
import GranaAICore

public enum FixtureStore {
    public static func classificationV1Data(_ name: String) throws -> Data {
        try Data(contentsOf: classificationV1URL(name))
    }

    public static func classificationV1String(_ name: String) throws -> String {
        let data = try classificationV1Data(name)
        return String(decoding: data, as: UTF8.self)
    }

    public static func classificationV1Request(_ name: String) throws -> ClassificationRequest {
        try JSONDecoder().decode(ClassificationRequest.self, from: classificationV1Data(name))
    }

    public static func classificationV1Response(_ name: String) throws -> ClassificationResponse {
        try JSONDecoder().decode(ClassificationResponse.self, from: classificationV1Data(name))
    }

    public static func classificationV1Transactions(_ name: String) throws -> [Transaction] {
        try JSONDecoder().decode([Transaction].self, from: classificationV1Data(name))
    }

    public static func classificationV1Taxonomy(_ name: String) throws -> Taxonomy {
        try JSONDecoder().decode(Taxonomy.self, from: classificationV1Data(name))
    }

    public static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func classificationV1URL(_ name: String) -> URL {
        packageRoot()
            .appendingPathComponent("Tests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("classification.v1")
            .appendingPathComponent(name)
    }
}
