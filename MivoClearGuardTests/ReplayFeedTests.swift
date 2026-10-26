import XCTest
@testable import Mivo

final class ReplayFeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let a = "AAAAAAAAAAA", b = "BBBBBBBBBBB", c = "CCCCCCCCCCC"
    private let x = "XXXXXXXXXXX", y = "YYYYYYYYYYY", z = "ZZZZZZZZZZZ"

    private func session(seen: [String] = []) -> ReplaySession {
        var log = SeenReelLog()
        for code in seen { log.record(code, at: now) }
        return ReplaySession(log: log)
    }

    /// Watches three new reels, then the session's chosen amount is used up.
    private func warmedUp() -> ReplaySession {
        var s = session()
        for code in [a, b, c] { _ = s.observe(code, replayActive: true, now: now) }
        s.startReplaying()
        return s
    }

    // MARK: - ReelCode

    func testReelCodeAcceptsShortcodesAndRejectsEverythingElse() {
        XCTAssertTrue(ReelCode.isValid("DAbc123_-xY"))
        XCTAssertFalse(ReelCode.isValid(""))
        XCTAssertFalse(ReelCode.isValid("short"))
        XCTAssertFalse(ReelCode.isValid("has space1234"))
        XCTAssertFalse(ReelCode.isValid("../../etc/passwd"))
        XCTAssertFalse(ReelCode.isValid(String(repeating: "a", count: 40)))
        XCTAssertFalse(ReelCode.isValid("abcdefghi\u{00E9}"))
    }

    func testReelURLOnlyBuiltForValidCodes() {
        XCTAssertEqual(ReelCode.url(for: a)?.absoluteString, "https://www.instagram.com/reel/AAAAAAAAAAA/")
        XCTAssertNil(ReelCode.url(for: "x/../y"))
    }

    // MARK: - SeenReelLog

    func testLogCountsRepeatSightings() {
        var log = SeenReelLog()
        log.record(a, at: now)
        log.record(a, at: now.addingTimeInterval(60))
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.entries[0].timesSeen, 2)
        XCTAssertEqual(log.entries[0].firstSeen, now)
        XCTAssertEqual(log.entries[0].lastSeen, now.addingTimeInterval(60))
    }

    func testLogIgnoresInvalidCodes() {
        var log = SeenReelLog()
        log.record("nope", at: now)
        XCTAssertEqual(log.count, 0)
    }

    func testLogDropsReelsOlderThanThirtyDays() {
        var log = SeenReelLog()
        log.record(a, at: now.addingTimeInterval(-31 * 86_400))
        log.record(b, at: now)
        XCTAssertFalse(log.contains(a))
        XCTAssertTrue(log.contains(b))
    }

    func testLogKeepsTheNewestWhenOverTheCap() {
        var log = SeenReelLog()
        for i in 0..<(SeenReelLog.maxEntries + 20) {
            log.record(String(format: "code%08d", i), at: now.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(log.count, SeenReelLog.maxEntries)
        XCTAssertFalse(log.contains("code00000000"))
        XCTAssertTrue(log.contains(String(format: "code%08d", SeenReelLog.maxEntries + 19)))
    }

    func testLogSurvivesEncodeDecode() throws {
        var log = SeenReelLog()
        log.record(a, at: now)
        let decoded = try JSONDecoder().decode(SeenReelLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }

    // MARK: - ReplaySession

    func testNewReelsPassThroughUntilTheChosenAmountIsUsed() {
        var s = session()
        for code in [a, b, c, x, y, z] {
            XCTAssertEqual(s.observe(code, replayActive: true, now: now), .none)
        }
        XCTAssertEqual(s.freshReels, 6)
        XCTAssertEqual(s.repeatsServed, 0)
        XCTAssertFalse(s.isReplaying)
    }

    func testRepeatsComeFromTheLatestFewReelsOnly() {
        var s = session()
        let watched = [a, b, c, x, y, z]
        for code in watched { _ = s.observe(code, replayActive: true, now: now) }
        s.startReplaying()
        var served = Set<String>()
        for code in ["WWWWWWWWWWW", "VVVVVVVVVVV", "UUUUUUUUUUU", "TTTTTTTTTTT"] {
            guard case .replace(let target) = s.observe(code, replayActive: true, now: now) else {
                return XCTFail("expected a replacement")
            }
            served.insert(target)
            _ = s.observe(target, replayActive: true, now: now)
        }
        XCTAssertTrue(served.isSubset(of: [x, y, z]))
    }

    func testReplayFallsBackToEarlierSessionsWhenThisOneWatchedNothing() {
        var s = session(seen: [a, b])
        s.startReplaying()
        guard case .replace(let target) = s.observe(x, replayActive: true, now: now) else {
            return XCTFail("expected a replacement")
        }
        XCTAssertTrue([a, b].contains(target))
    }

    func testNothingToReplayMeansTheReelPlays() {
        var s = session()
        s.startReplaying()
        XCTAssertEqual(s.observe(x, replayActive: true, now: now), .none)
        XCTAssertEqual(s.freshReels, 1)
    }

    func testFirstNewReelsPassThroughAndAreCounted() {
        var s = session()
        XCTAssertEqual(s.observe(a, replayActive: true, now: now), .none)
        XCTAssertEqual(s.observe(b, replayActive: true, now: now), .none)
        XCTAssertEqual(s.observe(c, replayActive: true, now: now), .none)
        XCTAssertEqual(s.freshReels, 3)
        XCTAssertEqual(s.repeatsServed, 0)
        XCTAssertTrue(s.log.contains(a) && s.log.contains(b) && s.log.contains(c))
    }

    func testOnceReplayingANewReelIsReplacedByARepeat() {
        var s = warmedUp()
        let outcome = s.observe(x, replayActive: true, now: now)
        guard case .replace(let target) = outcome else { return XCTFail("expected a replacement") }
        XCTAssertTrue([a, b, c].contains(target))
        XCTAssertEqual(s.repeatsServed, 1)
        XCTAssertFalse(s.log.contains(x), "a swapped-out reel was never watched")
        XCTAssertEqual(s.freshReels, 3)
    }

    func testReplayedReelsCycleEvenly() {
        var s = warmedUp()
        var served: [String] = []
        for code in [x, y, z, "WWWWWWWWWWW", "VVVVVVVVVVV", "UUUUUUUUUUU"] {
            guard case .replace(let target) = s.observe(code, replayActive: true, now: now) else {
                return XCTFail("expected a replacement")
            }
            served.append(target)
            XCTAssertEqual(s.observe(target, replayActive: true, now: now), .none)
        }
        XCTAssertEqual(served, [a, b, c, a, b, c])
        XCTAssertEqual(s.repeatsServed, 6)
        XCTAssertEqual(s.repeatsSeen, 6)
    }

    func testTheReelBeingServedIsNeverTheOneJustWatched() {
        var s = warmedUp()
        guard case .replace(let first) = s.observe(x, replayActive: true, now: now) else { return XCTFail() }
        _ = s.observe(first, replayActive: true, now: now)
        guard case .replace(let second) = s.observe(y, replayActive: true, now: now) else { return XCTFail() }
        XCTAssertNotEqual(first, second)
    }

    func testNothingIsReplacedWhenReplayIsInactive() {
        var s = warmedUp()
        XCTAssertEqual(s.observe(x, replayActive: false, now: now), .none)
        XCTAssertEqual(s.freshReels, 4)
        XCTAssertEqual(s.repeatsServed, 0)
        XCTAssertTrue(s.log.contains(x), "reels are still logged while replay is held off")
    }

    func testRepeatsInstagramServesAreCountedNotReplaced() {
        var s = warmedUp()
        XCTAssertEqual(s.observe(a, replayActive: true, now: now), .none)
        XCTAssertEqual(s.repeatsSeen, 1)
        XCTAssertEqual(s.repeatsServed, 0)
    }

    func testTheSameReelReportedTwiceInARowCountsOnce() {
        var s = session()
        _ = s.observe(a, replayActive: true, now: now)
        _ = s.observe(a, replayActive: true, now: now)
        XCTAssertEqual(s.freshReels, 1)
        XCTAssertEqual(s.repeatsSeen, 0)
    }

    func testReelsFromEarlierSessionsCountAsRepeatsAndDoNotUseUpTheAllowance() {
        var s = session(seen: [a, b])
        XCTAssertEqual(s.observe(a, replayActive: true, now: now), .none)
        XCTAssertEqual(s.observe(b, replayActive: true, now: now), .none)
        XCTAssertEqual(s.repeatsSeen, 2)
        XCTAssertEqual(s.freshReels, 0)
        // Still inside the allowance, so a new reel is let through.
        XCTAssertEqual(s.observe(x, replayActive: true, now: now), .none)
        XCTAssertEqual(s.freshReels, 1)
    }

    func testAReplayThatNeverArrivesDoesNotBlockLaterReels() {
        var s = warmedUp()
        guard case .replace(let target) = s.observe(x, replayActive: true, now: now) else { return XCTFail() }
        // The replayed reel never reports; a different reel shows up instead.
        let other = [a, b, c].first { $0 != target }!
        XCTAssertEqual(s.observe(other, replayActive: true, now: now), .none)
        XCTAssertNil(s.pendingReplay)
        XCTAssertEqual(s.repeatsSeen, 1)
    }

    // MARK: - Setting and store

    func testReplayIsHeldOffDuringTheBaselineAndWhenSwitchedOff() {
        XCTAssertTrue(ReplayModeSetting.isActive(enabled: true, observingBaseline: false))
        XCTAssertFalse(ReplayModeSetting.isActive(enabled: true, observingBaseline: true))
        XCTAssertFalse(ReplayModeSetting.isActive(enabled: false, observingBaseline: false))
        XCTAssertFalse(ReplayModeSetting.isActive(enabled: false, observingBaseline: true))
    }

    func testStoreRoundTripsAndClears() {
        let defaults = UserDefaults(suiteName: "ReplayFeedTests.\(UUID().uuidString)")!
        let store = SeenReelStore(defaults: defaults, now: { self.now })
        var log = SeenReelLog()
        log.record(a, at: now)
        store.save(log)
        XCTAssertEqual(store.load(), log)
        store.clear()
        XCTAssertEqual(store.load().count, 0)
    }

    func testStoreDropsStaleReelsOnLoad() {
        let defaults = UserDefaults(suiteName: "ReplayFeedTests.\(UUID().uuidString)")!
        var log = SeenReelLog()
        log.record(a, at: now.addingTimeInterval(-40 * 86_400))
        let fresh = SeenReelStore(defaults: defaults, now: { self.now })
        fresh.save(log)
        XCTAssertEqual(fresh.load().count, 0)
    }

    // MARK: - Session model

    func testOlderStoredSessionsStillDecode() throws {
        let json = #"{"id":"1","date":"2026-10-20","startedAt":"s","endedAt":"e","scrollCount":4}"#
        let session = try JSONDecoder().decode(InstagramWrapperSession.self, from: Data(json.utf8))
        XCTAssertFalse(session.replayActive)
        XCTAssertEqual(session.freshReelCount, 0)
        XCTAssertEqual(session.replacedReelCount, 0)
    }

    func testReplayFieldsRoundTrip() throws {
        let original = InstagramWrapperSession(
            id: "1", date: "2026-10-25", startedAt: "s", endedAt: "e", scrollCount: 9,
            replayActive: true, freshReelCount: 3, repeatReelCount: 5, replacedReelCount: 4
        )
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(decoded.replayActive)
        XCTAssertEqual(decoded.freshReelCount, 3)
        XCTAssertEqual(decoded.repeatReelCount, 5)
        XCTAssertEqual(decoded.replacedReelCount, 4)
    }
}
