import Foundation

enum MivoSessionState: String, Codable {
    case idle
    case pendingSetup
    case active
    case expiredAwaitingChoice
    case finished
}

enum MivoSessionExpirationSource: String, Codable {
    case sessionEnd = "session-end"
    case leaseEnd = "lease-end"
    case appRecovery = "app-recovery"
    case manualFinish = "manual-finish"
    case unknown
}

enum SessionStartError: Error, Equatable, Identifiable {
    case screenTimeUnavailable
    case schedulingFailed(String)
    case noTimeRemaining

    var id: String { message }

    var message: String {
        switch self {
        case .screenTimeUnavailable:
            return "Screen Time blocker is not available on this device."
        case .schedulingFailed(let detail):
            return "Screen Time blocker could not start. \(detail)"
        case .noTimeRemaining:
            return "There is no approved time remaining."
        }
    }
}

enum MivoScreenTimeKeys {
    static let appGroup = "group.com.mivo.mivoapp"
    static let shieldStoreName = "mivo.intervention"

    static let familyActivitySelection = "mivo.familyActivitySelection"
    static let impulseProtectionEnabled = "mivo.impulseProtectionEnabled"
    static let impulseProtectionSignedIn = "mivo.impulseProtectionSignedIn"
    static let learningModeUnlocked = "mivo.learningModeUnlocked"
    static let sessionActive = "mivo.sessionActive"
    static let sessionEndsAt = "mivo.sessionEndsAt"
    static let pendingInterventionSetup = "mivo.pendingInterventionSetup"
    static let pendingInterventionSetupAt = "mivo.pendingInterventionSetupAt"
    static let shieldCountdownUntil = "mivo.shieldCountdownUntil"
    static let shieldCountdownRemaining = "mivo.shieldCountdownRemaining"
    static let checkInIntervalMinutes = "mivo.checkInIntervalMinutes"
    /// How many seconds the "Start" pause lasts before the glimpse. Default 5. Range 3–30.
    static let shieldPauseDuration = "mivo.shieldPauseDuration"

    static let sessionExpiredAt = "mivo.sessionExpiredAt"
    static let sessionExpiredSource = "mivo.sessionExpiredSource"
    static let lastShieldSource = "mivo.lastShieldSource"
    static let lastScheduleError = "mivo.lastScheduleError"

    static let sessionLeaseStartedAt = "mivo.sessionLeaseStartedAt"
    static let sessionLeaseEndsAt = "mivo.sessionLeaseEndsAt"
    static let sessionLeaseDurationSeconds = "mivo.sessionLeaseDurationSeconds"
    static let leaseMonitorScheduledAt = "mivo.leaseMonitorScheduledAt"
    static let leaseMonitorDidStartAt = "mivo.leaseMonitorDidStartAt"
    static let leaseMonitorDidEndAt = "mivo.leaseMonitorDidEndAt"

    static let sessionMonitorScheduledAt = "mivo.sessionMonitorScheduledAt"
    static let sessionMonitorDidStartAt = "mivo.sessionMonitorDidStartAt"
    static let sessionMonitorDidEndAt = "mivo.sessionMonitorDidEndAt"
    static let lastSessionMonitorCallback = "mivo.lastSessionMonitorCallback"

    static let sessionRelockActivityName = "mivo.session.relock"
    static let sessionUsageLimitEventName = "mivo.session.usageLimit"
    // Backup watcher: interval starts now, ends at session-end time.
    // intervalDidEnd fires at session end as a second trigger point.
    static let sessionEndWatcherActivityName = "mivo.session.endwatcher"
    static let sessionEndWatcherUsageLimitEventName = "mivo.session.endwatcher.usageLimit"
    static let leaseEnforcementActivityName = "mivo.lease.enforcement"
    static let blockerSelfTestActivityName = "mivo.blocker.selftest"

    static let defaultCheckInIntervalMinutes = 3
    static let defaultLeaseSeconds: TimeInterval = TimeInterval(defaultCheckInIntervalMinutes * 60)
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
