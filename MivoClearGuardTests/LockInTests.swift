import XCTest
@testable import Mivo

// MARK: - Rules

final class LockInRulesTests: XCTestCase {
    func testTaskIsTidiedAndNeedsRealWords() {
        XCTAssertEqual(LockInRules.cleanTask("  finish   my\nessay  "), "finish my essay")
        XCTAssertNil(LockInRules.cleanTask("  "))
        XCTAssertNil(LockInRules.cleanTask("ok"))
        XCTAssertEqual(LockInRules.cleanTask(String(repeating: "a", count: 200))?.count, LockInRules.maxTaskLength)
    }

    func testDurationStaysBetweenTheShortestLockAndTheCap() {
        XCTAssertEqual(LockInRules.duration(minutes: 1), TimeInterval(LockInRules.minimumDurationMinutes * 60))
        XCTAssertEqual(LockInRules.duration(minutes: 120), 7200)
        XCTAssertEqual(LockInRules.duration(minutes: 24 * 60), TimeInterval(LockInKeys.hardCapHours * 3600))
    }

    func testEveryOfferedDurationIsWithinTheCap() {
        for minutes in LockInRules.durationChoicesMinutes {
            XCTAssertLessThanOrEqual(LockInRules.duration(minutes: minutes), TimeInterval(LockInKeys.hardCapHours * 3600))
        }
        XCTAssertTrue(LockInRules.durationChoicesMinutes.contains(LockInRules.defaultDurationMinutes))
    }

    func testMessagesAreTrimmedAndCapped() {
        XCTAssertEqual(LockInRules.cleanMessage("  hi  "), "hi")
        XCTAssertEqual(LockInRules.cleanMessage(String(repeating: "x", count: 5000)).count, LockInRules.maxMessageLength)
    }

    func testScreenTimeLockNeedsIOS26Point4() {
        func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        }
        XCTAssertFalse(LockInRules.supportsScreenTimeLock(version(18, 6)))
        XCTAssertFalse(LockInRules.supportsScreenTimeLock(version(26, 3)))
        XCTAssertTrue(LockInRules.supportsScreenTimeLock(version(26, 4)))
        XCTAssertTrue(LockInRules.supportsScreenTimeLock(version(26, 5)))
        XCTAssertTrue(LockInRules.supportsScreenTimeLock(version(27, 0)))
    }
}

// MARK: - Shared live state

final class LockInSharedTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "lockin.tests.\(UUID().uuidString)")!
        return defaults
    }

    func testNothingIsLiveUntilTheAppWritesIt() {
        XCTAssertNil(LockInLiveState.read(from: makeDefaults()))
        XCTAssertNil(LockInLiveState.read(from: nil))
    }

    func testALiveLockIsReadBack() {
        let defaults = makeDefaults()
        let now = Date()
        defaults.set(true, forKey: LockInKeys.liveActive)
        defaults.set("lock-1", forKey: LockInKeys.liveID)
        defaults.set("Write the outline", forKey: LockInKeys.liveTask)
        defaults.set(now.addingTimeInterval(1800).timeIntervalSince1970, forKey: LockInKeys.liveEndsAt)

        let live = LockInLiveState.read(from: defaults, now: now)
        XCTAssertEqual(live?.id, "lock-1")
        XCTAssertEqual(live?.task, "Write the outline")
        XCTAssertEqual(live?.minutesLeft(now: now), 30)
    }

    func testAnExpiredLockIsNeverLive() {
        let defaults = makeDefaults()
        let now = Date()
        defaults.set(true, forKey: LockInKeys.liveActive)
        defaults.set("lock-1", forKey: LockInKeys.liveID)
        defaults.set(now.addingTimeInterval(-1).timeIntervalSince1970, forKey: LockInKeys.liveEndsAt)
        XCTAssertNil(LockInLiveState.read(from: defaults, now: now))
    }
}

// MARK: - Model

