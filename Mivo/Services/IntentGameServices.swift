import Foundation

/// Focus Break (formerly "Intent Games") is opt-in, not on by default. The
/// server-side feature flag (`.intentGames`) still gates the feature as a
/// whole; this is the second, local gate that makes it something a user
/// deliberately turns on as a trial — set from a toggle in Settings, read
/// wherever the game entry point decides whether to show itself.
enum FocusBreakTrial {
    private static let key = "mivo.focusBreak.optedIn"

    static var isOptedIn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Stateless — every function takes the `AppViewModel` snapshot and current
/// loan list as parameters and returns a number. No storage of its own;
/// `TimeLoanService` owns the loans, this just does the math against them.
/// `@MainActor` because `AppViewModel` itself only allows access from there.
@MainActor
enum DailyAllowanceService {
    /// Today's gated remaining minutes (every existing protection —
    /// schedule, night, experiment, window — already inherited from
    /// `adaptiveSessionDurationLimit`), minus any loan due back today.
    static func todayRemainingMinutes(appVM: AppViewModel, loans: [TimeLoan], now: Date = Date()) -> Int {
        let today = MivoDay.key(now)
        let gated = appVM.adaptiveSessionDurationLimit(now: now).maxMinutes
        let dueToday = loans
            .filter { $0.status == .pending && $0.repayDate == today }
            .reduce(0) { $0 + $1.borrowedMinutes }
        return max(0, gated - dueToday)
    }

    /// Tomorrow's raw target before any pending loan is subtracted, via the
    /// exact same pure ramp function the adaptive plan already uses for
    /// every other day — not reinvented here.
    static func tomorrowRawTarget(appVM: AppViewModel, now: Date = Date()) -> Int {
        let plan = appVM.adaptiveScreenTimePlan()
        guard !plan.collecting else { return 240 }
        let floor = max(15, appVM.onboardingProfile.dailyScrollGoalMinutes ?? 30)
        return AIService.projectedTargetMinutes(
            dayIndex: plan.dayIndex + 1,
            baseline: plan.baselineMinutes,
            floor: floor,
            comeback: appVM.comebackAnchor
        )
    }

    /// What's actually shown to the user before they borrow more — raw
    /// target minus whatever's already pending against that date.
    static func tomorrowProjectedMinutes(appVM: AppViewModel, loans: [TimeLoan], now: Date = Date()) -> Int {
        let tomorrow = MivoDay.key(offsetFromToday: 1, from: now)
        let raw = tomorrowRawTarget(appVM: appVM, now: now)
        let pending = loans
            .filter { $0.status == .pending && $0.repayDate == tomorrow }
            .reduce(0) { $0 + $1.borrowedMinutes }
        return max(0, raw - pending)
    }

    static func borrowable(needed: Int, appVM: AppViewModel, loans: [TimeLoan], now: Date = Date()) -> Int {
        let tomorrow = MivoDay.key(offsetFromToday: 1, from: now)
        let raw = tomorrowRawTarget(appVM: appVM, now: now)
        let pending = loans
            .filter { $0.status == .pending && $0.repayDate == tomorrow }
            .reduce(0) { $0 + $1.borrowedMinutes }
        return TimeLoanMath.borrowable(needed: needed, tomorrowRawTarget: raw, alreadyPendingAgainstTomorrow: pending)
    }
}

/// Owns the loan ledger. Mirrors `MivoStillStore` — its own small store
/// rather than another array bolted onto `AppViewModel`, deliberately kept
/// separate from `Session`/scrolling-time analytics.
@MainActor
final class TimeLoanService: ObservableObject {
    static let shared = TimeLoanService()

    @Published private(set) var loans: [TimeLoan] = []
    private var loadedEmail: String?

    private init() {}

    func prepare(for appVM: AppViewModel) {
        if let email = appVM.user?.email, loadedEmail != email {
            loadedEmail = email
            loans = StorageService.load([TimeLoan].self, forKey: .timeLoans, email: email) ?? []
        }
        settleDueLoansIfNeeded(appVM: appVM)
    }

    /// Lazy, computed-on-read settlement — no background job, same pattern
    /// as `isMivoSessionActive()`/`isStillLockActive()` elsewhere in this
    /// codebase. A no-op once every due loan is already settled, so it's
    /// safe to call as often as convenient.
    func settleDueLoansIfNeeded(appVM: AppViewModel, now: Date = Date()) {
        let today = MivoDay.key(now)
        guard loans.contains(where: { $0.status == .pending && $0.repayDate <= today }) else { return }
        let todayRawTarget = appVM.adaptiveScreenTimePlan().targetMinutes
        loans = TimeLoanMath.settleDueLoans(loans, today: today, todayRawTarget: todayRawTarget, now: now)
        persist()
    }

