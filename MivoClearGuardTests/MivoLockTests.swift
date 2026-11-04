import XCTest
@testable import Mivo

final class MivoLockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func lock(delay: TimeInterval = 24 * 60 * 60) -> MivoLock {
        MivoLock(lockedAt: start, delay: delay, unlockRequestedAt: nil, usesScreenTimePasscode: true)
    }

    // MARK: - Phases

    func testStaysLockedUntilAsked() {
        XCTAssertEqual(lock().phase(at: start.addingTimeInterval(30 * day)), .locked)
    }

    func testAskingStartsTheWait() {
        var subject = lock()
        subject.requestUnlock(at: start)
        XCTAssertEqual(subject.phase(at: start.addingTimeInterval(day - 1)), .waiting(opensAt: start.addingTimeInterval(day)))
    }

    func testOpensAfterTheWaitForThirtyMinutesThenLocksAgain() {
        var subject = lock()
        subject.requestUnlock(at: start)
        let opensAt = start.addingTimeInterval(day)
        XCTAssertEqual(subject.phase(at: opensAt), .open(closesAt: opensAt.addingTimeInterval(MivoLock.openWindow)))
        XCTAssertEqual(subject.phase(at: opensAt.addingTimeInterval(MivoLock.openWindow)), .locked)
    }

    func testAskingAgainWhileWaitingDoesNotRestartOrSkipTheWait() {
        var subject = lock()
        subject.requestUnlock(at: start)
        subject.requestUnlock(at: start.addingTimeInterval(day / 2))
        XCTAssertEqual(subject.unlockRequestedAt, start)
    }

    func testALapsedUnlockCanBeAskedForAgain() {
        var subject = lock()
        subject.requestUnlock(at: start)
        let later = start.addingTimeInterval(day + MivoLock.openWindow + 60)
        subject.requestUnlock(at: later)
        XCTAssertEqual(subject.unlockRequestedAt, later)
    }

    func testStayingLockedCancelsTheWait() {
        var subject = lock()
        subject.requestUnlock(at: start)
        subject.stayLocked()
        XCTAssertEqual(subject.phase(at: start.addingTimeInterval(day)), .locked)
    }

    func testTheWaitOnlyGrows() {
        var subject = lock(delay: 3 * day)
        subject.lengthenDelay(to: day)
        XCTAssertEqual(subject.delay, 3 * day)
        subject.lengthenDelay(to: 7 * day)
        XCTAssertEqual(subject.delay, 7 * day)
    }

    func testLengtheningPushesBackARunningWait() {
        var subject = lock(delay: day)
        subject.requestUnlock(at: start)
        subject.lengthenDelay(to: 3 * day)
        XCTAssertEqual(subject.phase(at: start.addingTimeInterval(2 * day)), .waiting(opensAt: start.addingTimeInterval(3 * day)))
    }

    func testDelayLabels() {
        XCTAssertEqual(MivoLock.delayChoices.map(MivoLock.delayLabel), ["1 hour", "1 day", "3 days", "1 week"])
    }

    // MARK: - Code

    func testRejectsEasyCodes() {
        for code in ["1111", "1212", "1221", "1234", "4321", "0123", "9876", "1998", "2024", "12a4", "123", "12345"] {
            XCTAssertFalse(MivoLockCode.isHardToGuess(code), code)
        }
    }

    func testAcceptsRandomLookingCodes() {
        for code in ["4821", "7390", "0573", "3815"] {
            XCTAssertTrue(MivoLockCode.isHardToGuess(code), code)
        }
    }

    func testMadeCodesAreAlwaysHardToGuess() {
        for _ in 0..<500 {
            XCTAssertTrue(MivoLockCode.isHardToGuess(MivoLockCode.make()))
        }
    }

    // MARK: - Trusted clock

    func testReadsTheServerDateHeader() {
        let date = MivoTrustedClock.date(fromDateHeader: "Tue, 03 Nov 2026 14:05:09 GMT", age: nil)
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-11-03T14:05:09Z"))
    }

    func testAddsACachesAge() {
        let date = MivoTrustedClock.date(fromDateHeader: "Tue, 03 Nov 2026 14:05:09 GMT", age: "120")
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-11-03T14:07:09Z"))
    }

    func testRejectsAMalformedHeader() {
        XCTAssertNil(MivoTrustedClock.date(fromDateHeader: "yesterday", age: nil))
    }
}
