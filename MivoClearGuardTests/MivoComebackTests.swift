import XCTest
@testable import Mivo

/// The rules behind the fresh-start flow: when someone counts as lapsed, what
/// baseline a returning user is offered, and how the restart ramp falls. These
/// are pure functions of day keys and observations, so every threshold is
/// pinned here rather than trusted.
final class MivoComebackTests: XCTestCase {
    private var today: String { MivoDay.todayKey }

    private func observation(_ offset: Int, _ minutes: Int) -> DailyScreenTimeObservation {
        DailyScreenTimeObservation(date: MivoDay.key(offsetFromToday: offset), minutes: minutes, recordedAt: "")
    }

    private func anchor(startOffset: Int, startMinutes: Int, step: Int) -> ComebackAnchor {
        ComebackAnchor(
            startDay: MivoDay.key(offsetFromToday: startOffset),
            baselineMinutes: startMinutes,
            baselineSource: .selfReported,
            startMinutes: startMinutes,
            dailyStepMinutes: step,
            pace: .steady,
            reason: nil,
            lapseDays: 0,
            why: nil,
            nudgesEnabled: true,
            createdAt: ""
        )
    }

    // MARK: Lapse detection

    func testLapseNeedsThreeFullDays() {
        XCTAssertFalse(MivoComeback.isLapsed(lastActiveDay: MivoDay.key(offsetFromToday: -2), today: today))
        XCTAssertTrue(MivoComeback.isLapsed(lastActiveDay: MivoDay.key(offsetFromToday: -3), today: today))
        XCTAssertEqual(MivoComeback.lapseDays(lastActiveDay: MivoDay.key(offsetFromToday: -5), today: today), 5)
    }

    func testMissingOrUnparseableLastActiveDayIsNeverALapse() {
        XCTAssertFalse(MivoComeback.isLapsed(lastActiveDay: nil, today: today))
        XCTAssertFalse(MivoComeback.isLapsed(lastActiveDay: "garbage", today: today))
        XCTAssertEqual(MivoComeback.latestDay(["2026-01-02", "bad", "2026-03-01"]), "2026-03-01")
    }

    // MARK: Baseline

    func testBaselineAveragesRecentMeasuredDaysAndSkipsTodayAndZeros() {
        let days = [observation(0, 500), observation(-1, 60), observation(-2, 80), observation(-3, 0), observation(-4, 100)]
        let baseline = MivoComeback.baseline(observations: days, setupEstimate: 45, today: today)
        XCTAssertEqual(baseline?.minutes, 80)
        XCTAssertEqual(baseline?.source, .recentDays(3))
    }

    func testOneRecentDayFallsBackToOlderMeasuredDaysAndSaysSo() {
        let days = [observation(-1, 70), observation(-30, 90), observation(-31, 110)]
        let baseline = MivoComeback.baseline(observations: days, setupEstimate: 45, today: today)
        XCTAssertEqual(baseline?.minutes, 90)
        guard case .lastMeasuredDays(let count, _)? = baseline?.source else {
            return XCTFail("expected an older-days source, got \(String(describing: baseline?.source))")
        }
        XCTAssertEqual(count, 3)
    }

    func testStaleOnlyDataIsLabelledWithItsLastDay() {
        let days = [observation(-40, 100), observation(-41, 120)]
        let baseline = MivoComeback.baseline(observations: days, setupEstimate: nil, today: today)
        XCTAssertEqual(baseline?.minutes, 110)
        XCTAssertEqual(baseline?.source, .lastMeasuredDays(2, lastDay: MivoDay.key(offsetFromToday: -40)))
    }

    func testNoMeasuredDaysUsesSetupEstimateThenNothing() {
        XCTAssertEqual(MivoComeback.baseline(observations: [], setupEstimate: 75, today: today)?.source, .setupEstimate)
        XCTAssertNil(MivoComeback.baseline(observations: [observation(0, 90)], setupEstimate: nil, today: today),
                     "today alone is in progress and must not become a baseline")
        XCTAssertNil(MivoComeback.baseline(observations: [], setupEstimate: 0, today: today))
    }

    func testLowestDayNeedsThreeMeasuredDays() {
        XCTAssertNil(MivoComeback.lowestDay(observations: [observation(-1, 50), observation(-2, 80)], today: today))
        let three = [observation(-1, 50), observation(-2, 80), observation(-3, 65)]
        XCTAssertEqual(MivoComeback.lowestDay(observations: three, today: today)?.minutes, 50)
    }

    // MARK: Ramp

