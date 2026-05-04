import Foundation

// Simple data store to keep AI-oriented dataset entries locally.
// This keeps recent session summaries and onboarding profile snapshots that the AI can use
// to personalize recommendations. Data is persisted via StorageService.

struct AIDataEntry: Codable {
    let id: String
    let timestamp: String
    let summary: String
}

struct AIDataStore {
    private static let maxEntries = 50

    static func appendEntry(_ summary: String) {
        var entries = StorageService.load([AIDataEntry].self, forKey: .aiDataset) ?? []
        let entry = AIDataEntry(id: UUID().uuidString, timestamp: ISO8601DateFormatter().string(from: Date()), summary: summary)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        StorageService.save(entries, forKey: .aiDataset)
    }

    static func recentEntries(limit: Int = 5) -> [AIDataEntry] {
        if let entries = StorageService.load([AIDataEntry].self, forKey: .aiDataset) {
            return Array(entries.prefix(limit))
        }
        let legacySummaries = StorageService.load([String].self, forKey: .aiDataset) ?? []
        let entries = legacySummaries.map {
            AIDataEntry(id: UUID().uuidString, timestamp: "Saved profile", summary: $0)
        }
        return Array(entries.prefix(limit))
    }

    static func recentSummary(limit: Int = 5) -> String {
        let items = recentEntries(limit: limit)
        if items.isEmpty { return "No recent session data available." }
        return items.map { "[\($0.timestamp)] \($0.summary)" }.joined(separator: "\n")
    }
}
