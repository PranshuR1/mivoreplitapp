import Foundation

/// Shared wire contract for phone, Mac and future Windows clients. Dates are server-issued.
struct LinkedStudySession: Codable, Equatable, Identifiable {
    var id: UUID
    var task: String
    var status: String
    var requestedAt: String
    var startedAt: String?
    var endedAt: String?
    var lastSeenAt: String?
    var desktopID: UUID?
    var activity: String
    var focusedSeconds: Int
    var distractedSeconds: Int
    var awaySeconds: Int
    var uncertainSeconds: Int

    var isFinished: Bool { status == "finished" || status == "cancelled" }
    var startDate: Date? { Self.date(startedAt) }
    var endDate: Date? { Self.date(endedAt) }
    func isConnected(at now: Date = Date()) -> Bool {
        guard status == "active", let seen = Self.date(lastSeenAt) else { return false }
        return now.timeIntervalSince(seen) < 20 && now.timeIntervalSince(seen) >= -5
    }
    func activityLabel(at now: Date = Date()) -> String {
        if isFinished { return status == "cancelled" ? "Session cancelled" : "Session finished" }
        if status == "waiting" { return "Waiting for your computer" }
        guard isConnected(at: now) else { return "Computer disconnected · time isn't being counted" }
        switch activity {
        case "focus": return "Focused on your computer"
        case "drift": return "Distracted · focus credit paused"
        case "away": return "Away · focus credit paused"
        default: return "Uncertain · choose study apps on your computer"
        }
    }
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct LinkedStudyReward: Codable, Equatable {
    var sessionID: UUID
    var dayKey: String
    var scrollSeconds: Int
}

protocol LinkedStudyBackend: AnyObject {
    func current() async throws -> LinkedStudySession?
    func create(id: UUID, task: String) async throws -> LinkedStudySession
    func finish(id: UUID) async throws -> LinkedStudySession
    func rewards(deviceID: UUID, hasPlus: Bool, timeZone: String) async throws -> [LinkedStudyReward]
}
