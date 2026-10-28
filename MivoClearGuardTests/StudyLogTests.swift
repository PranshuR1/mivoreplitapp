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

    func testReceiptLineIsFixedByWhatWasEarned() {
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: false, capReached: false, streak: 1).contains("No video"))
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 0, recorded: true, capReached: true, streak: 1).contains("full"))
        XCTAssertTrue(MiloStudyVoice.receipt(earnedScrollMinutes: 8, recorded: true, capReached: false, streak: 3).contains("3 days"))
    }
}
