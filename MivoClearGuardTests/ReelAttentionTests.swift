import XCTest
@testable import Mivo

final class ReelAttentionTests: XCTestCase {
    private func session(
        reels: Int,
        seconds: [Double],
        kind: WrapperSessionLimit? = .reels,
        amount: Int = 10,
        afterSlowdown: Int = 0,
        cause: String? = nil
    ) -> InstagramWrapperSession {
        InstagramWrapperSession(
            id: UUID().uuidString,
            date: "2026-11-02",
            startedAt: "2026-11-02T20:00:00Z",
            endedAt: "2026-11-02T20:10:00Z",
            scrollCount: reels,
            limitKind: kind?.rawValue,
            limitAmount: kind == nil ? nil : amount,
            reelCount: reels,
            reelsAfterSlowdown: afterSlowdown,
            slowDownCause: cause,
            reelSeconds: seconds
        )
    }

    func testTooLittleDataGivesNoBandAndNoPlan() {
        let report = ReelAttentionReport(sessions: [session(reels: 30, seconds: Array(repeating: 2, count: 30))], days: 7)
        XCTAssertFalse(report.hasEnoughData)
        XCTAssertNil(report.band)
        XCTAssertNil(ReelPlan(report: report))
    }

    func testMedianAndQuickSkipShare() {
        let seconds: [Double] = [1, 2, 2.5, 5, 20, 40]
        let report = ReelAttentionReport(sessions: [session(reels: 6, seconds: seconds)], days: 7)
        XCTAssertEqual(report.medianSecondsPerReel ?? 0, 3.75, accuracy: 0.001)
        XCTAssertEqual(report.quickSkipShare ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(report.timedReels, 6)
    }

    func testBandCutoffs() {
        XCTAssertEqual(AttentionBand(medianSeconds: 3.9), .skimming)
        XCTAssertEqual(AttentionBand(medianSeconds: 4), .restless)
        XCTAssertEqual(AttentionBand(medianSeconds: 8), .steady)
        XCTAssertEqual(AttentionBand(medianSeconds: 15), .settled)
    }

    func testOnlySessionsThatKeptGoingAfterThePickCountAsGoingPast() {
        let sessions = [
            session(reels: 14, seconds: [], afterSlowdown: 4, cause: "pick"),
            session(reels: 10, seconds: [], afterSlowdown: 0, cause: "pick"),
            session(reels: 12, seconds: [], afterSlowdown: 2, cause: "today"),
            session(reels: 6, seconds: [])
        ]
        let report = ReelAttentionReport(sessions: sessions, days: 7)
        XCTAssertEqual(report.pickedSessions, 4)
        XCTAssertEqual(report.wentPastPick, 1)
        XCTAssertEqual(report.averageReelsPastPick ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(report.keptPickShare ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(report.totalReels, 42)
    }

    func testPlanLowersAKeptPick() {
        let sessions = (0..<4).map { _ in session(reels: 10, seconds: Array(repeating: 6, count: 9), cause: "pick") }
        let plan = ReelPlan(report: ReelAttentionReport(sessions: sessions, days: 7))
        XCTAssertEqual(plan?.suggestedReelPick, 8)
        XCTAssertTrue(plan?.steps.first?.contains("4 of 4") == true)
    }

    func testPlanHoldsAPickThatKeepsGettingPassed() {
        let sessions = (0..<4).map { _ in
            session(reels: 16, seconds: Array(repeating: 2, count: 9), afterSlowdown: 6, cause: "pick")
        }
        let plan = ReelPlan(report: ReelAttentionReport(sessions: sessions, days: 7))
        XCTAssertEqual(plan?.suggestedReelPick, 10)
        XCTAssertTrue(plan?.steps.contains { $0.contains("under 3 seconds") } == true)
    }

    func testPlanNeverGoesBelowTheSmallestPick() {
        let sessions = (0..<4).map { _ in session(reels: 5, seconds: Array(repeating: 10, count: 6), amount: 5) }
        XCTAssertEqual(ReelPlan(report: ReelAttentionReport(sessions: sessions, days: 7))?.suggestedReelPick, ReelPlan.smallestPick)
    }

    func testOlderSavedSessionsStillLoad() throws {
        let json = """
        {"id":"a","date":"2026-10-30","startedAt":"x","endedAt":"y","scrollCount":4,"freshReelCount":3,"repeatReelCount":2}
        """
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.reelCount, 5)
        XCTAssertNil(decoded.limitKind)
        XCTAssertEqual(decoded.reelSeconds, [])
    }

    func testNewFieldsSurviveARoundTrip() throws {
        let original = session(reels: 12, seconds: [1.5, 8], afterSlowdown: 2, cause: "pick")
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.limitKind, "reels")
        XCTAssertEqual(decoded.limitAmount, 10)
        XCTAssertEqual(decoded.reelCount, 12)
        XCTAssertEqual(decoded.reelsAfterSlowdown, 2)
        XCTAssertEqual(decoded.slowDownCause, "pick")
        XCTAssertEqual(decoded.reelSeconds, [1.5, 8])
    }

    func testPickStoreRemembersTheLastPick() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReelAttentionTests"))
        defaults.removePersistentDomain(forName: "ReelAttentionTests")
        XCTAssertEqual(WrapperPickStore.load(defaults: defaults).kind, .reels)
        XCTAssertEqual(WrapperPickStore.load(defaults: defaults).amount, 10)
        WrapperPickStore.save(.minutes, amount: 20, defaults: defaults)
        XCTAssertEqual(WrapperPickStore.load(defaults: defaults).kind, .minutes)
        XCTAssertEqual(WrapperPickStore.load(defaults: defaults).amount, 20)
    }

    func testTitlesFollowTheAmount() {
        XCTAssertEqual(WrapperSessionLimit.reels.title(amount: 15), "15 Reels")
        XCTAssertEqual(WrapperSessionLimit.reels.title(amount: 1), "1 Reel")
        XCTAssertEqual(WrapperSessionLimit.minutes.title(amount: 5), "5 minutes")
    }
}
