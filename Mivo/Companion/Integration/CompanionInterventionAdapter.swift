import Foundation

/// The seam between Mivo's existing intervention flows and the companion.
/// Each existing flow reports what already happened — a pause started, a pause
/// resolved, a focus session ended — and nothing here changes what those flows
/// do. With Companion off, every call is a cheap no-op.
@MainActor
enum CompanionInterventionAdapter {
    /// A Mivo pause screen appeared (reported from `AppViewModel.recordInterventionAttempt`).
    static func pauseBegan() {
        CompanionStateManager.shared.interventionBegan()
    }

    /// A pause resolved (reported from `AppViewModel.resolveInterventionAttempt`):
    /// `continued == false` is the person choosing to step away.
    static func pauseResolved(continued: Bool) {
        CompanionStateManager.shared.interventionEnded(continued: continued)
    }

    /// The mid-session check-in finished and the person chose to carry on.
    static func midSessionCheckInCompleted() {
        CompanionStateManager.shared.interventionEnded(continued: true)
    }

    /// A Mivo Still session started.
    static func focusBegan(endsAt: Date? = nil) {
        CompanionStateManager.shared.focusSessionStarted(endsAt: endsAt)
    }

    /// A Mivo Still session finished. Only a completed one counts as progress;
    /// ending early is simply the end of the session, never a mark against you.
    static func focusEnded(completed: Bool) {
        CompanionStateManager.shared.focusSessionEnded(completed: completed)
    }
}
