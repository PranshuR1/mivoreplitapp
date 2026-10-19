import XCTest
@testable import Mivo

/// The state manager end to end, with an injected clock, calendar, storage and
/// side effects: on/off behaviour, cooldowns, duplicate events, rollover,
/// account switching and restarts.
@MainActor
final class CompanionStateManagerTests: XCTestCase {
    // MARK: Harness

    private final class TestClock {
        var now: Date
        var calendar: Calendar
        init(now: Date, calendar: Calendar) { self.now = now; self.calendar = calendar }
    }

    @MainActor
    private final class SpyEffects: CompanionSideEffects {
        var published: [CompanionSharedSnapshot?] = []
        var notificationSyncs = 0
        var nudges: [(text: String, at: Date)] = []
        var cancelledNudges = 0

        var lastSnapshot: CompanionSharedSnapshot? { published.last ?? nil }

        func publish(snapshot: CompanionSharedSnapshot?, preferences: CompanionPreferences) { published.append(snapshot) }
        func syncNotifications(preferences: CompanionPreferences, appNotificationsEnabled: Bool) { notificationSyncs += 1 }
        func scheduleFocusNudge(text: String, at fireDate: Date) { nudges.append((text, fireDate)) }
        func cancelFocusNudge() { cancelledNudges += 1 }
    }

    @MainActor
    private struct Harness {
        let clock: TestClock
        let effects = SpyEffects()
        let stores: [String: InMemoryCompanionPersistence]
        let manager: CompanionStateManager

        init(
            hour: Int = 14, minute: Int = 0, day: Int = 19, zone: String = "America/New_York",
            stores: [String: InMemoryCompanionPersistence]
        ) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let clock = TestClock(
                now: calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!,
                calendar: calendar
            )
            self.clock = clock
            self.stores = stores
            let effects = self.effects
            manager = CompanionStateManager(
                clock: { clock.now },
                calendar: { clock.calendar },
                // Mirrors StorageCompanionPersistence, which keys by the normalised address.
                persistenceFactory: { stores[$0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] ?? InMemoryCompanionPersistence() },
                sideEffects: effects
            )
        }

        var store: InMemoryCompanionPersistence { stores[Self.email]! }
        static let email = "milo@mivo.test"

