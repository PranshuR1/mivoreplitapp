import Foundation
import SwiftUI

/// What the UI renders. Derived entirely from the behaviour engine.
struct CompanionPresentation: Equatable {
    var state: CompanionState
    var animation: CompanionAnimation
    var behavior: CompanionBehavior
    var severity: CompanionSeverity
    var recommendation: CompanionRecommendation
    var topic: CompanionMessageTopic?
    /// The line the companion *would* say. Intervention surfaces must go
    /// through `claimSpeech()`, which applies frequency and cooldown.
    var message: String?
    var dataLimits: [CompanionDataLimit]

    static let inactive = CompanionPresentation(
        state: .idle, animation: .idleBreathing, behavior: .normalUse, severity: .calm,
        recommendation: .none, topic: nil, message: nil, dataLimits: []
    )
}

/// The one place companion state is decided and stored. Views read
/// `presentation`; adapters feed it signals and events; nothing else decides
/// what the companion is doing.
///
/// With the companion disabled (or before onboarding finishes) every method
/// here is a cheap no-op, so Mivo behaves exactly as it did before Companion.
@MainActor
final class CompanionStateManager: ObservableObject {
    static let shared = CompanionStateManager()

    @Published private(set) var preferences = CompanionPreferences()
    @Published private(set) var runtime = CompanionRuntime()
    @Published private(set) var progress = CompanionProgress()
    @Published private(set) var presentation = CompanionPresentation.inactive
    @Published private(set) var newlyUnlocked: [CompanionMilestone] = []
    /// Set by the `mivo://companion` link (the widget's tap target); the
    /// main tab view presents the Companion screen and clears it.
    @Published var openRequested = false

    private(set) var externalSignals = CompanionSignals.neutral()
    private var pauseInProgress = false
    private var pauseBeganAt: Date?
    private var focusInProgress = false
    private var focusEndsAt: Date?
    private var appNotificationsEnabled = false
    private var loadedKey: String?
    private var persistence: CompanionPersistence?

    private let clock: () -> Date
    private let calendarProvider: () -> Calendar
    private let persistenceFactory: (String) -> CompanionPersistence
    private let sideEffects: CompanionSideEffects

    /// A pause flag that never got resolved (flow dismissed some other way)
    /// stops counting after this long.
    private let pauseExpiry: TimeInterval = 10 * 60
    private let duplicateEventWindow: TimeInterval = 3
    private let focusNudgeDelay: TimeInterval = 20 * 60

    init(
        clock: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { CompanionDay.calendar },
        persistenceFactory: @escaping (String) -> CompanionPersistence = { StorageCompanionPersistence(email: $0) },
        sideEffects: CompanionSideEffects? = nil
    ) {
        self.clock = clock
        self.calendarProvider = calendar
        self.persistenceFactory = persistenceFactory
        self.sideEffects = sideEffects ?? LiveCompanionSideEffects()
    }

    var isActive: Bool { preferences.isActive }
    private var calendar: Calendar { calendarProvider() }

    // MARK: - Lifecycle

    /// Loads (or unloads, for `nil`) the signed-in account's companion data.
    func prepare(forEmail email: String?) {
        let key = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != loadedKey else { return }
        loadedKey = key
        pauseInProgress = false
        focusInProgress = false
        newlyUnlocked = []

        guard let email else {
            persistence = nil
            preferences = CompanionPreferences()
            runtime = CompanionRuntime()
            progress = CompanionProgress()
            presentation = .inactive
            sideEffects.publish(snapshot: nil, preferences: preferences)
            sideEffects.syncNotifications(preferences: preferences, appNotificationsEnabled: false)
            return
        }
        let store = persistenceFactory(email)
        persistence = store
        preferences = store.loadPreferences() ?? CompanionPreferences()
        runtime = store.loadRuntime() ?? CompanionRuntime()
        progress = store.loadProgress() ?? CompanionProgress()
        reevaluate()
        sideEffects.syncNotifications(preferences: preferences, appNotificationsEnabled: appNotificationsEnabled)
    }

    /// Feed the latest externally observed facts. Called on foreground and once
    /// a minute while the app is open.
    func refresh(with signals: CompanionSignals, appNotificationsEnabled: Bool) {
        let notificationsChanged = self.appNotificationsEnabled != appNotificationsEnabled
        externalSignals = signals
        self.appNotificationsEnabled = appNotificationsEnabled
        reevaluate()
        if notificationsChanged {
            sideEffects.syncNotifications(preferences: preferences, appNotificationsEnabled: appNotificationsEnabled)
        }
    }

    // MARK: - Preferences

