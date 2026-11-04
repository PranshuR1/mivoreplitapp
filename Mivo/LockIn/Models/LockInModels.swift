import Foundation

/// The numbers Lock-in runs on, in one place so the screens, the manager and the
/// tests agree.
enum LockInRules {
    /// "Check in by" choices. The lock always ends by then, with or without proof.
    static let durationChoicesMinutes = [30, 60, 120, 240, 480]
    static let defaultDurationMinutes = 120
    static let minimumDurationMinutes = 15

    /// A lock started by mistake can be undone for this long, as long as nothing
    /// has been said to Milo or sent to a keyholder yet.
    static let cancelGrace: TimeInterval = 120

    static let minTaskLength = 3
    static let maxTaskLength = 80

    /// Per lock, so a chat cannot be ground down by repeating until Milo gives in.
    static let maxUserMessages = 20
    static let maxMessageLength = 1000
    static let maxImagesPerMessage = 3
    static let maxUnlockRequests = 3

    /// iOS 26.4 is the first release that can lock an app's Screen Time permission
    /// behind a Screen Time code. On older systems Lock-in still works, but the
    /// person can turn it off in Settings.
    static let screenTimeLockMinimumOS = (major: 26, minor: 4)

    static func supportsScreenTimeLock(
        _ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        let minimum = screenTimeLockMinimumOS
        if version.majorVersion != minimum.major { return version.majorVersion > minimum.major }
        return version.minorVersion >= minimum.minor
    }

    /// The length of a lock, kept between the shortest useful lock and the cap.
    static func duration(minutes: Int) -> TimeInterval {
        let capMinutes = LockInKeys.hardCapHours * 60
        return TimeInterval(min(max(minutes, minimumDurationMinutes), capMinutes) * 60)
    }

    /// One tidy line, or nil when there is nothing to commit to yet.
    static func cleanTask(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count >= minTaskLength else { return nil }
        return String(collapsed.prefix(maxTaskLength))
    }

    static func cleanMessage(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMessageLength))
    }
}

/// A friend who can approve an unlock. Their address stays on the server; the
/// phone only ever holds the masked form.
struct LockInKeyholder: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        /// Invited, hasn't opened the link and agreed yet.
        case pending
        case active
        case revoked
    }

    let id: String
    var name: String
    var emailMasked: String
    var status: Status
}

struct LockInMessage: Codable, Equatable, Identifiable {
    enum Role: String, Codable {
        case user
        case milo
    }

    let id: String
    let role: Role
    let text: String
    /// Photos are judged and dropped, never stored; only how many were shown is kept.
    let imageCount: Int
    let sentAt: Date

    init(id: String = UUID().uuidString, role: Role, text: String, imageCount: Int = 0, sentAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.imageCount = imageCount
        self.sentAt = sentAt
    }
}

/// A request for the keyholder to unlock, and what they answered.
struct LockInUnlockRequest: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case pending
        case approved
        case declined
        case expired
    }

    let id: String
    let sentAt: Date
    var status: Status
    var keyholderNote: String?
    /// What the keyholder was shown: Milo's summary of the evidence.
    let summary: String
}

enum LockInReleaseReason: String, Codable {
    case miloConvinced = "milo_convinced"
    case keyholderApproved = "keyholder_approved"
    /// The check-in time passed without proof. Recorded as not done.
    case timeRanOut = "time_ran_out"
    case cancelledEarly = "cancelled_early"

    /// Whether the lock ended because the work was shown.
    var wasCompleted: Bool {
        self == .miloConvinced || self == .keyholderApproved
    }
}

enum LockInPhase: Equatable {
    case locked
    case waitingOnKeyholder
    case released(LockInReleaseReason)
}

/// The apps a lock covers, as chosen in Apple's picker.
struct ScreenTimeAppSelection: Codable, Equatable {
    /// JSON-encoded `FamilyActivitySelection`; nil until apps are chosen.
    var data: Data?
    /// Names resolved at selection time. Apple does not guarantee a name for
    /// every token, so this can be shorter than `applicationCount`.
    var appNames: [String]
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int

    static let empty = ScreenTimeAppSelection(
        data: nil, appNames: [], applicationCount: 0, categoryCount: 0, webDomainCount: 0
    )