        func advance(_ seconds: TimeInterval) { clock.now = clock.now.addingTimeInterval(seconds) }
    }

    private func activePrefs(_ edit: (inout CompanionPreferences) -> Void = { _ in }) -> CompanionPreferences {
        var p = CompanionPreferences()
        p.isEnabled = true
        p.hasCompletedOnboarding = true
        edit(&p)
        return p
    }

    private func harness(
        preferences: CompanionPreferences?, hour: Int = 14, minute: Int = 0, day: Int = 19, zone: String = "America/New_York"
    ) -> Harness {
        let store = InMemoryCompanionPersistence(preferences: preferences)
        let h = Harness(hour: hour, minute: minute, day: day, zone: zone, stores: [Harness.email: store])
        h.manager.prepare(forEmail: Harness.email)
        return h
    }

    private func overTargetSignals(_ now: Date) -> CompanionSignals {
        var s = CompanionSignals.neutral(now: now)
        s.screenTimeAuthorized = true
        s.hasProtectedApps = true
        s.todayScreenMinutes = 100
        s.dailyTargetMinutes = 60
        return s
    }

    // MARK: Disabled and inactive

    func testCompanionOffMeansEveryEventIsANoOp() {
        let h = harness(preferences: nil)
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        h.manager.focusSessionStarted(endsAt: h.clock.now.addingTimeInterval(600))
        h.manager.focusSessionEnded(completed: true)

        XCTAssertFalse(h.manager.isActive)
        XCTAssertEqual(h.manager.presentation, .inactive)
        XCTAssertEqual(h.manager.progress, CompanionProgress())
        XCTAssertNil(h.store.runtime, "nothing is written while off")
        XCTAssertNil(h.manager.claimSpeech())
        XCTAssertNil(h.effects.lastSnapshot, "no snapshot is published for the widget")
    }

    func testEnabledButNotOnboardedIsStillInactive() {
        var p = CompanionPreferences()
        p.isEnabled = true
        let h = harness(preferences: p)
        h.manager.interventionBegan()
        XCTAssertFalse(h.manager.isActive)
        XCTAssertEqual(h.manager.presentation, .inactive)
    }

    func testFinishingOnboardingTurnsItOnAndSavesTheChoices() {
        let h = harness(preferences: nil)
        h.manager.completeOnboarding(name: "  Pip  ", personality: .playful)
        XCTAssertTrue(h.manager.isActive)
        XCTAssertEqual(h.manager.preferences.name, "Pip")
        XCTAssertEqual(h.manager.preferences.personality, .playful)
        XCTAssertEqual(h.store.preferences, h.manager.preferences)
        XCTAssertNotNil(h.effects.lastSnapshot)
        XCTAssertEqual(h.effects.lastSnapshot?.name, "Pip")
    }

    func testSwitchingOffMidPauseDropsEverythingAndStopsRecording() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        XCTAssertEqual(h.manager.presentation.state, .intervening)

        h.manager.setEnabled(false)
        XCTAssertEqual(h.manager.presentation, .inactive)
        XCTAssertNil(h.effects.lastSnapshot, "the widget is cleared")
        XCTAssertGreaterThan(h.effects.cancelledNudges, 0)

        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.totalPauses, 0)
    }

    // MARK: Pauses

    func testAPauseShowsTheCompanionThenRecordsTheOutcomeAndStartsACooldown() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        XCTAssertEqual(h.manager.presentation.state, .intervening)
        XCTAssertNotNil(h.store.runtime?.lastInterventionDate)

        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.totalPauses, 1)
        XCTAssertEqual(h.manager.progress.totalExits, 1)
        XCTAssertEqual(h.manager.todayRecord.pauses, 1)
        XCTAssertEqual(h.manager.runtime.lastOutcome, .exited)
        XCTAssertEqual(
            h.manager.runtime.cooldownUntil,
            h.clock.now.addingTimeInterval(CompanionInterventionFrequency.balanced.postInterventionCooldown)
        )
        XCTAssertEqual(h.manager.newlyUnlocked, [.firstPause])
        XCTAssertEqual(h.manager.presentation.state, .celebrating, "stepping away earns a small celebration")
        XCTAssertEqual(h.store.progress, h.manager.progress, "progress is persisted")
    }

    func testContinuingPastAPauseIsRecordedWithoutAnyCelebrationOrScolding() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: true)
        XCTAssertEqual(h.manager.progress.totalPauses, 1, "going through the pause still counts as intentional")
        XCTAssertEqual(h.manager.progress.totalExits, 0)
        XCTAssertEqual(h.manager.runtime.lastOutcome, .continued)
        XCTAssertNotEqual(h.manager.presentation.state, .concerned)
        XCTAssertNil(h.manager.presentation.message)
    }

    func testRepeatedDeviceActivityEventsAreOneEvent() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        let firstStamp = h.manager.runtime.lastInterventionDate
        h.advance(1)
        h.manager.interventionBegan() // the same pause reported again
        XCTAssertEqual(h.manager.runtime.lastInterventionDate, firstStamp)

        h.manager.interventionEnded(continued: false)
        h.advance(1)
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.totalPauses, 1, "same resolution within a few seconds")

        h.advance(30)
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.totalPauses, 2, "a genuinely new pause counts")
    }

    func testAPauseFlagThatNeverResolvedStopsCountingAfterTenMinutes() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        XCTAssertEqual(h.manager.presentation.state, .intervening)
        h.advance(11 * 60)
        h.manager.reevaluate()
        XCTAssertNotEqual(h.manager.presentation.state, .intervening)
    }

    // MARK: Cooldown

    func testCooldownKeepsTheCompanionRestingUntilItEnds() {
        let h = harness(preferences: activePrefs())
        h.manager.refresh(with: overTargetSignals(h.clock.now), appNotificationsEnabled: false)
        XCTAssertEqual(h.manager.presentation.behavior, .thresholdExceeded)
        XCTAssertEqual(h.manager.presentation.state, .watching)

        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: true)
        h.advance(60) // celebration window irrelevant: it was a continue
        h.manager.reevaluate()
        XCTAssertEqual(h.manager.presentation.state, .resting)
        XCTAssertNil(h.manager.presentation.message)

        h.advance(31 * 60)
        h.manager.reevaluate()
        XCTAssertEqual(h.manager.presentation.state, .watching)
        XCTAssertNotNil(h.manager.presentation.message)
    }

    func testDeviceRestartKeepsTheCooldownBecauseItIsAnAbsoluteTime() {
        let h = harness(preferences: activePrefs())
        h.manager.refresh(with: overTargetSignals(h.clock.now), appNotificationsEnabled: false)
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: true)
        let until = h.manager.runtime.cooldownUntil

        // A fresh manager over the same storage — what a relaunch looks like.
        let relaunched = Harness(stores: h.stores)
        relaunched.clock.now = h.clock.now.addingTimeInterval(120)
        relaunched.manager.prepare(forEmail: Harness.email)
        XCTAssertEqual(relaunched.manager.runtime.cooldownUntil, until)
        relaunched.manager.refresh(with: overTargetSignals(relaunched.clock.now), appNotificationsEnabled: false)
        XCTAssertEqual(relaunched.manager.presentation.state, .resting)
        XCTAssertTrue(relaunched.manager.preferences.isActive)
    }

    // MARK: Speech

    func testTheCompanionSpeaksOncePerGapAndNeverRepeatsItself() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        let first = h.manager.claimSpeech()
        XCTAssertNotNil(first)
        XCTAssertNil(h.manager.claimSpeech(), "a second claim in the same moment is refused")
        XCTAssertEqual(h.manager.runtime.messagesToday, 1)
    }

    func testQuietPersonalityShowsTheCharacterWithoutWords() {
        let h = harness(preferences: activePrefs { $0.personality = .quiet })
        h.manager.interventionBegan()
        XCTAssertEqual(h.manager.presentation.state, .intervening)
        XCTAssertNil(h.manager.presentation.message)
        XCTAssertNil(h.manager.claimSpeech())
    }

    func testFocusAndSleepAreSilentEvenWithAMessageToSay() {
        let h = harness(preferences: activePrefs())
        h.manager.focusSessionStarted(endsAt: h.clock.now.addingTimeInterval(900))
        XCTAssertEqual(h.manager.presentation.state, .focused)
        XCTAssertNil(h.manager.presentation.message)
        XCTAssertTrue(h.effects.lastSnapshot?.focusActive ?? false)
        XCTAssertNotNil(h.effects.lastSnapshot?.focusEndsAt)

        h.manager.focusSessionEnded(completed: false)
        XCTAssertFalse(h.effects.lastSnapshot?.focusActive ?? true)
        XCTAssertEqual(h.manager.progress.totalFocusSessions, 0, "ending early is never counted against anyone")

        let night = harness(preferences: activePrefs(), hour: 2)
        night.manager.interventionBegan()
        XCTAssertEqual(night.manager.presentation.state, .sleeping, "quiet hours keep it asleep")
        XCTAssertNil(night.manager.claimSpeech())
    }

    func testFinishingAFocusSessionIsRewarded() {
        let h = harness(preferences: activePrefs())
        h.manager.focusSessionStarted()
        h.manager.focusSessionEnded(completed: true)
        XCTAssertEqual(h.manager.progress.totalFocusSessions, 1)
        XCTAssertEqual(h.manager.todayRecord.focusSessions, 1)
        XCTAssertEqual(h.manager.newlyUnlocked, [.firstFocus])
        XCTAssertEqual(h.manager.presentation.state, .celebrating)
        XCTAssertEqual(h.manager.todaySummary, "Nice — 1 focus session finished today.")
    }

    // MARK: Changing settings while something is happening

    func testChangingPersonalityMidPauseKeepsThePauseAndSwapsTheWords() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        let gentle = h.manager.presentation.message
        h.manager.updatePreferences { $0.personality = .direct }
        XCTAssertEqual(h.manager.presentation.state, .intervening)
        let direct = h.manager.presentation.message
        XCTAssertNotNil(direct)
        XCTAssertNotEqual(gentle, direct)
        XCTAssertTrue(CompanionMessageProvider.variants(for: .pauseOpening, personality: .direct).contains(direct ?? ""))
    }

    func testRenamingIsSanitisedAndPersisted() {
        let h = harness(preferences: activePrefs())
        h.manager.updatePreferences { $0.name = "  Bob    the   Meerkat of Great Renown  " }
        XCTAssertEqual(h.manager.preferences.name, "Bob the Meerkat", "collapsed, then capped at \(CompanionPreferences.maxNameLength)")
        h.manager.updatePreferences { $0.name = "   " }
        XCTAssertEqual(h.manager.preferences.name, "Milo")
        XCTAssertEqual(h.store.preferences?.name, "Milo")
    }

    func testResetPutsSettingsBackButKeepsProgressAndOnOff() {
        let h = harness(preferences: activePrefs { $0.name = "Pip"; $0.personality = .direct })
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        h.manager.resetPreferences()
        XCTAssertEqual(h.manager.preferences.name, "Milo")
        XCTAssertEqual(h.manager.preferences.personality, .gentle)
        XCTAssertTrue(h.manager.preferences.isActive)
        XCTAssertEqual(h.manager.progress.totalPauses, 1, "resetting settings never wipes progress")
    }

    func testTurningOffNotificationsRemovesWhatWasScheduled() {
        let h = harness(preferences: activePrefs { $0.notificationsEnabled = true })
        let before = h.effects.notificationSyncs
        h.manager.updatePreferences { $0.notificationsEnabled = false }
        XCTAssertGreaterThan(h.effects.notificationSyncs, before)
    }

    // MARK: Focus nudge notification

    func testTheFocusInvitationIsOptInRateLimitedAndNeverScheduledIntoTheNight() {
        func busy(_ now: Date) -> CompanionSignals {
            var signals = CompanionSignals.neutral(now: now)
            signals.screenTimeAuthorized = true
            signals.hasProtectedApps = true
            signals.interventionsLastHour = 3
            return signals
        }

        let off = harness(preferences: activePrefs())
        off.manager.refresh(with: busy(off.clock.now), appNotificationsEnabled: true)
        XCTAssertTrue(off.effects.nudges.isEmpty, "notifications are opt-in")

        let on = harness(preferences: activePrefs { $0.notificationsEnabled = true })
        on.manager.refresh(with: busy(on.clock.now), appNotificationsEnabled: false)
        XCTAssertTrue(on.effects.nudges.isEmpty, "Mivo's own notification setting wins")

        on.manager.refresh(with: busy(on.clock.now), appNotificationsEnabled: true)
        XCTAssertEqual(on.effects.nudges.count, 1)
        on.manager.refresh(with: busy(on.clock.now), appNotificationsEnabled: true)
        XCTAssertEqual(on.effects.nudges.count, 1, "at most one a day")

        let late = harness(preferences: activePrefs { $0.notificationsEnabled = true }, hour: 22, minute: 50)
        late.manager.refresh(with: busy(late.clock.now), appNotificationsEnabled: true)
        XCTAssertTrue(late.effects.nudges.isEmpty, "it would land after bedtime")
    }

    // MARK: Dates and time zones

    func testMidnightStartsAFreshDayWithoutLosingTheStreak() {
        let h = harness(
            preferences: activePrefs { $0.quietHours.isEnabled = false; $0.bedtime.isEnabled = false },
            hour: 23, minute: 55
        )
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.todayRecord.pauses, 1)

        h.advance(10 * 60) // 00:05 the next day
        XCTAssertEqual(h.manager.todayRecord.pauses, 0)
        XCTAssertEqual(h.manager.currentStreak, 1, "yesterday still counts until today has had its chance")

        h.advance(60)
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.todayRecord.pauses, 1)
        XCTAssertEqual(h.manager.currentStreak, 2)
        XCTAssertEqual(h.manager.progress.days.map(\.dayKey), ["2026-10-19", "2026-10-20"])
    }

    func testChangingTimeZoneNeverLosesRecordedDays() {
        let h = harness(preferences: activePrefs())
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.days.map(\.dayKey), ["2026-10-19"])

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        h.clock.calendar = tokyo // the same instant is now the next morning
        h.manager.reevaluate()
        XCTAssertEqual(h.manager.progress.totalPauses, 1)
        XCTAssertEqual(h.manager.todayRecord.pauses, 0)
        XCTAssertEqual(h.manager.progress.record(for: "2026-10-19").pauses, 1)
    }

    // MARK: Accounts and Screen Time authorization

    func testEachAccountHasItsOwnCompanionAndSigningOutClearsTheWidget() {
        let storeA = InMemoryCompanionPersistence(preferences: activePrefs { $0.name = "Ana's" })
        let storeB = InMemoryCompanionPersistence(preferences: activePrefs { $0.name = "Ben's" })
        let h = Harness(stores: ["a@mivo.test": storeA, "b@mivo.test": storeB])

        h.manager.prepare(forEmail: "a@mivo.test")
        XCTAssertEqual(h.manager.preferences.name, "Ana's")
        XCTAssertEqual(h.effects.lastSnapshot?.name, "Ana's")

        h.manager.prepare(forEmail: "B@Mivo.test ")
        XCTAssertEqual(h.manager.preferences.name, "Ben's", "addresses are normalised")

        h.manager.prepare(forEmail: nil)
        XCTAssertFalse(h.manager.isActive)
        XCTAssertEqual(h.manager.preferences, CompanionPreferences())
        XCTAssertNil(h.effects.lastSnapshot)
    }

    func testRevokedScreenTimeAccessDegradesHonestlyAndPausesStillWork() {
        let h = harness(preferences: activePrefs())
        var revoked = overTargetSignals(h.clock.now)
        revoked.screenTimeAuthorized = false
        h.manager.refresh(with: revoked, appNotificationsEnabled: false)
        XCTAssertEqual(h.manager.presentation.behavior, .normalUse, "no usage claims without access")
        XCTAssertEqual(h.manager.presentation.dataLimits, [.screenTimeNotAuthorized])

        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        XCTAssertEqual(h.manager.progress.totalPauses, 1)
    }

    func testNoSelectedAppsIsReportedNotHidden() {
        let h = harness(preferences: activePrefs())
        var s = overTargetSignals(h.clock.now)
        s.hasProtectedApps = false
        s.dailyTargetMinutes = nil
        h.manager.refresh(with: s, appNotificationsEnabled: false)
        XCTAssertEqual(h.manager.presentation.dataLimits, [.noProtectedApps])
    }

    // MARK: Published snapshot

    func testSnapshotCarriesOnlyWhatTheWidgetMayShow() throws {
        let h = harness(preferences: activePrefs { $0.name = "Pip" })
        h.manager.interventionBegan()
        h.manager.interventionEnded(continued: false)
        let snapshot = try XCTUnwrap(h.effects.lastSnapshot)
        XCTAssertEqual(snapshot.name, "Pip")
        XCTAssertEqual(snapshot.companionType, "meerkat")
        XCTAssertEqual(snapshot.pausesToday, 1)
        XCTAssertEqual(snapshot.dayKey, "2026-10-19")
        XCTAssertTrue(snapshot.isActive)
        // The type has no field for app names, durations or usage totals.
        XCTAssertEqual(Set(Mirror(reflecting: snapshot).children.compactMap(\.label)), [
            "isActive", "companionType", "name", "state", "message", "pausesToday", "focusSessionsToday",
            "dayKey", "focusActive", "focusEndsAt", "updatedAt",
        ])
    }
}
