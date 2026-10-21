import XCTest
@testable import Mivo

/// Pure companion logic: the behaviour engine, schedules, copy, progression,
/// persistence shape and the animation function. Every date here is built in an
/// explicit calendar, so none of it depends on the machine's time zone.
final class CompanionBehaviorTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func calendar(_ zone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? newYork
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 19, zone: TimeZone? = nil) -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func prefs(_ edit: (inout CompanionPreferences) -> Void = { _ in }) -> CompanionPreferences {
        var p = CompanionPreferences()
        p.isEnabled = true
        p.hasCompletedOnboarding = true
        edit(&p)
        return p
    }

    private func signals(_ now: Date, _ edit: (inout CompanionSignals) -> Void = { _ in }) -> CompanionSignals {
        var s = CompanionSignals.neutral(now: now)
        s.screenTimeAuthorized = true
        s.hasProtectedApps = true
        s.todayScreenMinutes = 20
        edit(&s)
        return s
    }

    private var engine: CompanionBehaviorEngine { CompanionBehaviorEngine(calendar: calendar()) }

    // MARK: - Defaults

    func testMeerkatIsTheDefaultAndOnlyOfferedCompanion() {
        let defaults = CompanionPreferences()
        XCTAssertEqual(defaults.companionType, .meerkat)
        XCTAssertEqual(defaults.name, "Milo")
        XCTAssertEqual(CompanionType.available, [.meerkat])
        XCTAssertTrue(defaults.isEnabled, "Companion is on by default")
        XCTAssertFalse(defaults.isActive, "but stays inactive until the privacy introduction is finished")
        XCTAssertTrue(defaults.isAwaitingIntroduction)
    }

    func testActiveNeedsBothTheSwitchAndFinishedOnboarding() {
        var p = CompanionPreferences()
        p.isEnabled = true
        XCTAssertFalse(p.isActive)
        p.hasCompletedOnboarding = true
        XCTAssertTrue(p.isActive)
    }

    // MARK: - Classification

    func testOrdinaryUseIsIdleAndSilent() {
        let result = engine.evaluate(signals: signals(date(14)), preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
        XCTAssertEqual(result.state, .idle)
        XCTAssertNil(result.topic)
        XCTAssertEqual(result.severity, .calm)
    }

    func testQuietHoursSleepAndOutrankEverything() {
        let now = date(23, 45)
        let busy = signals(now) {
            $0.pauseInProgress = true
            $0.focusActive = true
            $0.interventionsLastHour = 5
            $0.dailyTargetMinutes = 10
        }
        let result = engine.evaluate(signals: busy, preferences: prefs())
        XCTAssertEqual(result.behavior, .quietHours)
        XCTAssertEqual(result.state, .sleeping)
        XCTAssertNil(result.topic)
    }

    func testQuietHoursCanBeSwitchedOff() {
        let result = engine.evaluate(signals: signals(date(23, 45)), preferences: prefs { $0.quietHours.isEnabled = false })
        XCTAssertNotEqual(result.state, .sleeping)
    }

    func testFocusSessionIsFocusedAndNeverSpeaks() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.focusActive = true; $0.dailyTargetMinutes = 5 }, preferences: prefs())
        XCTAssertEqual(result.behavior, .focusSession)
        XCTAssertEqual(result.state, .focused)
        XCTAssertNil(result.topic)
        XCTAssertTrue(result.state.isSilent)
    }

    func testApproachingAndExceedingTheDailyTarget() {
        let near = engine.evaluate(signals: signals(date(14)) { $0.todayScreenMinutes = 50; $0.dailyTargetMinutes = 60 }, preferences: prefs())
        XCTAssertEqual(near.behavior, .approachingLimit)
        XCTAssertEqual(near.state, .curious)
        XCTAssertEqual(near.topic, .nearTarget)

        let over = engine.evaluate(signals: signals(date(14)) { $0.todayScreenMinutes = 60; $0.dailyTargetMinutes = 60 }, preferences: prefs())
        XCTAssertEqual(over.behavior, .thresholdExceeded)
        XCTAssertEqual(over.state, .watching)
        XCTAssertEqual(over.topic, .overTarget)
        XCTAssertEqual(over.recommendation, .stepAway)
    }

    func testBelowTheApproachFractionNothingStandsOut() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.todayScreenMinutes = 40; $0.dailyTargetMinutes = 60 }, preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
    }

    func testNoTargetMeansNoLimitClassification() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.todayScreenMinutes = 900 }, preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
    }

    func testCooldownKeepsTheCompanionSilentAndRestingInsteadOfNagging() {
        let now = date(14)
        let cooling = signals(now) {
            $0.todayScreenMinutes = 100
            $0.dailyTargetMinutes = 60
            $0.cooldownUntil = now.addingTimeInterval(600)
        }
        let result = engine.evaluate(signals: cooling, preferences: prefs())
        XCTAssertEqual(result.behavior, .thresholdExceeded)
        XCTAssertEqual(result.state, .resting)
        XCTAssertNil(result.topic)

        var expired = cooling
        expired.cooldownUntil = now.addingTimeInterval(-1)
        XCTAssertEqual(engine.evaluate(signals: expired, preferences: prefs()).topic, .overTarget)
    }

    func testRepeatedPausesInAnHourSuggestAFocusSession() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.interventionsLastHour = 3 }, preferences: prefs())
        XCTAssertEqual(result.behavior, .repeatedIntervention)
        XCTAssertEqual(result.state, .concerned)
        XCTAssertEqual(result.topic, .repeatedPauses)
        XCTAssertEqual(result.recommendation, .startFocus)

        let one = engine.evaluate(signals: signals(date(14)) { $0.interventionsLastHour = 1 }, preferences: prefs())
        XCTAssertEqual(one.behavior, .normalUse)

        let two = engine.evaluate(signals: signals(date(14)) { $0.interventionsLastHour = 2 }, preferences: prefs())
        XCTAssertEqual(two.behavior, .repeatedIntervention)
    }

    func testContinuingAfterAPauseIsNoticedOnlyWhenUsageActuallyGrew() {
        let now = date(14)
        let day = CompanionDay.key(now, calendar: calendar())
        func continuation(usage: Int, atPause: Int, dayKey: String?, ago: TimeInterval = 600) -> CompanionBehaviorResult {
            engine.evaluate(signals: signals(now) {
                $0.todayScreenMinutes = usage
                $0.lastOutcome = .continued
                $0.lastOutcomeDate = now.addingTimeInterval(-ago)
                $0.minutesAtLastIntervention = atPause
                $0.minutesAtLastInterventionDayKey = dayKey
            }, preferences: prefs())
        }
        XCTAssertEqual(continuation(usage: 45, atPause: 30, dayKey: day).behavior, .postInterventionContinuation)
        XCTAssertEqual(continuation(usage: 45, atPause: 30, dayKey: day).topic, .stillHere)
        XCTAssertEqual(continuation(usage: 35, atPause: 30, dayKey: day).behavior, .normalUse, "only 5 minutes more")
        XCTAssertEqual(continuation(usage: 45, atPause: 30, dayKey: day, ago: 3600).behavior, .normalUse, "outside the window")
        // Midnight rollover: a baseline from yesterday says nothing about today.
        XCTAssertEqual(continuation(usage: 45, atPause: 30, dayKey: "2026-10-18").behavior, .normalUse)
    }

    func testSteppingAwayIsCelebratedThenFadesToHappyThenNormal() {
        let now = date(14)
        func afterExit(secondsAgo: TimeInterval) -> CompanionBehaviorResult {
            engine.evaluate(signals: signals(now) {
                $0.lastOutcome = .exited
                $0.lastOutcomeDate = now.addingTimeInterval(-secondsAgo)
            }, preferences: prefs())
        }
        let fresh = afterExit(secondsAgo: 20)
        XCTAssertEqual(fresh.behavior, .intentionalBreak)
        XCTAssertEqual(fresh.state, .celebrating)
        XCTAssertEqual(fresh.topic, .breakTaken)
        XCTAssertEqual(afterExit(secondsAgo: 300).state, .happy)
        XCTAssertNil(afterExit(secondsAgo: 300).topic)
        XCTAssertEqual(afterExit(secondsAgo: 25 * 60).behavior, .normalUse)
    }

    func testAFutureOutcomeDateFromAClockChangeIsIgnored() {
        let now = date(14)
        let result = engine.evaluate(signals: signals(now) {
            $0.lastOutcome = .exited
            $0.lastOutcomeDate = now.addingTimeInterval(3600)
        }, preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
    }

    func testFinishedFocusSessionGetsAShortAfterglow() {
        let now = date(14)
        let result = engine.evaluate(signals: signals(now) { $0.lastFocusCompletedAt = now.addingTimeInterval(-30) }, preferences: prefs())
        XCTAssertEqual(result.state, .celebrating)
        XCTAssertEqual(result.topic, .focusDone)
    }

    func testAnOpenPauseMakesTheCompanionStayWithThePerson() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.pauseInProgress = true }, preferences: prefs())
        XCTAssertEqual(result.state, .intervening)
        XCTAssertEqual(result.animation, .intervention)
        XCTAssertEqual(result.topic, .pauseOpening)
    }

    func testBeingInACooldownDoesNotMuteAPauseThatIsOnScreen() {
        let now = date(14)
        let result = engine.evaluate(signals: signals(now) {
            $0.pauseInProgress = true
            $0.cooldownUntil = now.addingTimeInterval(900)
        }, preferences: prefs())
        XCTAssertEqual(result.state, .intervening)
        XCTAssertNotNil(result.topic)
    }

    func testExtendedUseNeedsEnoughHistory() {
        func evaluate(days: Int) -> CompanionBehavior {
            engine.evaluate(signals: signals(date(14)) {
                $0.todayScreenMinutes = 160
                $0.typicalDailyMinutes = 100
                $0.typicalDaysCount = days
            }, preferences: prefs()).behavior
        }
        XCTAssertEqual(evaluate(days: 3), .extendedUse)
        XCTAssertEqual(evaluate(days: 2), .normalUse, "not enough history to call anything unusual")
    }

    // MARK: - Late night and bedtime

    func testLateNightIsOnlyClaimedWhenThePhoneIsDemonstrablyInUse() {
        let now = date(23, 0) // after the 10:30 PM bedtime, before quiet hours at 11:30 PM
        let idle = engine.evaluate(signals: signals(now), preferences: prefs())
        XCTAssertEqual(idle.behavior, .normalUse, "no evidence of use, so no claim")
        XCTAssertEqual(idle.state, .tired, "bedtime still changes posture")

        let inUse = engine.evaluate(signals: signals(now) { $0.appInForeground = true }, preferences: prefs())
        XCTAssertEqual(inUse.behavior, .lateNightUse)
        XCTAssertEqual(inUse.state, .tired)
        XCTAssertEqual(inUse.topic, .lateNight)
        XCTAssertEqual(inUse.recommendation, .stepAway)
    }

    func testMivosOwnLateNightProtectionCountsAsLateNight() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.mivoLateNightActive = true; $0.mivoSessionActive = true }, preferences: prefs())
        XCTAssertEqual(result.behavior, .lateNightUse)
    }

    func testWindDownBeforeBedtimeOnlyChangesPosture() {
        let result = engine.evaluate(signals: signals(date(22, 0)), preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
        XCTAssertEqual(result.state, .tired)
        XCTAssertNil(result.topic)
    }

    func testBedtimeCanBeSwitchedOff() {
        let result = engine.evaluate(signals: signals(date(23, 0)) { $0.appInForeground = true }, preferences: prefs { $0.bedtime.isEnabled = false })
        XCTAssertEqual(result.behavior, .normalUse)
        XCTAssertEqual(result.state, .idle)
    }

    func testBedtimePhaseBoundaries() {
        let bedtime = CompanionBedtime.default // 10:30 PM, wake 7:00 AM, 60 minute wind-down
        let cal = calendar()
        XCTAssertEqual(bedtime.phase(at: date(21, 29), calendar: cal), .none)
        XCTAssertEqual(bedtime.phase(at: date(21, 30), calendar: cal), .windingDown)
        XCTAssertEqual(bedtime.phase(at: date(22, 29), calendar: cal), .windingDown)
        XCTAssertEqual(bedtime.phase(at: date(22, 30), calendar: cal), .night)
        XCTAssertEqual(bedtime.phase(at: date(3, 0), calendar: cal), .night)
        XCTAssertEqual(bedtime.phase(at: date(6, 59), calendar: cal), .night)
        XCTAssertEqual(bedtime.phase(at: date(7, 0), calendar: cal), .none)
    }

    func testWindDownLengthIsClamped() {
        var bedtime = CompanionBedtime.default
        bedtime.windDownMinutes = 5_000
        XCTAssertEqual(bedtime.phase(at: date(19, 29), calendar: calendar()), .none)
        XCTAssertEqual(bedtime.phase(at: date(19, 30), calendar: calendar()), .windingDown)
        bedtime.windDownMinutes = -10
        XCTAssertEqual(bedtime.phase(at: date(22, 14), calendar: calendar()), .none)
        XCTAssertEqual(bedtime.phase(at: date(22, 15), calendar: calendar()), .windingDown)
    }

    // MARK: - Honesty about missing data

    func testWithoutScreenTimeAccessUsageIsNeverGuessed() {
        let result = engine.evaluate(signals: signals(date(14)) {
            $0.screenTimeAuthorized = false
            $0.todayScreenMinutes = 900
            $0.dailyTargetMinutes = 60
        }, preferences: prefs())
        XCTAssertEqual(result.behavior, .normalUse)
        XCTAssertEqual(result.dataLimits, [.screenTimeNotAuthorized])
    }

    func testNeverRequestedAuthorizationIsReportedTheSameWay() {
        let result = engine.evaluate(signals: .neutral(now: date(14)), preferences: prefs())
        XCTAssertEqual(result.dataLimits, [.screenTimeNotAuthorized])
    }

    func testNoSelectedAppsAndNoReportYetAreEachNamed() {
        let result = engine.evaluate(signals: signals(date(14)) { $0.hasProtectedApps = false; $0.todayScreenMinutes = nil }, preferences: prefs())
        XCTAssertEqual(result.dataLimits, [.noProtectedApps, .noUsageReportYet])
        XCTAssertEqual(result.state, .idle, "still a perfectly good companion")
    }

    // MARK: - Personality and frequency never change behaviour

    func testPersonalityAndFrequencyChangeCopyNotDecisions() {
        let busy = signals(date(14)) { $0.todayScreenMinutes = 80; $0.dailyTargetMinutes = 60; $0.interventionsLastHour = 1 }
        let baseline = engine.evaluate(signals: busy, preferences: prefs())
        for personality in CompanionPersonality.allCases {
            for frequency in CompanionInterventionFrequency.allCases {
                let result = engine.evaluate(signals: busy, preferences: prefs { $0.personality = personality; $0.interventionFrequency = frequency })
                XCTAssertEqual(result, baseline, "\(personality) / \(frequency)")
            }
        }
    }

    // MARK: - Time zones and the clock

    func testQuietHoursFollowTheTimeZoneTheDeviceIsIn() {
        let instant = date(23, 30, zone: newYork)
        let inNewYork = engine.evaluate(signals: signals(instant), preferences: prefs())
        XCTAssertEqual(inNewYork.state, .sleeping)

        let tokyoEngine = CompanionBehaviorEngine(calendar: calendar(tokyo))
        let inTokyo = tokyoEngine.evaluate(signals: signals(instant), preferences: prefs())
        XCTAssertNotEqual(inTokyo.state, .sleeping, "the same instant is 12:30 PM there")
    }

    func testDayKeysRollOverAtLocalMidnight() {
        let cal = calendar()
        XCTAssertEqual(CompanionDay.key(date(23, 59), calendar: cal), "2026-10-19")
        XCTAssertEqual(CompanionDay.key(date(0, 0, day: 20), calendar: cal), "2026-10-20")
        XCTAssertEqual(CompanionDay.key(offset: -1, from: date(0, 5, day: 20), calendar: cal), "2026-10-19")
    }

    func testClockTimesWrapAndFormat() {
        XCTAssertEqual(CompanionClockTime(minutesFromMidnight: -30).minutesFromMidnight, 23 * 60 + 30)
        XCTAssertEqual(CompanionClockTime(minutesFromMidnight: 1440 + 15).minutesFromMidnight, 15)
        XCTAssertEqual(CompanionClockTime(hour: 0).displayText, "12:00 AM")
        XCTAssertEqual(CompanionClockTime(hour: 13, minute: 5).displayText, "1:05 PM")
    }

    func testTimeWindowsIncludeStartExcludeEndAndHandleMidnight() {
        let window = CompanionTimeWindow(isEnabled: true, start: .init(hour: 23, minute: 30), end: .init(hour: 6, minute: 30))
        let cal = calendar()
        XCTAssertTrue(window.contains(date(23, 30), calendar: cal))
        XCTAssertTrue(window.contains(date(0, 0), calendar: cal))
        XCTAssertFalse(window.contains(date(6, 30), calendar: cal))
        XCTAssertFalse(window.contains(date(12, 0), calendar: cal))

        let empty = CompanionTimeWindow(isEnabled: true, start: .init(hour: 9), end: .init(hour: 9))
        XCTAssertFalse(empty.contains(date(9, 0), calendar: cal), "start == end is empty, not all day")

        var off = window
        off.isEnabled = false
        XCTAssertFalse(off.contains(date(1, 0), calendar: cal))
    }

    // MARK: - Speech policy and frequency

    func testFrequencyOrdersGapsCapsAndCooldowns() {
        let order: [CompanionInterventionFrequency] = [.minimal, .balanced, .attentive]
        for (quieter, louder) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(quieter.messageGap, louder.messageGap)
            XCTAssertLessThan(quieter.dailyMessageCap, louder.dailyMessageCap)
            XCTAssertGreaterThan(quieter.postInterventionCooldown, louder.postInterventionCooldown)
        }
    }

    func testSpeechRespectsTheGapAndTheDailyCap() {
        let cal = calendar()
        let now = date(14)
        var runtime = CompanionRuntime()
        XCTAssertTrue(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: now, calendar: cal))

        CompanionSpeechPolicy.recordSpoken(runtime: &runtime, now: now, calendar: cal)
        XCTAssertFalse(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: now.addingTimeInterval(7 * 60), calendar: cal))
        XCTAssertTrue(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: now.addingTimeInterval(9 * 60), calendar: cal))
        XCTAssertFalse(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .minimal, now: now.addingTimeInterval(19 * 60), calendar: cal))

        runtime.messagesToday = CompanionInterventionFrequency.balanced.dailyMessageCap
        runtime.messageCountDayKey = CompanionDay.key(now, calendar: cal)
        XCTAssertFalse(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: now.addingTimeInterval(4 * 3600), calendar: cal))
        XCTAssertTrue(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: date(9, day: 20), calendar: cal), "a new day resets the cap")
    }

    func testAPauseScreenIgnoresTheGapButNotTheDailyCap() {
        let cal = calendar()
        let now = date(14)
        var runtime = CompanionRuntime()
        CompanionSpeechPolicy.recordSpoken(runtime: &runtime, now: now, calendar: cal)

        func canSpeak(after seconds: TimeInterval, duringPause: Bool) -> Bool {
            CompanionSpeechPolicy.canSpeak(
                runtime: runtime, frequency: .balanced, now: now.addingTimeInterval(seconds),
                calendar: cal, duringPause: duringPause
            )
        }
        XCTAssertFalse(canSpeak(after: 120, duringPause: false))
        XCTAssertFalse(canSpeak(after: 10, duringPause: true), "one screen is never claimed twice")
        XCTAssertTrue(canSpeak(after: 120, duringPause: true))

        runtime.messagesToday = CompanionInterventionFrequency.balanced.dailyMessageCap
        runtime.messageCountDayKey = CompanionDay.key(now, calendar: cal)
        XCTAssertFalse(canSpeak(after: 3600, duringPause: true))
    }

    func testAClockMovedBackwardsIsTreatedAsRecentNotFree() {
        let cal = calendar()
        var runtime = CompanionRuntime()
        runtime.lastMessageDate = date(15)
        XCTAssertFalse(CompanionSpeechPolicy.canSpeak(runtime: runtime, frequency: .balanced, now: date(14), calendar: cal))
    }

    // MARK: - Copy

    func testEveryLineIsObservationalNeverAVerdict() {
        let banned = [
            "fail", "self-control", "self control", "addict", "wast", "disappoint", "shame", "guilt",
            "lazy", "pathetic", "weak", "should have", "stop scrolling", "your fault", "bad",
        ]
        let context = CompanionMessageContext(companionName: "Milo", minutes: 52, targetMinutes: 60)
        for topic in CompanionMessageTopic.allCases {
            for personality in CompanionPersonality.allCases {
                for line in CompanionMessageProvider.variants(for: topic, personality: personality, context: context) {
                    XCTAssertFalse(line.isEmpty)
                    for word in banned {
                        XCTAssertFalse(line.lowercased().contains(word), "“\(line)” (\(topic), \(personality)) contains “\(word)”")
                    }
                }
            }
        }
        for pauses in 0...4 {
            for focus in 0...2 {
                let summary = CompanionMessageProvider.todaySummary(pauses: pauses, focusSessions: focus).lowercased()
                for word in banned { XCTAssertFalse(summary.contains(word)) }
            }
        }
    }

    func testPersonalitySelectsCopyFromTheSameTopic() {
        let gentle = CompanionMessageProvider.message(for: .stillHere, personality: .gentle, variant: 0)
        let playful = CompanionMessageProvider.message(for: .stillHere, personality: .playful, variant: 0)
        let direct = CompanionMessageProvider.message(for: .overTarget, personality: .direct, context: .init(targetMinutes: 30))
        XCTAssertEqual(gentle, "You've been here a little while.")
        XCTAssertEqual(playful, "This scroll turned into a journey.")
        XCTAssertEqual(direct, "30 minutes reached.")
        XCTAssertNotEqual(gentle, playful)
    }

    func testQuietPersonalityUsesAnimationNotWords() {
        XCTAssertFalse(CompanionPersonality.quiet.usesText)
        let quietTopics: [CompanionMessageTopic] = [.pauseOpening, .stillHere, .nearTarget, .breakTaken, .focusDone, .repeatedPauses]
        for topic in quietTopics {
            XCTAssertNil(CompanionMessageProvider.message(for: topic, personality: .quiet), "\(topic)")
        }
    }

    func testVariantSelectionIsDeterministicAndWrapsSafely() {
        let options = CompanionMessageProvider.variants(for: .pauseOpening, personality: .gentle)
        XCTAssertGreaterThan(options.count, 1)
        XCTAssertEqual(CompanionMessageProvider.message(for: .pauseOpening, personality: .gentle, variant: 1), options[1])
        XCTAssertEqual(CompanionMessageProvider.message(for: .pauseOpening, personality: .gentle, variant: options.count), options[0])
        XCTAssertEqual(CompanionMessageProvider.message(for: .pauseOpening, personality: .gentle, variant: -1), options[options.count - 1])
    }

    func testDirectCopyNeverInventsNumbersItDoesNotHave() {
        let line = CompanionMessageProvider.message(for: .nearTarget, personality: .direct, context: .init(minutes: nil, targetMinutes: nil))
        XCTAssertEqual(line, "Close to today's target.")
        let withNumbers = CompanionMessageProvider.message(for: .nearTarget, personality: .direct, context: .init(minutes: 52, targetMinutes: 60))
        XCTAssertEqual(withNumbers, "52 of 60 minutes.")
    }

    func testTodaySummaryRewardsIntentionAndStaysNeutralOnAQuietDay() {
        XCTAssertEqual(CompanionMessageProvider.todaySummary(pauses: 0, focusSessions: 0), "A calm day so far.")
        XCTAssertEqual(CompanionMessageProvider.todaySummary(pauses: 3, focusSessions: 0), "Nice — you've taken 3 intentional pauses.")
        XCTAssertEqual(CompanionMessageProvider.todaySummary(pauses: 1, focusSessions: 0), "Nice — you've taken 1 intentional pause.")
    }

    // MARK: - Preferences and persistence shape

    func testPreferencesRoundTripThroughJSON() throws {
        var p = prefs {
            $0.name = "Pip"
            $0.personality = .playful
            $0.interventionFrequency = .minimal
            $0.quietHours = CompanionTimeWindow(isEnabled: false, start: .init(hour: 22), end: .init(hour: 5))
            $0.bedtime = CompanionBedtime(isEnabled: true, bedtime: .init(hour: 23), wakeTime: .init(hour: 8), windDownMinutes: 45)
            $0.animationsEnabled = false
            $0.notificationsEnabled = true
        }
        p.companionType = .meerkat
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testUnreadableOrNewerValuesFallBackInsteadOfResettingEverything() throws {
        let json = """
        {"companionType":"fox","personality":"sassy","interventionFrequency":"constant",
         "isEnabled":true,"hasCompletedOnboarding":true,"name":"   ","animationsEnabled":false,
         "quietHours":"garbage"}
        """
        let p = try JSONDecoder().decode(CompanionPreferences.self, from: Data(json.utf8))
        XCTAssertEqual(p.companionType, .meerkat)
        XCTAssertEqual(p.personality, .gentle)
        XCTAssertEqual(p.interventionFrequency, .balanced)
        XCTAssertEqual(p.name, "Milo")
        XCTAssertEqual(p.quietHours, .defaultQuietHours)
        XCTAssertTrue(p.isEnabled, "what could be read is kept")
        XCTAssertFalse(p.animationsEnabled)
    }

    func testAnEmptyDocumentDecodesToDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(CompanionPreferences.self, from: Data("{}".utf8)), CompanionPreferences())
        XCTAssertEqual(try JSONDecoder().decode(CompanionRuntime.self, from: Data("{}".utf8)), CompanionRuntime())
        XCTAssertEqual(try JSONDecoder().decode(CompanionProgress.self, from: Data("{}".utf8)), CompanionProgress())
    }

    func testNamesAreTrimmedCollapsedCappedAndNeverEmpty() {
        XCTAssertEqual(CompanionPreferences.sanitizedName("  Mo   mo ", for: .meerkat), "Mo mo")
        XCTAssertEqual(CompanionPreferences.sanitizedName("   ", for: .meerkat), "Milo")
        XCTAssertEqual(CompanionPreferences.sanitizedName("", for: .meerkat), "Milo")
        XCTAssertEqual(CompanionPreferences.sanitizedName(String(repeating: "a", count: 40), for: .meerkat).count, CompanionPreferences.maxNameLength)
        XCTAssertEqual(CompanionPreferences.sanitizedName("Zoë 🦦", for: .meerkat), "Zoë 🦦")
    }

    func testResetKeepsOnOffAndOnboardingSoTheFlowDoesNotReplay() {
        let changed = prefs { $0.name = "Pip"; $0.personality = .direct; $0.animationsEnabled = false; $0.notificationsEnabled = true }
        let reset = changed.resetToDefaults()
        XCTAssertTrue(reset.isEnabled)
        XCTAssertTrue(reset.hasCompletedOnboarding)
        XCTAssertEqual(reset.name, "Milo")
        XCTAssertEqual(reset.personality, .gentle)
        XCTAssertTrue(reset.animationsEnabled)
        XCTAssertFalse(reset.notificationsEnabled)
    }

    func testStorageBackedPersistenceRoundTripsPerAccount() {
        let alice = StorageCompanionPersistence(email: "alice-\(UUID().uuidString)@mivo.test")
        let bob = StorageCompanionPersistence(email: "bob-\(UUID().uuidString)@mivo.test")
        defer {
            StorageService.removeUserScopedMivoData(email: alice.email)
            StorageService.removeUserScopedMivoData(email: bob.email)
        }
        XCTAssertNil(alice.loadPreferences())
        alice.savePreferences(prefs { $0.name = "Alice's" })
        var progress = CompanionProgress()
        progress.recordPause(exited: true, dayKey: "2026-10-19", today: date(14), calendar: calendar())
        alice.saveProgress(progress)

        XCTAssertEqual(alice.loadPreferences()?.name, "Alice's")
        XCTAssertEqual(alice.loadProgress()?.totalPauses, 1)
        XCTAssertNil(bob.loadPreferences(), "one account never sees another's companion")
    }

    // MARK: - Progression

    func testMilestonesAreEarnedByIntentionalActsAndNeverRevoked() {
        let cal = calendar()
        var progress = CompanionProgress()
        XCTAssertEqual(progress.recordPause(exited: false, dayKey: "2026-10-19", today: date(14), calendar: cal), [.firstPause])
        progress.recordPause(exited: true, dayKey: "2026-10-19", today: date(14), calendar: cal)
        XCTAssertEqual(progress.recordPause(exited: true, dayKey: "2026-10-19", today: date(14), calendar: cal), [.threePauses])
        XCTAssertTrue(progress.isUnlocked(.stretching), "the ambient stretch is earned at three pauses")
        XCTAssertEqual(progress.recordFocusSession(dayKey: "2026-10-19", today: date(14), calendar: cal), [.firstFocus])
        XCTAssertEqual(progress.totalExits, 2)

        // Nothing is ever taken back, however long the gap.
        XCTAssertEqual(progress.currentStreak(today: date(14, day: 30), calendar: cal), 0)
        XCTAssertTrue(progress.isUnlocked(.threePauses))
    }

    func testStreakSurvivesAnUnfinishedTodayAndRestartsQuietlyAfterAGap() {
        let cal = calendar()
        var progress = CompanionProgress()
        for day in [17, 18] {
            progress.recordPause(exited: false, dayKey: "2026-10-\(day)", today: date(14, day: day), calendar: cal)
        }
        XCTAssertEqual(progress.currentStreak(today: date(9, day: 19), calendar: cal), 2, "today hasn't had a pause yet — not a lost streak")
        progress.recordPause(exited: false, dayKey: "2026-10-19", today: date(14), calendar: cal)
        XCTAssertEqual(progress.currentStreak(today: date(14), calendar: cal), 3)
        XCTAssertTrue(progress.isUnlocked(.threeDays))

        XCTAssertEqual(progress.currentStreak(today: date(14, day: 23), calendar: cal), 0)
        XCTAssertEqual(progress.bestStreak, 3, "the best run is remembered")
    }

    func testOnlyAggregateDailyCountsAreKeptAndOnlyRecentOnes() {
        let cal = calendar()
        var progress = CompanionProgress()
        let first = date(12, day: 1)
        for offset in 0..<(CompanionProgress.retainedDays + 10) {
            let day = cal.date(byAdding: .day, value: offset, to: first)!
            progress.recordPause(exited: false, dayKey: CompanionDay.key(day, calendar: cal), today: day, calendar: cal)
        }
        XCTAssertEqual(progress.days.count, CompanionProgress.retainedDays)
        XCTAssertEqual(progress.totalPauses, CompanionProgress.retainedDays + 10, "lifetime totals aren't truncated")
        let mirror = Mirror(reflecting: progress.days[0]).children.compactMap(\.label)
        XCTAssertEqual(Set(mirror), ["dayKey", "pauses", "exits", "focusSessions"], "no app names, durations or timestamps")
    }

    // MARK: - Shared (widget / extension) state

    func testSnapshotFromAnotherDayReadsAsZeroForToday() {
        let snapshot = CompanionSharedSnapshot(
            isActive: true, companionType: "meerkat", name: "Milo", state: "idle", message: nil,
            pausesToday: 4, focusSessionsToday: 1, dayKey: "2026-10-18", focusActive: false,
            focusEndsAt: nil, updatedAt: date(10, day: 18)
        )
        XCTAssertEqual(snapshot.pausesCount(on: "2026-10-18"), 4)
        XCTAssertEqual(snapshot.pausesCount(on: "2026-10-19"), 0)
        XCTAssertEqual(snapshot.focusCount(on: "2026-10-19"), 0)
    }

    func testSnapshotFreshnessRejectsStaleAndFutureDates() {
        let now = date(14)
        func snapshot(updated: Date) -> CompanionSharedSnapshot {
            CompanionSharedSnapshot(
                isActive: true, companionType: "meerkat", name: "Milo", state: "idle", message: nil,
                pausesToday: 0, focusSessionsToday: 0, dayKey: "2026-10-19", focusActive: false,
                focusEndsAt: nil, updatedAt: updated
            )
        }
        XCTAssertTrue(snapshot(updated: now.addingTimeInterval(-60)).isFresh(at: now))
        XCTAssertFalse(snapshot(updated: now.addingTimeInterval(-7 * 3600)).isFresh(at: now))
        XCTAssertFalse(snapshot(updated: now.addingTimeInterval(3600)).isFresh(at: now), "a clock set backwards")
    }

    func testSharedStoreRoundTripsAndDegradesWhenTheAppGroupIsUnreachable() {
        let suite = "mivo.companion.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }
        let store = CompanionSharedStore(defaults: defaults)
        XCTAssertNil(store.read())

        let snapshot = CompanionSharedSnapshot(
            isActive: true, companionType: "meerkat", name: "Milo", state: "focused", message: nil,
            pausesToday: 2, focusSessionsToday: 0, dayKey: "2026-10-19", focusActive: true,
            focusEndsAt: date(15), updatedAt: date(14)
        )
        XCTAssertTrue(store.write(snapshot))
        XCTAssertEqual(store.read(), snapshot)
        store.clear()
        XCTAssertNil(store.read())

        // An extension that can't open the group: no crash, no data, no pretence.
        let unreachable = CompanionSharedStore(defaults: nil)
        XCTAssertFalse(unreachable.write(snapshot))
        XCTAssertNil(unreachable.read())
    }

    func testCorruptSharedDataReadsAsNothing() {
        let suite = "mivo.companion.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: CompanionSharedKeys.snapshot)
        XCTAssertNil(CompanionSharedStore(defaults: defaults).read())
    }

    // MARK: - Signals built from Mivo's existing data

    @MainActor
    func testTypicalUsageIsTheMeanOfRecentDaysExcludingToday() {
        func observation(_ day: String, _ minutes: Int) -> DailyScreenTimeObservation {
            DailyScreenTimeObservation(date: day, minutes: minutes, recordedAt: "")
        }
        let (none, noneDays) = CompanionDeviceActivityAdapter.typicalDailyMinutes(from: [], excluding: "2026-10-19")
        XCTAssertNil(none)
        XCTAssertEqual(noneDays, 0)

        let (mean, days) = CompanionDeviceActivityAdapter.typicalDailyMinutes(from: [
            observation("2026-10-19", 500), // today is excluded
            observation("2026-10-18", 100),
            observation("2026-10-17", 200),
            observation("2026-10-16", 0),   // a day with no data isn't a 0-minute day
        ], excluding: "2026-10-19")
        XCTAssertEqual(mean, 150)
        XCTAssertEqual(days, 2)
    }

    @MainActor
    func testOnlyPausesFromTheLastHourCount() {
        let now = date(14)
        let formatter = ISO8601DateFormatter()
        func attempt(_ secondsAgo: TimeInterval) -> InterventionAttemptRecord {
            InterventionAttemptRecord(id: UUID().uuidString, occurredAt: formatter.string(from: now.addingTimeInterval(-secondsAgo)), continued: nil)
        }
        let attempts = [attempt(60), attempt(1800), attempt(3599), attempt(3700), attempt(-600)]
        XCTAssertEqual(CompanionDeviceActivityAdapter.interventionsInLastHour(attempts, now: now), 3)
        XCTAssertEqual(CompanionDeviceActivityAdapter.interventionsInLastHour([], now: now), 0)
    }

    // MARK: - Animation

    func testEveryStateHasADistinctRestingPoseAndOnlySleepingShowsZs() {
        for state in CompanionState.allCases {
            let pose = MeerkatMotion.staticPose(for: state)
            XCTAssertEqual(pose, MeerkatMotion.staticPose(for: state), "Reduce Motion pose must be stable")
            XCTAssertEqual(pose.sleepZ > 0, state == .sleeping, "\(state)")
        }
        XCTAssertEqual(MeerkatMotion.staticPose(for: .sleeping).eyeOpen, 0)
        XCTAssertGreaterThan(MeerkatMotion.staticPose(for: .celebrating).armRaise, MeerkatMotion.staticPose(for: .idle).armRaise)
        XCTAssertLessThan(MeerkatMotion.staticPose(for: .concerned).browLift, 0)
    }

    func testEveryClipStaysInRangeAtEveryMomentInEveryState() {
        // The pairings the UI really produces: a state's own clip, and a
        // previewed clip in the posture it is previewed in.
        let pairs = CompanionState.allCases.map { ($0, $0.defaultAnimation) }
            + CompanionAnimation.allCases.map { ($0.previewState, $0) }
        for (state, clip) in pairs {
            for step in 0..<400 {
                let t = Double(step) * 0.173
                let pose = MeerkatMotion.pose(state: state, clip: clip, elapsed: t)
                let values = [
                    pose.eyeOpen, pose.eyeLookX, pose.eyeLookY, pose.smile, pose.browLift, pose.headTilt,
                    pose.headDrop, pose.bodyLean, pose.bodyStretch, pose.armRaise, pose.armOut, pose.earBack,
                    pose.tailSwing, pose.lift, pose.sleepZ,
                ]
                XCTAssertTrue(values.allSatisfy(\.isFinite), "\(state)/\(clip)@\(t)")
                XCTAssertTrue((-0.0001...1.0001).contains(pose.eyeOpen), "\(state)/\(clip)@\(t) eyeOpen \(pose.eyeOpen)")
            }
        }
    }

    func testPosesBlendSmoothlyBetweenStates() {
        let a = MeerkatMotion.staticPose(for: .idle)
        let b = MeerkatMotion.staticPose(for: .sleeping)
        let end = a.blended(to: b, fraction: 1)
        XCTAssertEqual(a.blended(to: b, fraction: 0), a)
        XCTAssertEqual(end.eyeOpen, b.eyeOpen, accuracy: 1e-9)
        XCTAssertEqual(end.headDrop, b.headDrop, accuracy: 1e-9)
        XCTAssertEqual(end.sleepZ, b.sleepZ, accuracy: 1e-9)
        XCTAssertEqual(a.blended(to: b, fraction: 0.5).eyeOpen, 0.5, accuracy: 1e-9)
    }

    func testBlinkClosesTheEyesAndOneShotsSettleBackToRest() {
        let open = MeerkatMotion.pose(state: .idle, clip: .blink, elapsed: 0.5)
        let closing = MeerkatMotion.pose(state: .idle, clip: .blink, elapsed: 0.09)
        XCTAssertEqual(open.eyeOpen, 1, accuracy: 1e-9)
        XCTAssertLessThan(closing.eyeOpen, 0.2)

        let settled = MeerkatMotion.pose(state: .idle, clip: .stretching, elapsed: 10)
        XCTAssertEqual(settled, MeerkatMotion.staticPose(for: .idle))
        let celebrated = MeerkatMotion.pose(state: .celebrating, clip: .celebration, elapsed: 0.3)
        XCTAssertGreaterThan(celebrated.lift, 0)
    }

    func testTheAmbientStretchOnlyPlaysOnceItIsUnlocked() {
        let locked = MeerkatMotion.pose(state: .idle, clip: .idleBreathing, elapsed: 29, stretchUnlocked: false)
        let unlocked = MeerkatMotion.pose(state: .idle, clip: .idleBreathing, elapsed: 29, stretchUnlocked: true)
        XCTAssertEqual(locked.armRaise, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(unlocked.armRaise, 0.5)
    }
}