    /// A fresh start settles every open loan. Debts taken against the old plan
    /// must not shrink the new plan's targets, and the welcome says nothing is
    /// owed. Uses the same `cleared` outcome as a shortfall that is forgiven.
    func clearPendingLoans(appVM: AppViewModel, now: Date = Date()) {
        prepare(for: appVM)
        let stamp = ISO8601DateFormatter().string(from: now)
        var changed = false
        for index in loans.indices where loans[index].status == .pending {
            loans[index].status = .cleared
            loans[index].repaidAt = stamp
            changed = true
        }
        if changed { persist() }
    }

    func canBorrow(minutes: Int, appVM: AppViewModel) -> Bool {
        DailyAllowanceService.borrowable(needed: minutes, appVM: appVM, loans: loans) >= minutes
    }

    @discardableResult
    func borrow(
        minutes: Int,
        sourceGame: IntentGameType,
        sourceSessionID: String?,
        appVM: AppViewModel,
        now: Date = Date()
    ) -> TimeLoan {
        let loan = TimeLoan(
            id: UUID().uuidString.lowercased(),
            borrowedMinutes: minutes,
            borrowedAt: ISO8601DateFormatter().string(from: now),
            repayDate: MivoDay.key(offsetFromToday: 1, from: now),
            repaidAt: nil,
            status: .pending,
            sourceGame: sourceGame,
            sourceSessionID: sourceSessionID
        )
        loans.insert(loan, at: 0)
        persist()
        return loan
    }

    private func persist() {
        guard let email = loadedEmail else { return }
        StorageService.save(loans, forKey: .timeLoans, email: email)
    }
}

/// Thin — picks games and records history for `DailyTimeBalanceView`'s
/// "played today" stat. The one-attempt-per-unlock-flow rule is enforced by
/// `IntentGameContainerView`'s own local state, not tracked here.
@MainActor
final class IntentGameService: ObservableObject {
    static let shared = IntentGameService()

    @Published private(set) var history: [IntentGameHistoryEntry] = []
    private var loadedEmail: String?

    private init() {}

    func prepare(for appVM: AppViewModel) {
        guard let email = appVM.user?.email, loadedEmail != email else { return }
        loadedEmail = email
        history = StorageService.load([IntentGameHistoryEntry].self, forKey: .intentGameResults, email: email) ?? []
    }

    /// Even rotation, no immediate repeat — backs the picker's "Surprise me."
    func nextGame(excluding: IntentGameType? = nil) -> IntentGameType {
        var pool = IntentGameType.allCases
        if let excluding, pool.count > 1 {
            pool.removeAll { $0 == excluding }
        }
        return pool.randomElement() ?? .focusCards
    }

    func record(_ result: IntentGameResult, now: Date = Date()) {
        let entry = IntentGameHistoryEntry(
            id: result.id,
            date: MivoDay.key(now),
            gameType: result.gameType,
            awardedMinutes: result.awardedMinutes
        )
        history.insert(entry, at: 0)
        history = Array(history.prefix(180))
        if let email = loadedEmail {
            StorageService.save(history, forKey: .intentGameResults, email: email)
        }
        // The whole point of running this as a trial rather than a shipped
        // feature is to actually look at whether it does anything — this is
        // the one line that makes that possible, reusing the same
        // analytics_events table every other admin-visible metric in Mivo
        // already reads from.
        Task {
            await ReferralCampaignService.logEvent(
                "focus_break_result",
                metadata: [
                    "game_type": result.gameType.rawValue,
                    "awarded_minutes": result.awardedMinutes,
                    "completed": result.completed,
                    "needs_reflection": result.needsReflection
                ]
            )
        }
    }

    var minutesEarnedToday: Int {
        let today = MivoDay.todayKey
        return history
            .filter { $0.date == today && $0.awardedMinutes > 0 }
            .reduce(0) { $0 + $1.awardedMinutes }
    }

    var netMinutesToday: Int {
        let today = MivoDay.todayKey
        return history.filter { $0.date == today }.reduce(0) { $0 + $1.awardedMinutes }
    }

