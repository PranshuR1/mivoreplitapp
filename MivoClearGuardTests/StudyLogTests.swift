import XCTest
@testable import Mivo

final class StudyLogTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func entry(_ start: String, minutes: Int) -> StudyEntry {
        let startedAt = date(start)
        return StudyEntry(task: "Notes", startedAt: startedAt, endedAt: startedAt.addingTimeInterval(Double(minutes * 60)),
                          recordedSeconds: minutes * 60, scrollSecondsEarned: 0)
    }

    func testOneTenMinuteBlockCountsForTheDay() {
        let log = StudyLog(entries: [entry("2026-10-28T09:00:00Z", minutes: 10)])
        XCTAssertEqual(log.streak(asOf: date("2026-10-28T20:00:00Z"), calendar: calendar), 1)
    }

    func testNineMinutesDoesNotCount() {
        let log = StudyLog(entries: [entry("2026-10-28T09:00:00Z", minutes: 9)])
        XCTAssertEqual(log.streak(asOf: date("2026-10-28T20:00:00Z"), calendar: calendar), 0)
    }

    func testStreakCountsBackFromYesterdayWhileTodayIsOpen() {
        let log = StudyLog(entries: [
            entry("2026-10-26T09:00:00Z", minutes: 15),
            entry("2026-10-27T09:00:00Z", minutes: 12)
        ])
        XCTAssertEqual(log.streak(asOf: date("2026-10-28T08:00:00Z"), calendar: calendar), 2)
    }

    func testAMissedDayBreaksTheStreak() {
        let log = StudyLog(entries: [
            entry("2026-10-25T09:00:00Z", minutes: 15),
            entry("2026-10-27T09:00:00Z", minutes: 12)
        ])
        XCTAssertEqual(log.streak(asOf: date("2026-10-27T20:00:00Z"), calendar: calendar), 1)
    }

    func testASessionAcrossMidnightCountsForBothDays() {
        let log = StudyLog(entries: [entry("2026-10-27T23:50:00Z", minutes: 30)])
        let totals = log.secondsByDay(calendar: calendar)
        XCTAssertEqual(totals["2026-10-27"], 10 * 60)
        XCTAssertEqual(totals["2026-10-28"], 20 * 60)
        XCTAssertEqual(log.streak(asOf: date("2026-10-28T12:00:00Z"), calendar: calendar), 2)
    }

    func testFirstSessionIsTheEarliestStart() {
        XCTAssertNil(StudyLog().firstSessionAt)
        let log = StudyLog(entries: [entry("2026-10-27T09:00:00Z", minutes: 15), entry("2026-10-25T09:00:00Z", minutes: 15)])
        XCTAssertEqual(log.firstSessionAt, date("2026-10-25T09:00:00Z"))
    }

    func testTrialRunsForSevenDaysFromTheFirstSession() {
        let first = date("2026-10-28T09:00:00Z")
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: nil, now: first, calendar: calendar), .notStarted)
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: first, now: first, calendar: calendar), .running(daysLeft: 7))
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: first, now: date("2026-10-29T08:00:00Z"), calendar: calendar), .running(daysLeft: 7))
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: first, now: date("2026-11-03T20:00:00Z"), calendar: calendar), .running(daysLeft: 1))
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: first, now: date("2026-11-04T08:59:59Z"), calendar: calendar), .running(daysLeft: 1))
        XCTAssertEqual(StudyTrial.phase(firstSessionAt: first, now: date("2026-11-04T09:00:00Z"), calendar: calendar), .ended)
    }

    func testOnlyPlusEarnsScrollOnceTheTrialEnds() {
        XCTAssertTrue(StudyTrial.earnsScroll(.notStarted, hasPlus: false))
        XCTAssertTrue(StudyTrial.earnsScroll(.running(daysLeft: 3), hasPlus: false))
        XCTAssertFalse(StudyTrial.earnsScroll(.ended, hasPlus: false))
        XCTAssertTrue(StudyTrial.earnsScroll(.ended, hasPlus: true))
    }

    func testLockedReceiptLineNamesThePriceOfWaiting() {
        let line = MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: true, capReached: false, streak: 2, lockedScrollMinutes: 12)
        XCTAssertTrue(line.contains("12 minutes"))
        XCTAssertTrue(line.contains("Mivo Plus"))
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: false, capReached: false, streak: 1, lockedScrollMinutes: 12).contains("No video"))
    }

    func testReceiptLineIsFixedByWhatWasEarned() {
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: false, capReached: false, streak: 1).contains("No video"))
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: true, capReached: true, streak: 1).contains("full"))
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 8, recorded: true, capReached: false, streak: 3).contains("3 days"))
    }
}
