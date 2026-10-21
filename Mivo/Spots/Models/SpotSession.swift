import Foundation

/// How a Spot session was started. Recorded so that future physical products
/// can be told apart from today's stickers without changing the model.
enum SpotTrigger: String, Codable {
    /// A universal link or `mivo://spot/…` link opened — an NFC tag read in the
    /// background by iOS, a QR code, or a tapped link.
    case link
    /// The person scanned a tag from inside Mivo.
    case inAppScan
    /// A Shortcuts automation or Siri ran the Spot intent.
    case shortcut
    /// The Start button on the Spot.
    case manual
    /// "Test Spot" — runs the same path as a tag tap.
    case test
}

enum SpotCompletionReason: String, Codable {
    /// The timer ran out.
    case timerCompleted
    /// The person tapped the tag again.
    case endedByTag
    /// The person pressed End Spot.
    case endedManually
    /// Another Spot was started.
    case replaced
    /// An open-ended Spot reached its safety limit.
    case expired
    /// The Spot was deleted or switched off while running.
    case spotRemoved
    /// The person signed out.
    case signedOut

    /// Whether the session ran its course rather than being cut short by Mivo.
    var isFriendlyEnd: Bool {
        switch self {
        case .timerCompleted, .endedByTag, .endedManually: return true
        case .replaced, .expired, .spotRemoved, .signedOut: return false
        }
    }
}

/// One app the Spot measures individually. The index is what the monitor
/// extension's event names refer to, so it is fixed when the session starts.
struct SpotTrackedApp: Codable, Equatable, Identifiable {
    var index: Int
    var name: String?
    var tokenData: Data

    var id: Int { index }
}

/// Measured time in one app during a session.
struct SpotAppUsage: Codable, Equatable, Identifiable {
    var index: Int
    var name: String?
    var tokenData: Data?
    var minutes: Int

    var id: Int { index }
}

/// Usage iOS reported for a session. Absent entirely when Screen Time could not
/// be watched — Mivo never fills this in with an estimate.
struct SpotUsageRecord: Codable, Equatable {
    /// Time in everything the Spot covers (apps, categories and sites).
    var totalMinutes: Int
    var perApp: [SpotAppUsage]
}

enum SpotIntentionChoice: String, Codable, CaseIterable, Identifiable {
    case somethingSpecific
    case replyToSomeone
    case shortBreak
    case lookSomethingUp
    case notSure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .somethingSpecific: return "Something specific"
        case .replyToSomeone: return "Reply to someone"
        case .shortBreak: return "A short break"
        case .lookSomethingUp: return "Look something up"
        case .notSure: return "Not sure yet"
        }
    }
}

struct SpotIntentionAnswer: Codable, Equatable {
    var choice: SpotIntentionChoice?
    var note: String?
    var answeredAt: Date

    var displayText: String {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return choice?.title ?? "—"
    }
}

struct SpotSession: Codable, Identifiable, Equatable {
    let id: String
    let spotID: String
    /// Snapshots, so history still reads correctly after a Spot is renamed or deleted.
    var spotName: String
    var spotIcon: String
    var mode: SpotMode
    let startDate: Date
    /// Where the timer ends. Always set; for an open-ended Spot this is the safety limit.
    var plannedEndDate: Date
    var isOpenEnded: Bool
    var endDate: Date?
    var completionReason: SpotCompletionReason?
    var trigger: SpotTrigger
    var trackedApps: [SpotTrackedApp]
    /// True when Mivo was able to watch Screen Time for this session.
    var usageTracked: Bool
    var usage: SpotUsageRecord?
    var intention: SpotIntentionAnswer?
    /// How many times the person chose to continue past a Mivo pause.
    var pausesContinued: Int
    var summarySeen: Bool

    var isRunning: Bool { endDate == nil }

    func activeSeconds(now: Date = Date()) -> TimeInterval {
        max(0, (endDate ?? now).timeIntervalSince(startDate))
    }

    func remainingSeconds(now: Date = Date()) -> TimeInterval {
        max(0, plannedEndDate.timeIntervalSince(now))
    }
}