    func testStartMinutesNeverExceedBaselineOrDropBelowGoal() {
        XCTAssertEqual(MivoComeback.startMinutes(baseline: 100, pace: .easeBack, floor: 30), 100)
        XCTAssertEqual(MivoComeback.startMinutes(baseline: 100, pace: .steady, floor: 30), 90)
        XCTAssertEqual(MivoComeback.startMinutes(baseline: 100, pace: .stretch, floor: 30), 80)
        XCTAssertEqual(MivoComeback.startMinutes(baseline: 35, pace: .stretch, floor: 30), 30)
        XCTAssertEqual(MivoComeback.startMinutes(baseline: 20, pace: .easeBack, floor: 30), 30)
    }

    func testTargetFallsByTheDailyStepAndStopsAtTheGoal() {
        let running = anchor(startOffset: -2, startMinutes: 90, step: 3)
        XCTAssertEqual(MivoComeback.dayIndex(anchor: running, today: today), 3)
        XCTAssertEqual(MivoComeback.target(anchor: running, dayIndex: 1, floor: 30), 90)
        XCTAssertEqual(MivoComeback.target(anchor: running, dayIndex: 3, floor: 30), 84)
        XCTAssertEqual(MivoComeback.target(anchor: running, dayIndex: 100, floor: 30), 30)
    }

    func testFreshStartBlocksAnotherForThirtyDays() {
        XCTAssertFalse(MivoComeback.isCoolingDown(anchor: nil, today: today))
        XCTAssertTrue(MivoComeback.isCoolingDown(anchor: anchor(startOffset: 0, startMinutes: 90, step: 3), today: today))
        XCTAssertTrue(MivoComeback.isCoolingDown(anchor: anchor(startOffset: -29, startMinutes: 90, step: 3), today: today))
        XCTAssertFalse(MivoComeback.isCoolingDown(anchor: anchor(startOffset: -30, startMinutes: 90, step: 3), today: today),
                       "day 30 after the start is the first day it is allowed again")
        XCTAssertFalse(MivoComeback.isCoolingDown(anchor: anchor(startOffset: -200, startMinutes: 90, step: 3), today: today))
    }

    func testCooldownNamesTheFirstAllowedDay() {
        let started = anchor(startOffset: -5, startMinutes: 90, step: 3)
        XCTAssertEqual(MivoComeback.availableAgainDay(anchor: started), MivoDay.key(offsetFromToday: 25))
    }

    func testFutureDatedAnchorDoesNotLockTheFeature() {
        XCTAssertFalse(MivoComeback.isCoolingDown(anchor: anchor(startOffset: 3, startMinutes: 90, step: 3), today: today))
    }

    func testAnchorStartingInTheFutureIsIgnored() {
        XCTAssertNil(MivoComeback.dayIndex(anchor: anchor(startOffset: 2, startMinutes: 90, step: 3), today: today))
    }

    func testDaysToGoalRoundsUp() {
        XCTAssertEqual(MivoComeback.daysToGoal(startMinutes: 90, dailyStep: 3, floor: 30), 20)
        XCTAssertEqual(MivoComeback.daysToGoal(startMinutes: 91, dailyStep: 3, floor: 30), 21)
        XCTAssertEqual(MivoComeback.daysToGoal(startMinutes: 30, dailyStep: 3, floor: 30), 0)
    }

    func testDistributeAlwaysSumsToTheTotalAndKeepsProportions() {
        XCTAssertEqual(MivoComeback.distribute(total: 60, weights: [30, 30]), [30, 30])
        XCTAssertEqual(MivoComeback.distribute(total: 90, weights: [10, 20, 30]).reduce(0, +), 90)
        XCTAssertEqual(MivoComeback.distribute(total: 100, weights: [1, 1, 1]).reduce(0, +), 100)
        let skewed = MivoComeback.distribute(total: 80, weights: [60, 20])
        XCTAssertEqual(skewed, [60, 20])
        XCTAssertTrue(skewed[0] > skewed[1])
    }

    func testDistributeSplitsEvenlyWhenWindowsCarryNoMinutes() {
        XCTAssertEqual(MivoComeback.distribute(total: 10, weights: [0, 0, 0]), [4, 3, 3])
        XCTAssertEqual(MivoComeback.distribute(total: 0, weights: [5, 5]), [0, 0])
        XCTAssertEqual(MivoComeback.distribute(total: 30, weights: []), [])
    }

    func testFitKeepsTimesAndTitlesButResizesMinutes() {
        let windows = [
            ScreenScrollWindow(id: "a", title: "Morning", startHour: 8, endHour: 9, minutes: 60, reason: "r1"),
            ScreenScrollWindow(id: "b", title: "Evening", startHour: 19, endHour: 20, minutes: 20, reason: "r2")
        ]
        let fitted = MivoComeback.fit(windows, toTarget: 40)
        XCTAssertEqual(fitted.map(\.minutes), [30, 10])
        XCTAssertEqual(fitted.map(\.minutes).reduce(0, +), 40)
        XCTAssertEqual(fitted.map(\.startHour), [8, 19])
        XCTAssertEqual(fitted.map(\.endHour), [9, 20])
        XCTAssertEqual(fitted.map(\.title), ["Morning", "Evening"])
        XCTAssertEqual(fitted.map(\.id), ["a", "b"])
    }