    var isEmpty: Bool { applicationCount + categoryCount + webDomainCount == 0 }

    /// "Instagram, TikTok, YouTube" when every app has a name, otherwise a count.
    var summary: String {
        if isEmpty { return "No apps yet" }
        if applicationCount > 0, appNames.count == applicationCount,
           categoryCount == 0, webDomainCount == 0 {
            return Self.joined(appNames, limit: 3)
        }
        var parts: [String] = []
        if applicationCount > 0 { parts.append(applicationCount == 1 ? "1 app" : "\(applicationCount) apps") }
        if categoryCount > 0 { parts.append(categoryCount == 1 ? "1 category" : "\(categoryCount) categories") }
        if webDomainCount > 0 { parts.append(webDomainCount == 1 ? "1 site" : "\(webDomainCount) sites") }
        return parts.joined(separator: " · ")
    }

    static func joined(_ names: [String], limit: Int) -> String {
        guard names.count > limit else { return names.joined(separator: ", ") }
        return names.prefix(limit).joined(separator: ", ") + " +\(names.count - limit)"
    }
}

/// One lock, from the moment apps are shielded to the moment they are not.
struct LockIn: Codable, Equatable, Identifiable {
    let id: String
    var task: String
    let startedAt: Date
    /// The check-in time. Never past the safety cap.
    let endsAt: Date
    var keyholder: LockInKeyholder?
    var apps: ScreenTimeAppSelection
    var messages: [LockInMessage] = []
    /// Milo's one-line account of the evidence, set once Milo is convinced. It is
    /// what a keyholder is shown.
    var miloSummary: String?
    var requests: [LockInUnlockRequest] = []
    var releasedAt: Date?
    var releaseReason: LockInReleaseReason?

    var isActive: Bool { releasedAt == nil }

    var phase: LockInPhase {
        if let reason = releaseReason { return .released(reason) }
        if pendingRequest != nil { return .waitingOnKeyholder }
        return .locked
    }

    var pendingRequest: LockInUnlockRequest? {
        requests.last { $0.status == .pending }
    }

    var userMessageCount: Int {
        messages.filter { $0.role == .user }.count
    }

    var canSendMessage: Bool {
        isActive && pendingRequest == nil && userMessageCount < LockInRules.maxUserMessages
    }

    var miloIsConvinced: Bool { miloSummary != nil }

    /// Whether a keyholder can be asked right now.
    var canRequestKeyholder: Bool {
        guard isActive, keyholder?.status == .active, pendingRequest == nil else { return false }
        return requests.count < LockInRules.maxUnlockRequests
    }

    func remaining(now: Date = Date()) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    func isPastCheckIn(now: Date = Date()) -> Bool {
        now >= endsAt
    }

    /// An undo for a lock started by mistake: only at the very start, and only
    /// until anything has been said or sent.
    func canCancelFreely(now: Date = Date()) -> Bool {
        isActive
            && now.timeIntervalSince(startedAt) <= LockInRules.cancelGrace
            && messages.isEmpty
            && requests.isEmpty
    }
}

/// Milo's answer to what the person showed.
enum MiloVerdict: String, Codable, Equatable {
    /// The evidence matches the task. Unlock.
    case convinced
    /// Plausible, but Milo needs to see or hear something specific.
    case needsMore = "needs_more"
    /// Doesn't show the work was done.
    case notYet = "not_yet"
}

struct MiloReview: Equatable {
    let verdict: MiloVerdict
    /// What Milo says in the chat.
    let reply: String
    /// One neutral sentence about the evidence, for a keyholder.
    let summary: String
}

enum LockInError: Error, Equatable {
    case notConfigured
    case signedOut
    case offline
    case rateLimited
    case invalidEmail
    case failed

    var message: String {
        switch self {
        case .notConfigured: return "Lock-in's online part isn't set up on this build."
        case .signedOut: return "Sign in again to continue."
        case .offline: return "Mivo can't reach the internet right now."
        case .rateLimited: return "That was a lot of tries. Give it a little while."
        case .invalidEmail: return "That email doesn't look right."
        case .failed: return "Something went wrong. Try again in a moment."
        }
    }
}
