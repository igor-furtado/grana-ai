import Foundation

/// Métricas locais da categorização assistida, sem descrições, valores ou
/// qualquer dado financeiro sensível.
actor CategorizationMetricsRecorder {
    static let shared = CategorizationMetricsRecorder()

    private static let storageKey = "GranaAi.categorizationMetrics.v1"
    private static let individualRetention: TimeInterval = 90 * 24 * 60 * 60

    struct Run: Codable, Hashable {
        let id: UUID
        let startedAt: Date
        let model: String
        let total: Int
        let cacheHits: Int
        let fromAI: Int
        let fallback: Int
        let failedChunks: Int
        let latencySeconds: Double
    }

    struct MonthlyAggregate: Codable, Hashable {
        var month: String
        var runs: Int
        var total: Int
        var cacheHits: Int
        var fromAI: Int
        var fallback: Int
        var failedChunks: Int
        var latencySeconds: Double
    }

    private struct Store: Codable {
        var runs: [Run] = []
        var monthly: [String: MonthlyAggregate] = [:]
    }

    func record(_ run: Run) {
        var store = load()
        store.runs.append(run)
        let cutoff = Date().addingTimeInterval(-Self.individualRetention)
        store.runs.removeAll { $0.startedAt < cutoff }

        let key = monthKey(for: run.startedAt)
        var aggregate = store.monthly[key] ?? MonthlyAggregate(
            month: key,
            runs: 0,
            total: 0,
            cacheHits: 0,
            fromAI: 0,
            fallback: 0,
            failedChunks: 0,
            latencySeconds: 0
        )
        aggregate.runs += 1
        aggregate.total += run.total
        aggregate.cacheHits += run.cacheHits
        aggregate.fromAI += run.fromAI
        aggregate.fallback += run.fallback
        aggregate.failedChunks += run.failedChunks
        aggregate.latencySeconds += run.latencySeconds
        store.monthly[key] = aggregate

        save(store)
    }

    private func load() -> Store {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let store = try? JSONDecoder().decode(Store.self, from: data)
        else { return Store() }
        return store
    }

    private func save(_ store: Store) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func monthKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