    func updatePreferences(_ change: (inout CompanionPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        updated.name = CompanionPreferences.sanitizedName(updated.name, for: updated.companionType)
        guard updated != preferences else { return }
        let wasActive = preferences.isActive
        preferences = updated
        persistence?.savePreferences(updated)
        if wasActive && !updated.isActive {
            // Switched off mid-event: drop any in-flight pause/focus so nothing
            // lingers, and stop reacting immediately.
            pauseInProgress = false
            focusInProgress = false
            sideEffects.cancelFocusNudge()
        }
        reevaluate()
        sideEffects.syncNotifications(preferences: updated, appNotificationsEnabled: appNotificationsEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        updatePreferences { $0.isEnabled = enabled }
    }

    func completeOnboarding(name: String, personality: CompanionPersonality) {
        updatePreferences {
            $0.name = name
            $0.personality = personality
            $0.hasCompletedOnboarding = true
            $0.isEnabled = true
        }
    }

    func resetPreferences() {
        updatePreferences { $0 = $0.resetToDefaults() }
    }

    // MARK: - Events

    func interventionBegan() {
        guard preferences.isActive else { return }
        let now = clock()
        if pauseInProgress, let began = pauseBeganAt, now.timeIntervalSince(began) < pauseExpiry { return }
        pauseInProgress = true
        pauseBeganAt = now
        runtime.lastInterventionDate = now
        persistRuntime()
        reevaluate()
    }

    func interventionEnded(continued: Bool) {
        pauseInProgress = false
        pauseBeganAt = nil
        guard preferences.isActive else { reevaluate(); return }

        let now = clock()
        let outcome: CompanionInterventionOutcome = continued ? .continued : .exited
        // The same resolution reported twice in quick succession is one event.
        if runtime.lastOutcome == outcome, let last = runtime.lastOutcomeDate,
           abs(now.timeIntervalSince(last)) < duplicateEventWindow {
            reevaluate()
            return
        }

        let dayKey = CompanionDay.key(now, calendar: calendar)
        runtime.lastOutcome = outcome
        runtime.lastOutcomeDate = now
        runtime.lastInterventionDate = now
        runtime.minutesAtLastIntervention = externalSignals.todayScreenMinutes
        runtime.minutesAtLastInterventionDayKey = dayKey
        runtime.cooldownUntil = now.addingTimeInterval(preferences.interventionFrequency.postInterventionCooldown)
        persistRuntime()

        newlyUnlocked = progress.recordPause(exited: !continued, dayKey: dayKey, today: now, calendar: calendar)
        persistence?.saveProgress(progress)
        reevaluate()
    }

    func focusSessionStarted(endsAt: Date? = nil) {
        guard preferences.isActive else { return }
        focusInProgress = true
        focusEndsAt = endsAt
        sideEffects.cancelFocusNudge()
        reevaluate()
    }

    func focusSessionEnded(completed: Bool) {
        focusInProgress = false
        focusEndsAt = nil
        guard preferences.isActive else { reevaluate(); return }
        if completed {
            let now = clock()
            runtime.lastFocusCompletedAt = now
            persistRuntime()
            newlyUnlocked = progress.recordFocusSession(
                dayKey: CompanionDay.key(now, calendar: calendar), today: now, calendar: calendar
            )
            persistence?.saveProgress(progress)
        }
        reevaluate()
    }

    func acknowledgeUnlocks() { newlyUnlocked = [] }

    func requestOpen() { openRequested = true }

    // MARK: - Speech

    /// Returns the companion's line for an intervention surface *if* it is
    /// allowed to speak now (frequency, daily cap, cooldown, quiet hours), and
    /// records that it did. `nil` means: show the character, say nothing.
    func claimSpeech() -> String? {
        // `topic == nil` is the passive ambient hello, which is never "spoken".
        guard preferences.isActive, presentation.topic != nil, let message = presentation.message else { return nil }
        let now = clock()
        guard CompanionSpeechPolicy.canSpeak(
            runtime: runtime, frequency: preferences.interventionFrequency, now: now, calendar: calendar,
            duringPause: presentation.state == .intervening
        ) else { return nil }
        CompanionSpeechPolicy.recordSpoken(runtime: &runtime, now: now, calendar: calendar)
        persistRuntime()
        return message
    }

    // MARK: - Derived

    var todayRecord: CompanionDayRecord {
        progress.record(for: CompanionDay.key(clock(), calendar: calendar))
    }

    var todaySummary: String {
        let today = todayRecord
        return CompanionMessageProvider.todaySummary(pauses: today.pauses, focusSessions: today.focusSessions)
    }

    var currentStreak: Int { progress.currentStreak(today: clock(), calendar: calendar) }

    /// The state to show in previews and widgets regardless of live behaviour.
    var displayState: CompanionState { presentation.state }

    // MARK: - Evaluation

    func reevaluate() {
        guard preferences.isActive else {
            presentation = .inactive
            publishSharedSnapshot()
            return
        }
        let now = clock()
        let signals = effectiveSignals(at: now)
        let result = CompanionBehaviorEngine(calendar: calendar).evaluate(signals: signals, preferences: preferences)

        let hour = calendar.component(.hour, from: now)
        let context = CompanionMessageContext(
            companionName: preferences.name,
            minutes: signals.todayScreenMinutes,
            targetMinutes: signals.dailyTargetMinutes,
            hour: hour
        )
        var message: String?
        if let topic = result.topic {
            if !result.state.isSilent {
                message = CompanionMessageProvider.message(
                    for: topic, personality: preferences.personality, context: context,
                    variant: runtime.messageVariantCounter
                )
            }
        } else if result.behavior == .normalUse, result.state == .idle {
            // Nothing stands out: a passive hello so Home and the widget aren't
            // blank. It changes with the hour and is never claimed as speech.
            message = CompanionMessageProvider.message(
                for: .ambient, personality: preferences.personality, context: context,
                variant: runtime.messageVariantCounter &+ hour
            )
        }
        presentation = CompanionPresentation(
            state: result.state, animation: result.animation, behavior: result.behavior,
            severity: result.severity, recommendation: result.recommendation,
            topic: result.topic, message: message, dataLimits: result.dataLimits
        )
        if runtime.currentState != result.state {
            runtime.currentState = result.state
            persistRuntime()
        }
        maybeScheduleFocusNudge(result: result, now: now)
        publishSharedSnapshot()
    }

    private func effectiveSignals(at now: Date) -> CompanionSignals {
        var signals = externalSignals
        signals.now = now
        if pauseInProgress, let began = pauseBeganAt, now.timeIntervalSince(began) < pauseExpiry {
            signals.pauseInProgress = true
        } else {
            signals.pauseInProgress = false
        }
        signals.focusActive = signals.focusActive || focusInProgress
        signals.lastOutcome = runtime.lastOutcome
        signals.lastOutcomeDate = runtime.lastOutcomeDate
        signals.minutesAtLastIntervention = runtime.minutesAtLastIntervention
        signals.minutesAtLastInterventionDayKey = runtime.minutesAtLastInterventionDayKey
        signals.lastInterventionDate = runtime.lastInterventionDate
        signals.cooldownUntil = runtime.cooldownUntil
        signals.lastFocusCompletedAt = runtime.lastFocusCompletedAt
        return signals
    }

    private func maybeScheduleFocusNudge(result: CompanionBehaviorResult, now: Date) {
        guard result.behavior == .repeatedIntervention,
              preferences.notificationsEnabled, appNotificationsEnabled,
              !focusInProgress, !pauseInProgress else { return }
        let today = CompanionDay.key(now, calendar: calendar)
        guard runtime.lastFocusNudgeDayKey != today else { return }

        let fireDate = now.addingTimeInterval(focusNudgeDelay)
        // Never schedule into quiet hours, and never into bedtime's deep night.
        guard !preferences.quietHours.contains(fireDate, calendar: calendar),
              preferences.bedtime.phase(at: fireDate, calendar: calendar) != .night else { return }

        runtime.lastFocusNudgeDayKey = today
        persistRuntime()
        let text = CompanionMessageProvider.message(
            for: .focusInvitation, personality: preferences.personality,
            context: CompanionMessageContext(companionName: preferences.name)
        ) ?? "Want to start a focus session?"
        sideEffects.scheduleFocusNudge(text: text, at: fireDate)
    }

    private func publishSharedSnapshot() {
        guard preferences.isActive else {
            sideEffects.publish(snapshot: nil, preferences: preferences)
            return
        }
        let now = clock()
        let today = CompanionDay.key(now, calendar: calendar)
        let record = progress.record(for: today)
        let snapshot = CompanionSharedSnapshot(
            isActive: true,
            companionType: preferences.companionType.rawValue,
            name: preferences.name,
            state: presentation.state.rawValue,
            message: presentation.message,
            pausesToday: record.pauses,
            focusSessionsToday: record.focusSessions,
            dayKey: today,
            focusActive: externalSignals.focusActive || focusInProgress,
            focusEndsAt: focusEndsAt,
            updatedAt: now
        )
        sideEffects.publish(snapshot: snapshot, preferences: preferences)
    }

    private func persistRuntime() {
        persistence?.saveRuntime(runtime)
    }
}