final class LockInModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let apps = ScreenTimeAppSelection(data: nil, appNames: ["Instagram"], applicationCount: 1, categoryCount: 0, webDomainCount: 0)

    private func makeLock(keyholder: LockInKeyholder? = nil) -> LockIn {
        LockIn(
            id: "lock-1", task: "Write the outline", startedAt: start,
            endsAt: start.addingTimeInterval(7200), keyholder: keyholder, apps: apps
        )
    }

    private let activeKeyholder = LockInKeyholder(id: "kh", name: "Dana", emailMasked: "d***@x.com", status: .active)

    func testAFreshLockCanBeUndoneOnlyInTheFirstMinutes() {
        let lock = makeLock()
        XCTAssertTrue(lock.canCancelFreely(now: start.addingTimeInterval(60)))
        XCTAssertTrue(lock.canCancelFreely(now: start.addingTimeInterval(LockInRules.cancelGrace)))
        XCTAssertFalse(lock.canCancelFreely(now: start.addingTimeInterval(LockInRules.cancelGrace + 1)))
    }

    func testTalkingToMiloEndsTheFreeUndo() {
        var lock = makeLock()
        lock.messages = [LockInMessage(role: .user, text: "done")]
        XCTAssertFalse(lock.canCancelFreely(now: start.addingTimeInterval(10)))
    }

    func testPhaseFollowsRequestsAndRelease() {
        var lock = makeLock(keyholder: activeKeyholder)
        XCTAssertEqual(lock.phase, .locked)

        lock.requests = [LockInUnlockRequest(id: "r1", sentAt: start, status: .pending, keyholderNote: nil, summary: "s")]
        XCTAssertEqual(lock.phase, .waitingOnKeyholder)

        lock.requests[0].status = .declined
        XCTAssertEqual(lock.phase, .locked)

        lock.releaseReason = .keyholderApproved
        lock.releasedAt = start
        XCTAssertEqual(lock.phase, .released(.keyholderApproved))
        XCTAssertFalse(lock.isActive)
    }

    func testOnlyAnAgreedKeyholderCanBeAsked() {
        XCTAssertFalse(makeLock().canRequestKeyholder)
        let invited = LockInKeyholder(id: "kh", name: "Dana", emailMasked: "d***@x.com", status: .pending)
        XCTAssertFalse(makeLock(keyholder: invited).canRequestKeyholder)
        XCTAssertTrue(makeLock(keyholder: activeKeyholder).canRequestKeyholder)
    }

    func testRequestsAreLimitedPerLock() {
        var lock = makeLock(keyholder: activeKeyholder)
        lock.requests = (0..<LockInRules.maxUnlockRequests).map {
            LockInUnlockRequest(id: "r\($0)", sentAt: start, status: .declined, keyholderNote: nil, summary: "s")
        }
        XCTAssertFalse(lock.canRequestKeyholder)
    }

    func testOnlyCompletedReleasesCountAsDone() {
        XCTAssertTrue(LockInReleaseReason.miloConvinced.wasCompleted)
        XCTAssertTrue(LockInReleaseReason.keyholderApproved.wasCompleted)
        XCTAssertFalse(LockInReleaseReason.timeRanOut.wasCompleted)
        XCTAssertFalse(LockInReleaseReason.cancelledEarly.wasCompleted)
    }

    func testALockSurvivesStorage() throws {
        var lock = makeLock(keyholder: activeKeyholder)
        lock.messages = [LockInMessage(role: .user, text: "done", imageCount: 2, sentAt: start)]
        lock.miloSummary = "Showed it."
        let data = try JSONEncoder().encode(lock)
        XCTAssertEqual(try JSONDecoder().decode(LockIn.self, from: data), lock)
    }
}

// MARK: - Manager