    func testFitGivesObservationWindowsAnEvenShare() {
        let windows = [
            ScreenScrollWindow(id: "a", title: "A", startHour: 8, endHour: 9, minutes: 0, reason: ""),
            ScreenScrollWindow(id: "b", title: "B", startHour: 14, endHour: 15, minutes: 0, reason: "")
        ]
        XCTAssertEqual(MivoComeback.fit(windows, toTarget: 50).map(\.minutes), [25, 25])
    }

    func testProjectionsFollowTheAnchorOnlyWhenOneIsActive() {
        let fresh = anchor(startOffset: 0, startMinutes: 85, step: 3)
        XCTAssertEqual(AIService.projectedTargetMinutes(dayIndex: 8, baseline: 200, floor: 30, comeback: fresh), 64)
        XCTAssertEqual(
            AIService.projectedTargetMinutes(dayIndex: 8, baseline: 200, floor: 30, comeback: nil),
            AIService.personalizedTargetMinutes(dayIndex: 8, baseline: 200, floor: 30)
        )
        XCTAssertEqual(AIService.projectedDaysUntilGoal(baseline: 200, goal: 30, comeback: fresh),
                       MivoComeback.goalDayIndex(anchor: fresh, floor: 30))
        // The goal day is the first day the target actually reaches the goal.
        let goalDay = MivoComeback.goalDayIndex(anchor: fresh, floor: 30)
        XCTAssertEqual(MivoComeback.target(anchor: fresh, dayIndex: goalDay, floor: 30), 30)
        XCTAssertGreaterThan(MivoComeback.target(anchor: fresh, dayIndex: goalDay - 1, floor: 30), 30)
    }

    // MARK: Plan integration

    func testPlanUsesTheAnchorInsteadOfTheCalendarRamp() {
        var profile = OnboardingProfile()
        profile.dailyScrollGoalMinutes = 30
        // Observation started long ago, so the calendar ramp would be deep in
        // its decline — the anchor must override that entirely.
        profile.observationStartedAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-90 * 86_400))
        let fresh = anchor(startOffset: 0, startMinutes: 85, step: 3)

        let plan = AIService.makeScreenTimeReductionPlan(
            sessions: [],
            truthChecks: [],
            todayScreenTimeMinutes: nil,
            profile: profile,
            dailyObservations: [],
            comeback: fresh
        )

        XCTAssertFalse(plan.collecting)
        XCTAssertEqual(plan.dayIndex, 1)
        XCTAssertEqual(plan.targetMinutes, 85)
        XCTAssertTrue(plan.id.hasPrefix("comeback-"))
    }

    // MARK: Persistence

    func testAnchorSurvivesEncodingIncludingPayloadSource() throws {
        let original = ComebackAnchor(
            startDay: today,
            baselineMinutes: 80,
            baselineSource: .lastMeasuredDays(3, lastDay: "2026-09-04"),
            startMinutes: 72,
            dailyStepMinutes: 3,
            pace: .steady,
            reason: .lostMotivation,
            lapseDays: 40,
            why: "Sleep better",
            nudgesEnabled: true,
            createdAt: "x"
        )
        let decoded = try JSONDecoder().decode(ComebackAnchor.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}

/// The pure helpers behind the one-tap scroll time picker.
final class ScrollWindowPickerTests: XCTestCase {
    private func window(_ start: Int, _ end: Int, minutes: Int = 15) -> ScreenScrollWindow {
        ScreenScrollWindow(id: "w\(start)", title: "W", startHour: start, endHour: end, minutes: minutes, reason: "r")
    }

    func testStartingAtKeepsLengthAndMinutes() {
        let moved = window(14, 16, minutes: 40).startingAt(9)
        XCTAssertEqual(moved.startHour, 9)
        XCTAssertEqual(moved.endHour, 11)
        XCTAssertEqual(moved.minutes, 40)
    }

    func testStartingAtPullsBackSoTheWindowEndsByMidnight() {
        let moved = window(14, 16).startingAt(23)
        XCTAssertEqual(moved.startHour, 22)
        XCTAssertEqual(moved.endHour, 24)
    }

    func testStartingAtClampsNegativeStart() {
        XCTAssertEqual(window(14, 15).startingAt(-3).startHour, 0)
    }

    func testHoursCoveredExcludesTheEditedWindow() {
        let windows = [window(9, 10), window(14, 16), window(20, 21)]
        XCTAssertEqual(windows.hoursCovered(excluding: 1), [9, 20])
        XCTAssertEqual(windows.hoursCovered(excluding: 0), [14, 15, 20])
    }
}