    var gamesPlayedToday: Int {
        history.filter { $0.date == MivoDay.todayKey }.count
    }
}

/// Persists negative chance-game outcomes independently from game history so a
/// result can survive the overnight boundary before tomorrow's locked schedule
/// exists. The adjustment is consumed exactly once when a matching schedule is
/// available.
@MainActor
final class DropPathTimeAdjustmentService: ObservableObject {
    static let shared = DropPathTimeAdjustmentService()

    @Published private(set) var adjustments: [DropPathTimeAdjustment] = []
    private var loadedEmail: String?

    private init() {}

    func prepare(for appVM: AppViewModel) {
        guard let email = appVM.user?.email, loadedEmail != email else { return }
        loadedEmail = email
        adjustments = StorageService.load(
            [DropPathTimeAdjustment].self,
            forKey: .dropPathTimeAdjustments,
            email: email
        ) ?? []
    }

    /// Drops penalties still waiting to be applied to a future schedule. They
    /// were set against the plan a fresh start just replaced; ones already
    /// applied stay as history.
    func clearPendingAdjustments(appVM: AppViewModel) {
        prepare(for: appVM)
        let before = adjustments.count
        adjustments.removeAll { $0.isPending }
        if adjustments.count != before { persist() }
    }

    /// Applies the loss to today's next unfinished scheduled window when one
    /// exists. If today's plan is finished (or absent), it is queued for
    /// tomorrow and applied to the first scheduled window once that plan is
    /// chosen.
    func removeFromNextScheduledSession(
        minutes: Int,
        sourceGame: IntentGameType = .dropPath,
        appVM: AppViewModel,
        now: Date = Date()
    ) -> DropPathPenaltyApplication {
        prepare(for: appVM)
        let removal = max(0, minutes)
        let id = UUID().uuidString.lowercased()
        let createdAt = ISO8601DateFormatter().string(from: now)

        if let application = appVM.applyTimeReductionToNextScheduledWindow(
            minutes: removal,
            sourceGame: sourceGame,
            now: now
        ) {
            adjustments.insert(
                DropPathTimeAdjustment(
                    id: id,
                    minutesRemoved: application.minutesRemoved,
                    createdAt: createdAt,
                    targetDate: application.targetDate,
                    sourceGame: sourceGame,
                    appliedWindowID: application.windowID,
                    appliedWindowTitle: application.windowTitle,
                    appliedAt: createdAt
                ),
                at: 0
            )
            persist()
            return DropPathPenaltyApplication(
                minutesRemoved: application.minutesRemoved,
                targetDate: application.targetDate,
                windowTitle: application.windowTitle,
                isPending: false
            )
        }

        let tomorrow = MivoDay.key(offsetFromToday: 1, from: now)
        adjustments.insert(
            DropPathTimeAdjustment(
                id: id,
                minutesRemoved: removal,
                createdAt: createdAt,
                targetDate: tomorrow,
                sourceGame: sourceGame,
                appliedWindowID: nil,
                appliedWindowTitle: nil,
                appliedAt: nil
            ),
            at: 0
        )
        persist()
        return DropPathPenaltyApplication(
            minutesRemoved: removal,
            targetDate: tomorrow,
            windowTitle: nil,
            isPending: true
        )
    }

    /// Called after schedules load and whenever a new daily schedule is saved.
    /// Each pending result gets its own pass so two losses reduce the same next
    /// session cumulatively instead of overwriting one another.
    func applyPendingAdjustments(for date: String, appVM: AppViewModel, now: Date = Date()) {
        prepare(for: appVM)
        let pendingIndices = adjustments.indices.filter {
            adjustments[$0].isPending && adjustments[$0].targetDate <= date
        }
        guard !pendingIndices.isEmpty else { return }

        let appliedAt = ISO8601DateFormatter().string(from: now)
        let calendar = Calendar.current
        let notBeforeMinute: Int? = date == MivoDay.key(now)
            ? calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            : nil
        var changed = false
        for index in pendingIndices.reversed() {
            guard let application = appVM.applyScheduledTimeReduction(
                minutes: adjustments[index].minutesRemoved,
                on: date,
                notBeforeMinute: notBeforeMinute,
                sourceGame: adjustments[index].sourceGame ?? .dropPath
            ) else { continue }
            adjustments[index].appliedWindowID = application.windowID
            adjustments[index].appliedWindowTitle = application.windowTitle
            adjustments[index].appliedAt = appliedAt
            changed = true
        }
        if changed { persist() }
    }

    private func persist() {
        guard let email = loadedEmail else { return }
        adjustments = Array(adjustments.prefix(180))
        StorageService.save(adjustments, forKey: .dropPathTimeAdjustments, email: email)
    }
}
