import Foundation

public struct LocalClassificationMemory: Sendable {
    public static let pathEnvironmentKey = "GRANA_AI_MEMORY_PATH"

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func configured(environment: [String: String] = ProcessInfo.processInfo.environment) -> LocalClassificationMemory {
        LocalClassificationMemory(fileURL: configuredFileURL(environment: environment))
    }

    public static func configuredFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let configuredPath = environment[pathEnvironmentKey], !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GranaAI", isDirectory: true)
            .appendingPathComponent("memory.v1.json")
    }

    public func learn(_ request: LearningRequest) throws {
        try validate(request)

        var snapshot = try loadSnapshot().storage

        for confirmedClassification in request.confirmedClassifications {
            let normalizedDescription = confirmedClassification.description.normalizedForRuleMatching()

            guard !normalizedDescription.isEmpty else {
                continue
            }

            guard request.taxonomy.contains(
                categoryID: confirmedClassification.categoryID,
                subcategoryID: confirmedClassification.subcategoryID
            ) else {
                continue
            }

            snapshot.upsert(
                StoredClassificationMemoryEntry(
                    normalizedDescription: normalizedDescription,
                    categoryID: confirmedClassification.categoryID,
                    subcategoryID: confirmedClassification.subcategoryID
                )
            )
        }

        try write(snapshot)
    }

    func loadSnapshot() throws -> LocalClassificationMemorySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalClassificationMemorySnapshot(storage: StoredClassificationMemory())
        }

        let data = try Data(contentsOf: fileURL)
        return try LocalClassificationMemorySnapshot(storage: JSONDecoder().decode(StoredClassificationMemory.self, from: data))
    }

    private func validate(_ request: LearningRequest) throws {
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

    private func write(_ snapshot: StoredClassificationMemory) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

struct LocalClassificationMemorySnapshot: Sendable {
    var storage: StoredClassificationMemory

    func outcome(for transaction: Transaction, taxonomy: Taxonomy) -> ClassificationOutcome? {
        let normalizedDescription = transaction.description.normalizedForRuleMatching()

        guard !normalizedDescription.isEmpty else {
            return nil
        }

        guard let entry = storage.entries.first(where: { $0.normalizedDescription == normalizedDescription }) else {
            return nil
        }

        guard taxonomy.contains(categoryID: entry.categoryID, subcategoryID: entry.subcategoryID) else {
            return nil
        }

        return .classified(
            categoryID: entry.categoryID,
            subcategoryID: entry.subcategoryID,
            source: .memory
        )
    }
}

struct StoredClassificationMemory: Codable, Equatable, Sendable {
    var version: String
    var entries: [StoredClassificationMemoryEntry]

    init(
        version: String = "classification-memory.v1",
        entries: [StoredClassificationMemoryEntry] = []
    ) {
        self.version = version
        self.entries = entries
    }

    mutating func upsert(_ entry: StoredClassificationMemoryEntry) {
        if let index = entries.firstIndex(where: { $0.normalizedDescription == entry.normalizedDescription }) {
            entries[index] = entry
            return
        }

        entries.append(entry)
    }
}

struct StoredClassificationMemoryEntry: Codable, Equatable, Sendable {
    let normalizedDescription: String
    let categoryID: String
    let subcategoryID: String?

    private enum CodingKeys: String, CodingKey {
        case normalizedDescription
        case categoryID = "categoryId"
        case subcategoryID = "subcategoryId"
    }
}
