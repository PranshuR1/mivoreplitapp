import Foundation

/// Why the companion is working from less data than it could be. Surfaced
/// honestly on the Companion screen — never papered over.
enum CompanionDataLimit: String, Equatable {
    case screenTimeNotAuthorized
    case noProtectedApps
    case noUsageReportYet

    var note: String {
        switch self {
        case .screenTimeNotAuthorized:
            return "Screen Time access is off, so the companion can only react to pauses and focus sessions inside Mivo."
        case .noProtectedApps:
            return "No apps are selected for Mivo to pause yet, so there are no pauses to react to."
        case .noUsageReportYet:
            return "Today's Screen Time total hasn't been reported to Mivo yet."
        }
    }
}

/// Every legitimate input the behaviour engine can see. All of it already
/// exists inside Mivo — there are no new monitors or schedules behind this.
///
/// What is deliberately **not** here, because iOS doesn't expose it: how many
/// times an app was opened, how long the current continuous session has been,
/// which app is on screen right now, or anything about content. A field only
/// belongs in this struct when Mivo can fill it truthfully.
struct CompanionSignals: Equatable {
    var now: Date

    /// `nil` when Screen Time authorization has never been requested.
    var screenTimeAuthorized: Bool?
    var hasProtectedApps: Bool

    /// Today's total from Mivo's existing DeviceActivity report. `nil` when
    /// unavailable (not authorized, or the report extension hasn't run yet).
    var todayScreenMinutes: Int?
    /// Today's target from Mivo's adaptive plan. `nil` while still observing.
    var dailyTargetMinutes: Int?
    /// Mean of Mivo's recorded daily observations, once there are enough days.
    var typicalDailyMinutes: Int?
    var typicalDaysCount: Int

    var appInForeground: Bool
    /// A timed Mivo scroll session is running.
    var mivoSessionActive: Bool
    /// A Mivo Still session or Lock Mode is running.
    var focusActive: Bool
    /// A Mivo pause / check-in screen is on screen right now.
    var pauseInProgress: Bool
    /// Mivo's own late-night protection window is active.
    var mivoLateNightActive: Bool

    /// Pauses Mivo started in the last hour (from `interventionAttempts`).
    var interventionsLastHour: Int

    var lastOutcome: CompanionInterventionOutcome?
    var lastOutcomeDate: Date?
    var minutesAtLastIntervention: Int?
    var minutesAtLastInterventionDayKey: String?
    var lastInterventionDate: Date?
    var cooldownUntil: Date?
    var lastFocusCompletedAt: Date?

    static func neutral(now: Date = Date()) -> CompanionSignals {
        CompanionSignals(
            now: now,
            screenTimeAuthorized: nil,
            hasProtectedApps: false,
            todayScreenMinutes: nil,
            dailyTargetMinutes: nil,
            typicalDailyMinutes: nil,
            typicalDaysCount: 0,
            appInForeground: false,
            mivoSessionActive: false,
            focusActive: false,
            pauseInProgress: false,
            mivoLateNightActive: false,
            interventionsLastHour: 0,
            lastOutcome: nil,
            lastOutcomeDate: nil,
            minutesAtLastIntervention: nil,
            minutesAtLastInterventionDayKey: nil,
            lastInterventionDate: nil,
            cooldownUntil: nil,
            lastFocusCompletedAt: nil
        )
    }
}