@MainActor
final class LockInManagerTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var clock = TestClock()
    private var persistence = InMemoryLockInPersistence()
    private var screenTime = NoopLockInScreenTime()
    private var backend = InMemoryLockInBackend()

    private let apps = ScreenTimeAppSelection(data: nil, appNames: ["Instagram"], applicationCount: 1, categoryCount: 0, webDomainCount: 0)

    override func setUp() {
        super.setUp()
        clock = TestClock()
        persistence = InMemoryLockInPersistence()
        screenTime = NoopLockInScreenTime()
        backend = InMemoryLockInBackend()
    }

    private func makeManager() -> LockInManager {
        let manager = LockInManager(
            persistence: persistence, screenTime: screenTime, backend: backend, clock: { [clock] in clock.now }
        )
        manager.setAccount("tester@example.com")
        return manager
    }

    @discardableResult
    private func startLock(_ manager: LockInManager, task: String = "Write the outline", minutes: Int = 120) -> LockIn {
        guard case .started(let lock) = manager.start(task: task, durationMinutes: minutes, apps: apps) else {
            XCTFail("could not start a lock")
            return LockIn(id: "none", task: task, startedAt: clock.now, endsAt: clock.now, keyholder: nil, apps: apps)
        }
        return lock
    }

    private func agreeKeyholder(_ manager: LockInManager) async {
        backend.invitedKeyholder = LockInKeyholder(id: "kh-1", name: "Dana", emailMasked: "d***@example.com", status: .active)
        _ = await manager.inviteKeyholder(name: "Dana", email: "dana@example.com")
    }

    // MARK: Starting

    func testStartingShieldsTheAppsAndRemembersTheLock() {
        let manager = makeManager()
        let lock = startLock(manager)

        XCTAssertEqual(manager.current?.id, lock.id)
        XCTAssertEqual(lock.endsAt, clock.now.addingTimeInterval(7200))
        XCTAssertEqual(screenTime.started, [lock.id])
        XCTAssertEqual(persistence.loadCurrent()?.id, lock.id)
        XCTAssertEqual(manager.lastApps, apps)
    }

    func testAShortOrEmptyTaskDoesNotStartALock() {
        let manager = makeManager()
        XCTAssertEqual(manager.start(task: " ", durationMinutes: 60, apps: apps), .invalidTask)
        XCTAssertNil(manager.current)
        XCTAssertTrue(screenTime.started.isEmpty)
    }

    func testALockWithNothingToBlockDoesNotStart() {
        let manager = makeManager()
        let result = manager.start(task: "Write the outline", durationMinutes: 60, apps: .empty)
        XCTAssertEqual(result, .blocked([.noAppsSelected]))
        XCTAssertNil(manager.current)
    }

    func testWithoutScreenTimeAccessNothingIsLocked() {
        screenTime.isAuthorized = false
        let manager = makeManager()
        let result = manager.start(task: "Write the outline", durationMinutes: 60, apps: apps)
        XCTAssertEqual(result, .blocked([.screenTimeNotAuthorized]))
        XCTAssertNil(manager.current)
    }

    func testOnlyOneLockRunsAtATime() {
        let manager = makeManager()
        startLock(manager)
        XCTAssertEqual(manager.start(task: "Another thing", durationMinutes: 60, apps: apps), .alreadyLocked)
    }

    func testARunningLockIsRestoredForTheSameAccount() {
        let first = makeManager()
        let lock = startLock(first)

        let second = LockInManager(persistence: persistence, screenTime: screenTime, backend: backend, clock: { [clock] in clock.now })
        second.setAccount("tester@example.com")
        XCTAssertEqual(second.current?.id, lock.id)
    }

    // MARK: Time

    func testTheLockEndsAtTheCheckInTimeAndCountsAsNotDone() {
        let manager = makeManager()
        let lock = startLock(manager)
        clock.advance(7200)

        manager.reconcile()

        XCTAssertNil(manager.current)
        XCTAssertEqual(screenTime.endCount, 1)
        XCTAssertEqual(manager.history.first?.releaseReason, .timeRanOut)
        XCTAssertEqual(manager.history.first?.releasedAt, lock.endsAt)
        XCTAssertEqual(manager.justReleased?.releaseReason, .timeRanOut)
    }

    func testBeforeTheCheckInTheLockHolds() {
        let manager = makeManager()
        startLock(manager)
        clock.advance(7199)
        manager.reconcile()
        XCTAssertNotNil(manager.current)
    }

    func testAShieldTornDownEarlyIsPutBack() {
        let manager = makeManager()
        startLock(manager)
        screenTime.end()
        let startsBefore = screenTime.started.count

        manager.reconcile()

        XCTAssertNotNil(manager.current)
        XCTAssertEqual(screenTime.started.count, startsBefore + 1)
    }

    func testAShieldTapAsksForTheLockScreen() {
        let manager = makeManager()
        startLock(manager)
        screenTime.pendingRoute = true
        manager.reconcile()
        XCTAssertTrue(manager.showRequested)
    }

    // MARK: Undo

    func testAMistakeCanBeUndoneRightAway() {
        let manager = makeManager()
        startLock(manager)
        clock.advance(30)

        XCTAssertTrue(manager.cancelFreely())

        XCTAssertNil(manager.current)
        XCTAssertEqual(manager.history.first?.releaseReason, .cancelledEarly)
        XCTAssertNil(manager.justReleased, "a mistaken start doesn't earn a wrap-up")
    }

    func testTheUndoClosesAfterTheGraceWindow() {
        let manager = makeManager()
        startLock(manager)
        clock.advance(LockInRules.cancelGrace + 5)
        XCTAssertFalse(manager.cancelFreely())
        XCTAssertNotNil(manager.current)
    }

    // MARK: Milo

    func testAConvincedMiloUnlocksWhenThereIsNoKeyholder() async {
        let manager = makeManager()
        startLock(manager)

        let outcome = await manager.send(text: "I finished the outline", images: [])

        guard case .sent(let review) = outcome else { return XCTFail("expected sent, got \(outcome)") }
        XCTAssertEqual(review.verdict, .convinced)
        XCTAssertNil(manager.current)
        XCTAssertEqual(manager.history.first?.releaseReason, .miloConvinced)
        XCTAssertEqual(manager.history.first?.messages.count, 2)
        XCTAssertEqual(screenTime.endCount, 1)
    }

    func testMiloAsksForMoreAndTheLockStays() async {
        backend.reviews = [MiloReview(verdict: .needsMore, reply: "Show me the page.", summary: "")]
        let manager = makeManager()
        startLock(manager)

        _ = await manager.send(text: "I did it", images: [])

        XCTAssertNotNil(manager.current)
        XCTAssertEqual(manager.current?.messages.map(\.role), [.user, .milo])
        XCTAssertEqual(manager.current?.messages.last?.text, "Show me the page.")
        XCTAssertNil(manager.current?.miloSummary)
    }

    func testMiloCanBeConvincedOnTheSecondTry() async {
        backend.reviews = [
            MiloReview(verdict: .notYet, reply: "That doesn't show it.", summary: ""),
            MiloReview(verdict: .convinced, reply: "That's done.", summary: "Showed the outline.")
        ]
        let manager = makeManager()
        startLock(manager)

        _ = await manager.send(text: "done", images: [])
        XCTAssertNotNil(manager.current)
        _ = await manager.send(text: "here is the outline", images: [Data([1])])

        XCTAssertNil(manager.current)
        XCTAssertEqual(backend.lastImageCount, 1)
        XCTAssertEqual(manager.history.first?.releaseReason, .miloConvinced)
    }

    func testAFailedReviewAddsNothingToTheChat() async {
        backend.failure = .offline
        let manager = makeManager()
        startLock(manager)

        let outcome = await manager.send(text: "I finished", images: [])

        XCTAssertEqual(outcome, .failed(.offline))
        XCTAssertEqual(manager.current?.messages.count, 0)
        XCTAssertFalse(manager.isReviewing)
    }

    func testAnEmptyMessageIsNotSent() async {
        let manager = makeManager()
        startLock(manager)
        let outcome = await manager.send(text: "   ", images: [])
        XCTAssertEqual(outcome, .notAllowed)
        XCTAssertEqual(backend.reviewCalls, 0)
    }

    func testAtMostThreePhotosReachMilo() async {
        backend.reviews = [MiloReview(verdict: .needsMore, reply: "Hm.", summary: "")]
        let manager = makeManager()
        startLock(manager)

        _ = await manager.send(text: "look", images: (0..<6).map { Data([UInt8($0)]) })

        XCTAssertEqual(backend.lastImageCount, LockInRules.maxImagesPerMessage)
        XCTAssertEqual(manager.current?.messages.first?.imageCount, LockInRules.maxImagesPerMessage)
    }

    func testTheChatIsLimitedPerLock() async {
        backend.reviews = [MiloReview(verdict: .notYet, reply: "No.", summary: "")]
        let manager = makeManager()
        startLock(manager)

        for index in 0..<LockInRules.maxUserMessages {
            _ = await manager.send(text: "try \(index)", images: [])
        }
        let outcome = await manager.send(text: "one more", images: [])

        XCTAssertEqual(outcome, .notAllowed)
        XCTAssertEqual(backend.reviewCalls, LockInRules.maxUserMessages)
    }

    // MARK: Keyholder

    func testABadEmailIsRejectedBeforeAnythingIsSent() async {
        let manager = makeManager()
        let result = await manager.inviteKeyholder(name: "Dana", email: "not an email")
        XCTAssertEqual(result, .failure(.invalidEmail))
        XCTAssertTrue(backend.invites.isEmpty)
    }

    func testInvitingKeepsTheKeyholderOnTheDevice() async {
        let manager = makeManager()
        _ = await manager.inviteKeyholder(name: " Dana ", email: " Dana@Example.com ")

        XCTAssertEqual(backend.invites.first?.name, "Dana")
        XCTAssertEqual(backend.invites.first?.email, "dana@example.com")
        XCTAssertEqual(manager.keyholder?.name, "Dana")
        XCTAssertEqual(persistence.loadKeyholder()?.id, "kh-1")
    }

    func testAKeyholderWhoHasntAgreedDoesNotBlockMilo() async {
        let manager = makeManager()
        _ = await manager.inviteKeyholder(name: "Dana", email: "dana@example.com")
        XCTAssertEqual(manager.keyholder?.status, .pending)
        startLock(manager)

        _ = await manager.send(text: "I finished", images: [])

        XCTAssertNil(manager.current)
    }

    func testWithAKeyholderMiloOnlyRecommends() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)

        _ = await manager.send(text: "I finished the outline", images: [])

        XCTAssertNotNil(manager.current, "the keyholder has the last word")
        XCTAssertEqual(manager.current?.miloSummary, "Showed the finished work.")
        XCTAssertTrue(manager.current?.canRequestKeyholder == true)
    }

    func testAskingSendsMilosSummaryAndWaits() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)
        _ = await manager.send(text: "I finished the outline", images: [])

        let result = await manager.askKeyholder()

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(backend.unlockRequests.first?.summary, "Showed the finished work.")
        XCTAssertEqual(backend.unlockRequests.first?.task, "Write the outline")
        XCTAssertEqual(manager.current?.phase, .waitingOnKeyholder)
        let blocked = await manager.send(text: "also this", images: [])
        XCTAssertEqual(blocked, .notAllowed, "nothing more can be added while a request is out")
    }

    func testSkippingMiloTellsTheKeyholderSo() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)
        backend.reviews = [MiloReview(verdict: .notYet, reply: "Not yet.", summary: "")]
        _ = await manager.send(text: "I think I'm done", images: [])

        _ = await manager.askKeyholder()

        let summary = backend.unlockRequests.first?.summary ?? ""
        XCTAssertTrue(summary.hasPrefix("Milo hasn't reviewed this"))
        XCTAssertTrue(summary.contains("I think I'm done"))
    }

    func testAnApprovalEndsTheLock() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)
        _ = await manager.send(text: "done", images: [])
        _ = await manager.askKeyholder()

        backend.requestAnswer = .approved
        await manager.pollKeyholderRequest()

        XCTAssertNil(manager.current)
        XCTAssertEqual(manager.history.first?.releaseReason, .keyholderApproved)
        XCTAssertEqual(screenTime.endCount, 1)
    }

    func testADeclineKeepsTheLockAndKeepsTheNote() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)
        _ = await manager.send(text: "done", images: [])
        _ = await manager.askKeyholder()

        backend.requestAnswer = .declined
        backend.requestNote = "Send me the page first."
        await manager.pollKeyholderRequest()

        XCTAssertNotNil(manager.current)
        XCTAssertEqual(manager.current?.requests.last?.status, .declined)
        XCTAssertEqual(manager.current?.requests.last?.keyholderNote, "Send me the page first.")
        XCTAssertNil(manager.current?.pendingRequest)
        XCTAssertTrue(manager.current?.canRequestKeyholder == true, "they may try again")
    }

    func testAStillPendingRequestChangesNothing() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)
        _ = await manager.send(text: "done", images: [])
        _ = await manager.askKeyholder()

        await manager.pollKeyholderRequest()

        XCTAssertEqual(manager.current?.phase, .waitingOnKeyholder)
    }

    func testTheKeyholderCantBeRemovedMidLock() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)

        let removed = await manager.removeKeyholder()

        XCTAssertFalse(removed)
        XCTAssertNotNil(manager.keyholder)
        XCTAssertTrue(backend.revoked.isEmpty)
    }

    func testTheKeyholderCanBeRemovedBetweenLocks() async {
        let manager = makeManager()
        await agreeKeyholder(manager)

        let removed = await manager.removeKeyholder()

        XCTAssertTrue(removed)
        XCTAssertNil(manager.keyholder)
        XCTAssertEqual(backend.revoked, ["kh-1"])
    }

    func testRefreshingPicksUpTheFriendAgreeing() async {
        let manager = makeManager()
        _ = await manager.inviteKeyholder(name: "Dana", email: "dana@example.com")
        XCTAssertEqual(manager.keyholder?.status, .pending)

        backend.keyholderStatusAnswer = .active
        await manager.refreshKeyholder()

        XCTAssertEqual(manager.keyholder?.status, .active)
    }

    // MARK: Account

    func testSigningOutLiftsTheLock() {
        let manager = makeManager()
        startLock(manager)

        manager.signOut()

        XCTAssertNil(manager.current)
        XCTAssertEqual(screenTime.endCount, 1)
    }

    func testAnotherAccountNeverInheritsALock() {
        let manager = makeManager()
        startLock(manager)

        manager.setAccount("someone-else@example.com")

        XCTAssertNil(manager.current)
        XCTAssertEqual(screenTime.endCount, 1)
    }

    func testDeletingTheAccountErasesEverything() async {
        let manager = makeManager()
        await agreeKeyholder(manager)
        startLock(manager)

        manager.eraseAllData()

        XCTAssertNil(manager.current)
        XCTAssertNil(manager.keyholder)
        XCTAssertNil(persistence.loadCurrent())
        XCTAssertNil(persistence.loadKeyholder())
    }

    // MARK: Links

    func testTheLockInLinkOpensTheScreen() {
        let manager = makeManager()
        XCTAssertTrue(manager.handle(url: URL(string: "mivo://lockin")!))
        XCTAssertTrue(manager.showRequested)
    }

    func testOtherLinksAreLeftAlone() {
        let manager = makeManager()
        XCTAssertFalse(manager.handle(url: URL(string: "mivo://companion")!))
        XCTAssertFalse(manager.handle(url: URL(string: "https://usemivo.app/room/ABC")!))
        XCTAssertFalse(manager.showRequested)
    }

    // MARK: Helpers

    func testPlausibleEmails() {
        XCTAssertTrue(LockInManager.isPlausibleEmail("a@b.co"))
        XCTAssertFalse(LockInManager.isPlausibleEmail("a@b"))
        XCTAssertFalse(LockInManager.isPlausibleEmail("@b.co"))
        XCTAssertFalse(LockInManager.isPlausibleEmail("a b@c.co"))
        XCTAssertFalse(LockInManager.isPlausibleEmail("a@@b.co"))
    }
}

// MARK: - Backend error mapping

final class LockInBackendMappingTests: XCTestCase {
    func testServerAnswersBecomeFriendlyErrors() {
        XCTAssertEqual(SupabaseLockInBackend.map(status: 401, code: nil), .signedOut)
        XCTAssertEqual(SupabaseLockInBackend.map(status: 429, code: nil), .rateLimited)
        XCTAssertEqual(SupabaseLockInBackend.map(status: 400, code: "rate_limited"), .rateLimited)
        XCTAssertEqual(SupabaseLockInBackend.map(status: 400, code: "valid_email_required"), .invalidEmail)
        XCTAssertEqual(SupabaseLockInBackend.map(status: 500, code: nil), .failed)
    }
}
