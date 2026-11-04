import XCTest
@testable import Mivo

final class AttentionJourneyTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testOneOpenCommitmentAndMeaningfulTitle() {
        var journey = AttentionJourney()
        XCTAssertFalse(journey.addCommitment(" \n "))
        XCTAssertFalse(journey.addCommitment("ok"))
        XCTAssertTrue(journey.addCommitment("  Read\n two   pages  "))
        XCTAssertEqual(journey.currentCommitment?.title, "Read two pages")
        XCTAssertFalse(journey.addCommitment("Write the introduction"))
    }

    func testSelfReportedCompletionCountsOnceAndFreesNextTask() {
        var journey = AttentionJourney()
        journey.addCommitment("Read two pages")
        let id = journey.currentCommitment!.id
        let completedAt = date("2026-11-01T15:00:00Z")
        XCTAssertTrue(journey.complete(id, now: completedAt))
        XCTAssertFalse(journey.complete(id, now: completedAt.addingTimeInterval(100)))
        XCTAssertEqual(journey.commitments.first?.evidence, .selfReported)
        XCTAssertEqual(journey.commitments.first?.completedAt, completedAt)
        XCTAssertTrue(journey.addCommitment("Write the introduction"))
    }

    func testProtectedTaskCannotBeSelfCompletedResizedOrSetAside() {
        var journey = AttentionJourney()
        let start = date("2026-11-01T15:00:00Z")
        journey.addCommitment("Write the introduction", now: start)
        let id = journey.currentCommitment!.id
        journey.linkLock(id: "lock-one", task: "Write the introduction", startedAt: start.addingTimeInterval(1))
        XCTAssertEqual(journey.commitments.count, 1)
        XCTAssertFalse(journey.complete(id))
        XCTAssertFalse(journey.resize(id, title: "Write one sentence"))
        journey.setAside(id)
        XCTAssertEqual(journey.currentCommitment?.status, .locked)
    }

    func testRepeatedLockHistoryDoesNotAddWins() {
        var journey = AttentionJourney()
        let start = date("2026-11-01T15:00:00Z")
        for _ in 0..<3 {
            journey.resolveLock(id: "lock-one", task: "Write the introduction", startedAt: start,
                                endedAt: start.addingTimeInterval(3600), evidence: .keyholderApproved)
        }
        XCTAssertEqual(journey.commitments.count, 1)
        XCTAssertEqual(journey.commitments.first?.evidence, .keyholderApproved)
        XCTAssertEqual(journey.commitments.first?.status, .completed)
    }

    func testExpiredLockAndSetAsideAreNotCompletions() {
        var journey = AttentionJourney()
        let start = date("2026-11-01T15:00:00Z")
        journey.resolveLock(id: "expired", task: "Write the introduction", startedAt: start,
                            endedAt: start.addingTimeInterval(3600), evidence: nil)
        journey.addCommitment("Read two pages", now: start)
        journey.setAside(journey.currentCommitment!.id)
        XCTAssertTrue(journey.completions(from: start, to: start.addingTimeInterval(86_400)).isEmpty)
        XCTAssertNil(journey.currentCommitment)
    }

    func testHistoricalLockCannotConsumeNewTaskWithTheSameName() {
        var journey = AttentionJourney()
        let start = date("2026-11-01T15:00:00Z")
        journey.addCommitment("Read two pages", now: start.addingTimeInterval(7200))
        let currentID = journey.currentCommitment?.id
        journey.resolveLock(id: "old", task: "Read two pages", startedAt: start,
                            endedAt: start.addingTimeInterval(3600), evidence: .miloReviewed)
        XCTAssertEqual(journey.currentCommitment?.id, currentID)
        XCTAssertEqual(journey.commitments.count, 2)
    }

    func testReportingPeriodIncludesStartAndExcludesEnd() {
        var journey = AttentionJourney()
        let start = date("2026-11-01T00:00:00Z")
        let end = date("2026-11-02T00:00:00Z")
        journey.addCommitment("Read two pages", now: start)
        journey.complete(journey.currentCommitment!.id, now: start)
        journey.addCommitment("Write the introduction", now: start)
        journey.complete(journey.currentCommitment!.id, now: end)
        XCTAssertEqual(journey.completions(from: start, to: end).map(\.title), ["Read two pages"])
    }

    func testRecoveryIsOneChoicePerLocalDayAcrossFallBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var journey = AttentionJourney()
        journey.chooseRecovery(.smallerTask, now: date("2026-11-01T05:30:00Z"), calendar: calendar)
        journey.chooseRecovery(.quietTime, now: date("2026-11-01T06:30:00Z"), calendar: calendar)
        XCTAssertEqual(journey.recoveries.count, 1)
        XCTAssertEqual(journey.recoveries.first?.choice, .quietTime)
        XCTAssertTrue(journey.commitments.isEmpty)
        journey.chooseRecovery(.messages, now: date("2026-11-02T06:30:00Z"), calendar: calendar)
        XCTAssertEqual(journey.recoveries.count, 2)
    }

    func testResizePreservesIdentityAndDoesNotClaimCompletion() {
        var journey = AttentionJourney()
        journey.addCommitment("Read the whole chapter")
        let id = journey.currentCommitment!.id
        XCTAssertTrue(journey.resize(id, title: "Read two pages"))
        XCTAssertEqual(journey.currentCommitment?.id, id)
        XCTAssertEqual(journey.currentCommitment?.title, "Read two pages")
        XCTAssertNil(journey.currentCommitment?.completedAt)
        XCTAssertNil(journey.currentCommitment?.evidence)
    }

    func testJourneyRoundTripsAndIsScopedByAccount() throws {
        let emailA = "attention-a-\(UUID().uuidString)@example.test"
        let emailB = "attention-b-\(UUID().uuidString)@example.test"
        defer {
            StorageService.remove(forKey: .attentionJourney, email: emailA)
            StorageService.remove(forKey: .attentionJourney, email: emailB)
        }
        var journey = AttentionJourney(problem: .study)
        journey.addCommitment("Read two pages")
        journey.chooseRecovery(.smallerTask)
        let restored = try JSONDecoder().decode(AttentionJourney.self, from: JSONEncoder().encode(journey))
        XCTAssertEqual(restored, journey)
        StorageService.save(journey, forKey: .attentionJourney, email: emailA)
        XCTAssertEqual(StorageService.load(AttentionJourney.self, forKey: .attentionJourney, email: emailA), journey)
        XCTAssertNil(StorageService.load(AttentionJourney.self, forKey: .attentionJourney, email: emailB))
        XCTAssertEqual(StorageService.scopedRawKey(for: .attentionJourney, email: emailA.uppercased()),
                       StorageService.scopedRawKey(for: .attentionJourney, email: emailA))
    }

    func testSharedVideoLinksAcceptOnlySupportedDirectMedia() {
        XCTAssertEqual(MivoClearSharedLink.route("https://www.instagram.com/reel/AbC123/")?.platform, .instagram)
        XCTAssertEqual(MivoClearSharedLink.route("https://www.tiktok.com/@person/video/123456789")?.platform, .tiktok)
        let youtube = MivoClearSharedLink.route("https://youtu.be/abcdefghijk?si=tracking")
        XCTAssertEqual(youtube?.platform, .youtube)
        XCTAssertEqual(youtube?.directURL?.absoluteString, "https://www.youtube.com/watch?v=abcdefghijk")
        for unsupported in [
            "http://www.instagram.com/reel/AbC123/", "https://instagram.com.evil.example/reel/AbC123/",
            "https://name@www.instagram.com/reel/AbC123/", "https://www.instagram.com/explore/",
            "https://www.tiktok.com/@person", "https://vm.tiktok.com/short/",
            "https://www.youtube.com/shorts/abcdefghijk", "https://www.youtube.com/watch?v=invalid"
        ] {
            XCTAssertNil(MivoClearSharedLink.route(unsupported), unsupported)
        }
    }

    func testExperimentNeedsBaselineAndResultEvidence() {
        func metrics(_ count: Int, minutes: Int, rate: Double = 0.5) -> ExperimentMetrics {
            ExperimentMetrics(comparableSessions: count, outsideWindowMinutes: minutes,
                              extensionRate: rate, cancellationRate: rate, truthAccuracyMinutes: 0, worthwhileRate: 0)
        }
        XCTAssertEqual(WeeklyExperimentComparison.outcome(type: .protectedWindow,
                       baseline: metrics(0, minutes: 0), result: metrics(5, minutes: 50)), .inconclusive)
        XCTAssertEqual(WeeklyExperimentComparison.outcome(type: .protectedWindow,
                       baseline: metrics(5, minutes: 100), result: metrics(2, minutes: 50)), .inconclusive)
        XCTAssertEqual(WeeklyExperimentComparison.outcome(type: .protectedWindow,
                       baseline: metrics(5, minutes: 100), result: metrics(5, minutes: 70)), .helped)
        XCTAssertEqual(WeeklyExperimentComparison.outcome(type: .strongerFriction,
                       baseline: metrics(5, minutes: 0, rate: 0), result: metrics(5, minutes: 0, rate: 0.5)), .inconclusive)
        XCTAssertEqual(WeeklyExperimentComparison.outcome(type: .reduceExtensions,
                       baseline: metrics(5, minutes: 0, rate: 0.5), result: metrics(5, minutes: 0, rate: 0.8)), .worsened)
    }
}
