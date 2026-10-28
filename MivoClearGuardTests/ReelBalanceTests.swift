import XCTest
@testable import Mivo

final class ReelBalanceTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testFreshBalanceIsTheFullDailyAllowance() {
        let balance = ReelBalance.fresh(on: date("2026-10-23T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(balance.dayKey, "2026-10-23")
        XCTAssertEqual(balance.remainingSeconds, 600)
        XCTAssertEqual(balance.remainingMinutes, 10)
        XCTAssertFalse(balance.isEmpty)
    }

    func testSpendReducesRemainingAndRoundsMinutesUp() {
        var balance = ReelBalance(dayKey: "2026-10-23")
        XCTAssertEqual(balance.spend(seconds: 61), 61)
        XCTAssertEqual(balance.remainingSeconds, 539)
        XCTAssertEqual(balance.remainingMinutes, 9)
    }

    func testSpendNeverGoesBelowZero() {
        var balance = ReelBalance(dayKey: "2026-10-23", spentSeconds: 590)
        XCTAssertEqual(balance.spend(seconds: 30), 10)
        XCTAssertEqual(balance.remainingSeconds, 0)
        XCTAssertTrue(balance.isEmpty)
        XCTAssertEqual(balance.spend(seconds: 5), 0)
    }

    func testNegativeSpendIsIgnored() {
        var balance = ReelBalance(dayKey: "2026-10-23")
        XCTAssertEqual(balance.spend(seconds: -20), 0)
        XCTAssertEqual(balance.remainingSeconds, 600)
    }

    func testRollsOverToAFullBalanceOnANewDay() {
        let spent = ReelBalance(dayKey: "2026-10-23", spentSeconds: 600)
        XCTAssertEqual(spent.rolled(to: date("2026-10-23T23:59:00Z"), calendar: calendar), spent)
        let next = spent.rolled(to: date("2026-10-24T00:01:00Z"), calendar: calendar)
        XCTAssertEqual(next.dayKey, "2026-10-24")
        XCTAssertEqual(next.remainingSeconds, 600)
    }

    func testStudyEarnsOneScrollMinuteForEveryThreeStudyMinutes() {
        var balance = ReelBalance(dayKey: "2026-10-23", spentSeconds: 600)
        XCTAssertEqual(balance.creditStudy(seconds: 30 * 60), 10 * 60)
        XCTAssertEqual(balance.remainingSeconds, 600)
        XCTAssertEqual(balance.creditStudy(seconds: -50), 0)
        XCTAssertEqual(balance.remainingSeconds, 600)
    }

    func testStudyCreditStopsAtTheDailyCap() {
        var balance = ReelBalance(dayKey: "2026-10-23")
        XCTAssertEqual(balance.creditStudy(seconds: 150 * 60), 50 * 60)
        XCTAssertEqual(balance.creditStudy(seconds: 60 * 60), 10 * 60)
        XCTAssertEqual(balance.bonusSeconds, ReelBalance.dailyEarnCapSeconds)
        XCTAssertEqual(balance.creditStudy(seconds: 60 * 60), 0)
        XCTAssertEqual(balance.remainingSeconds, 70 * 60)
    }

    func testStorePersistsAndResetsOnANewDay() {
        let suite = "ReelBalanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var now = date("2026-10-23T09:00:00Z")
        let store = ReelBalanceStore(defaults: defaults, calendar: calendar, now: { now })

        var balance = store.current()
        XCTAssertEqual(balance.remainingSeconds, 600)
        balance.spend(seconds: 200)
        store.save(balance)
        XCTAssertEqual(store.current().remainingSeconds, 400)

        now = date("2026-10-24T09:00:00Z")
        XCTAssertEqual(store.current().remainingSeconds, 600)
    }

    func testEachAccountHasItsOwnBalance() {
        let suite = "ReelBalanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var account: String? = "A@example.com"
        let store = ReelBalanceStore(defaults: defaults, calendar: calendar,
                                     now: { self.date("2026-10-23T09:00:00Z") }, account: { account })
        var first = store.current()
        first.creditStudy(seconds: 30 * 60)
        store.save(first)
        XCTAssertEqual(store.current().remainingSeconds, 1200)

        account = "b@example.com"
        XCTAssertEqual(store.current().remainingSeconds, 600)

        account = "a@EXAMPLE.com"
        XCTAssertEqual(store.current().remainingSeconds, 1200)
        store.erase()
        XCTAssertEqual(store.current().remainingSeconds, 600)
    }

    func testSessionLimitCopy() {
        XCTAssertEqual(WrapperSessionLimit.reels.title, "10 Reels")
        XCTAssertEqual(WrapperSessionLimit.minutes.title, "10 minutes")
    }
}
