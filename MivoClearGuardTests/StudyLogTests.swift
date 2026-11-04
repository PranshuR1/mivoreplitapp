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

    func testPhoneStudyPlanNormalizesMaterialsAndBoundsProtectionTime() throws {
        XCTAssertEqual(PhoneStudyPlan.website("https://www.School.edu/notes?q=private"), "school.edu")
        XCTAssertNil(PhoneStudyPlan.website("file:///notes"))
        XCTAssertNil(PhoneStudyPlan.website("https://name:password@school.edu"))
        XCTAssertNil(PhoneStudyPlan.website("not a domain"))
        XCTAssertEqual(PhoneStudyPlan(minutes: -20).goalSeconds, 15 * 60)
        XCTAssertEqual(PhoneStudyPlan(minutes: 900).goalSeconds, 120 * 60)
        let plan = PhoneStudyPlan(outcome: "Five questions", websites: ["school.edu"])
        XCTAssertEqual(try JSONDecoder().decode(PhoneStudyPlan.self, from: JSONEncoder().encode(plan)), plan)
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

    // MARK: - Syncing with the account

    private func remote(_ start: String, minutes: Int, id: UUID = UUID(), task: String = "Notes") -> RemoteStudySession {
        let startedAt = date(start)
        return RemoteStudySession(id: id, task: task, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(Double(minutes * 60)))
    }

    func testSessionsSavedBeforeOriginExistedAreTreatedAsRunOnThePhone() throws {
        let old = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","task":"Notes","startedAt":0,"endedAt":600,"recordedSeconds":600,"scrollSecondsEarned":200}
        """
        let decoded = try JSONDecoder().decode(StudyEntry.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.origin, .phone)
        let roundTrip = try JSONDecoder().decode(StudyEntry.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    func testMergeBringsInTheWebsitesSessionsAsRemoteAndCountsThemForTheStreak() {
        var log = StudyLog(entries: [entry("2026-10-27T09:00:00Z", minutes: 15)])
        log.merge(remote: [remote("2026-10-28T09:00:00Z", minutes: 12)], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.last?.origin, .remote)
        XCTAssertEqual(log.entries.last?.recordedSeconds, 0)
        XCTAssertEqual(log.entries.last?.scrollSecondsEarned, 0)
        XCTAssertEqual(log.streak(asOf: date("2026-10-28T20:00:00Z"), calendar: calendar), 2)
    }

    func testMergeNeverDoublesASessionThePhoneAlreadyHas() {
        let own = entry("2026-10-27T09:00:00Z", minutes: 15)
        var log = StudyLog(entries: [own])
        log.merge(remote: [remote("2026-10-27T09:00:00Z", minutes: 15, id: own.id)], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.entries, [own])
    }

    func testSessionsFromTheAccountDoNotStartTheFreeWeek() {
        var log = StudyLog()
        log.merge(remote: [remote("2026-10-20T09:00:00Z", minutes: 30)], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertNil(log.firstSessionAt)
        log.entries.append(entry("2026-10-27T09:00:00Z", minutes: 15))
        XCTAssertEqual(log.firstSessionAt, date("2026-10-27T09:00:00Z"))
    }

    func testASessionDeletedOnTheWebsiteLeavesTheLogButOnlyInsideTheWindowTheAccountAnsweredFor() {
        let gone = remote("2026-10-20T09:00:00Z", minutes: 30)
        let tooOld = remote("2026-03-01T09:00:00Z", minutes: 30)
        var log = StudyLog()
        log.merge(remote: [gone, tooOld], windowStart: date("2026-01-01T00:00:00Z"))
        XCTAssertEqual(log.entries.count, 2)
        // The account now holds neither, and spoke only for the last 120 days.
        log.merge(remote: [], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.entries.map(\.id), [tooOld.id])
    }

    func testMergeNeverRemovesASessionRunOnThePhone() {
        var log = StudyLog(entries: [entry("2026-10-20T09:00:00Z", minutes: 30)])
        log.merge(remote: [], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.entries.count, 1)
    }

    func testOnlyPhoneSessionsNotYetSavedAreSent() {
        let saved = entry("2026-10-25T09:00:00Z", minutes: 15)
        let fresh = entry("2026-10-26T09:00:00Z", minutes: 15)
        var log = StudyLog(entries: [saved, fresh])
        log.merge(remote: [remote("2026-10-27T09:00:00Z", minutes: 15)], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.unsynced(alreadySynced: [saved.id]).map(\.id), [fresh.id])
    }

    func testDuplicateRemoteRowsDoNotDoubleStudyTime() {
        let session = remote("2026-10-28T09:00:00Z", minutes: 10)
        var log = StudyLog()
        log.merge(remote: [session, session], windowStart: date("2026-07-01T00:00:00Z"))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.seconds(on: date("2026-10-28T12:00:00Z"), calendar: calendar), 600)
    }

    func testRemoteEditsRefreshTheExistingCopy() {
        var session = remote("2026-10-28T09:00:00Z", minutes: 10)
        var log = StudyLog()
        let window = date("2026-07-01T00:00:00Z")
        log.merge(remote: [session], windowStart: window)
        session.task = "Updated notes"
        session.endedAt.addTimeInterval(300)
        log.merge(remote: [session], windowStart: window)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries.first?.task, "Updated notes")
        XCTAssertEqual(log.entries.first?.seconds, 900)
    }

    func testRoomLinkNeedsARoom() {
        XCTAssertNil(StudyRoomState.none.url)
        var room = StudyRoomState.none
        room.hasRoom = true
        room.code = "43FFT2F7JA"
        XCTAssertEqual(room.url?.absoluteString, "https://usemivo.app/room/43FFT2F7JA")
    }
}

/// Stands in for the account: records what it is sent and answers from what a test queued.
private final class FakeStudyBackend: StudyBackend {
    var failure: Error?
    var remoteSessions: [RemoteStudySession] = []
    var roomState = StudyRoomState.none
    var beforePull: (() async -> Void)?
    var onPush: (() -> Void)?
    var beforeRoom: (() async -> Void)?
    private(set) var pushed: [[StudyEntry]] = []
    private(set) var pings: [(task: String, startedAt: Date)] = []
    private(set) var endedLive = 0

    func push(_ entries: [StudyEntry]) async throws {
        if let failure { throw failure }
        pushed.append(entries)
        onPush?()
    }
    func pull(since: Date) async throws -> [RemoteStudySession] {
        await beforePull?()
        if let failure { throw failure }
        return remoteSessions
    }
    func room() async throws -> StudyRoomState {
        if let failure { throw failure }
        let state = roomState
        await beforeRoom?()
        return state
    }
    func ensureRoom() async throws -> StudyRoomState {
        if let failure { throw failure }
        if !roomState.hasRoom {
            roomState = StudyRoomState(hasRoom: true, code: "ABCDEFGH23", displayName: "Maya", isOpen: false, showTask: true, studying: false, sitting: [])
        }
        return roomState
    }
    func updateRoom(displayName: String?, isOpen: Bool?, showTask: Bool?) async throws -> StudyRoomState {
        if let failure { throw failure }
        if let isOpen { roomState.isOpen = isOpen }
        if let showTask { roomState.showTask = showTask }
        if let displayName { roomState.displayName = displayName }
        return roomState
    }
    func rotateRoomLink() async throws -> StudyRoomState {
        if let failure { throw failure }
        roomState.code = "ZZZZZZZZ99"
        return roomState
    }
    func removeVisitor(_ id: UUID) async throws -> StudyRoomState {
        if let failure { throw failure }
        roomState.sitting.removeAll { $0.id == id }
        return roomState
    }
    func ping(task: String, startedAt: Date) async throws -> StudyRoomState {
        if let failure { throw failure }
        pings.append((task, startedAt))
        return roomState
    }
    func endLive() async throws -> StudyRoomState {
        if let failure { throw failure }
        endedLive += 1
        return roomState
    }
}

@MainActor
final class StudySyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var backend: FakeStudyBackend!
    private var email: String? = "maya@example.com"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "StudySyncTests.\(UUID().uuidString)")
        backend = FakeStudyBackend()
        email = "maya@example.com"
    }

    private func makeService() -> StudyService {
        StudyService(
            defaults: defaults,
            balanceStore: ReelBalanceStore(defaults: defaults, account: { [unowned self] in self.email }),
            backend: backend,
            account: { [unowned self] in self.email }
        )
    }

    private func store(_ entries: [StudyEntry], for account: String = "maya@example.com") {
        let log = StudyLog(entries: entries)
        defaults.set(try? JSONEncoder().encode(log), forKey: AccountScopedKey.make("mivo.study.log", account: account))
    }

    private func phoneEntry(daysAgo: Double) -> StudyEntry {
        let start = Date().addingTimeInterval(-daysAgo * 86_400)
        return StudyEntry(task: "Notes", startedAt: start, endedAt: start.addingTimeInterval(1_200), recordedSeconds: 1_200, scrollSecondsEarned: 400)
    }

    func testSyncSendsPhoneSessionsOnceAndBringsTheWebsitesIn() async {
        let own = phoneEntry(daysAgo: 1)
        store([own])
        let web = RemoteStudySession(id: UUID(), task: "From the site", startedAt: Date().addingTimeInterval(-3 * 86_400), endedAt: Date().addingTimeInterval(-3 * 86_400 + 900))
        backend.remoteSessions = [web]
        let service = makeService()

        await service.syncNow()
        XCTAssertEqual(backend.pushed.flatMap { $0 }.map(\.id), [own.id])
        XCTAssertEqual(service.log.entries.count, 2)
        XCTAssertEqual(service.log.entries.first?.origin, .remote)

        await service.syncNow()
        XCTAssertEqual(backend.pushed.count, 1, "a session already saved is not sent again")
    }

    func testTheSavedStateSurvivesARelaunch() async {
        store([phoneEntry(daysAgo: 1)])
        await makeService().syncNow()
        let relaunched = makeService()
        await relaunched.syncNow()
        XCTAssertEqual(backend.pushed.count, 1)
    }

    func testAFailedSaveIsRetriedNextTime() async {
        store([phoneEntry(daysAgo: 1)])
        backend.failure = MivoBackendError.unavailable
        let service = makeService()
        await service.syncNow()
        XCTAssertTrue(backend.pushed.isEmpty)

        backend.failure = nil
        await service.syncNow()
        XCTAssertEqual(backend.pushed.count, 1)
    }

    func testNothingIsSentWhenSignedOut() async {
        store([phoneEntry(daysAgo: 1)])
        email = nil
        await makeService().syncNow()
        XCTAssertTrue(backend.pushed.isEmpty)
    }

    func testSessionsNeverMixAcrossAccounts() async {
        store([phoneEntry(daysAgo: 1)], for: "other@example.com")
        let service = makeService()
        await service.syncNow()
        XCTAssertTrue(backend.pushed.isEmpty)
        XCTAssertTrue(service.log.entries.isEmpty)
    }

    func testAnAccountWithoutRoomsYetHidesTheRoomQuietly() async {
        backend.failure = MivoBackendError.server("Could not find the function public.my_study_room in the schema cache")
        let service = makeService()
        await service.syncNow()
        XCTAssertFalse(service.roomAvailable)
        XCTAssertNil(service.roomMessage)
    }

    func testOpeningTheRoomMakesItAndOpensIt() async {
        let service = makeService()
        await service.setRoomOpen(true)
        XCTAssertEqual(service.room?.isOpen, true)
        XCTAssertEqual(service.room?.code, "ABCDEFGH23")
        await service.setRoomShowsTask(false)
        XCTAssertEqual(service.room?.showTask, false)
        await service.rotateRoomLink()
        XCTAssertEqual(service.room?.code, "ZZZZZZZZ99")
    }

    func testARoomFailureIsExplainedNotThrown() async {
        backend.failure = MivoBackendError.unavailable
        let service = makeService()
        await service.setRoomOpen(true)
        XCTAssertNotNil(service.roomMessage)
        XCTAssertTrue(service.roomAvailable)
    }

    func testOldAccountResponseCannotPopulateTheNewAccountsLog() async {
        let pulling = expectation(description: "Pull in flight")
        var resumePull: CheckedContinuation<Void, Never>?
        backend.remoteSessions = [RemoteStudySession(id: UUID(), task: "Private study", startedAt: Date().addingTimeInterval(-900), endedAt: Date())]
        backend.beforePull = {
            await withCheckedContinuation {
                resumePull = $0
                pulling.fulfill()
            }
        }
        let service = makeService()
        let sync = Task { await service.syncNow() }
        await fulfillment(of: [pulling], timeout: 2)
        email = "other@example.com"
        service.bind()
        resumePull?.resume()
        await sync.value
        XCTAssertTrue(service.log.entries.isEmpty)
    }

    func testSlowRoomRefreshCannotUndoANewerToggle() async {
        let service = makeService()
        await service.setRoomOpen(true)
        let reading = expectation(description: "Old room state in flight")
        var resumeRoom: CheckedContinuation<Void, Never>?
        backend.beforeRoom = {
            await withCheckedContinuation {
                resumeRoom = $0
                reading.fulfill()
            }
        }
        let refresh = Task { await service.refreshRoom() }
        await fulfillment(of: [reading], timeout: 2)
        await service.setRoomOpen(false)
        resumeRoom?.resume()
        await refresh.value
        XCTAssertEqual(service.room?.isOpen, false)
    }

    func testRoomAvailabilityIsRetriedForTheNextAccount() async {
        backend.failure = MivoBackendError.server("Could not find the function")
        let service = makeService()
        await service.refreshRoom()
        XCTAssertFalse(service.roomAvailable)
        email = "other@example.com"
        backend.failure = nil
        service.bind()
        XCTAssertTrue(service.roomAvailable)
        await service.refreshRoom()
        XCTAssertEqual(service.room, StudyRoomState.none)
    }

    func testFailuresAreClassifiedByWhatToDoNext() {
        XCTAssertEqual(StudyBackendFailure.classify(MivoBackendError.unavailable), .offline)
        XCTAssertEqual(StudyBackendFailure.classify(MivoBackendError.authenticationRequired), .signedOut)
        XCTAssertEqual(StudyBackendFailure.classify(MivoBackendError.server("JWT expired")), .signedOut)
        XCTAssertEqual(StudyBackendFailure.classify(MivoBackendError.server("Could not find the function")), .notReady)
        XCTAssertEqual(StudyBackendFailure.classify(MivoBackendError.server("room_full")), .failed)
        XCTAssertEqual(StudyBackendFailure.classify(URLError(.notConnectedToInternet)), .offline)
    }
}

/// Suspends capture at real async boundaries so double taps and account changes can be reproduced.
private actor FakeStudyRecording: StudyRecording {
    var starts = 0
    var stops = 0
    let succeeds: Bool
    let seconds: Double
    let onStart: (() -> Void)?
    let onStop: (() -> Void)?
    let holdStart: Bool
    let holdStop: Bool
    private var startWaiter: CheckedContinuation<Bool, Never>?
    private var stopWaiter: CheckedContinuation<Double, Never>?

    init(succeeds: Bool = true, seconds: Double = 900, holdStart: Bool = false, holdStop: Bool = false,
         onStart: (() -> Void)? = nil, onStop: (() -> Void)? = nil) {
        self.succeeds = succeeds
        self.seconds = seconds
        self.holdStart = holdStart
        self.holdStop = holdStop
        self.onStart = onStart
        self.onStop = onStop
    }

    func start(to url: URL) async -> Bool {
        starts += 1
        if holdStart {
            return await withCheckedContinuation {
                startWaiter = $0
                onStart?()
            }
        }
        onStart?()
        return succeeds
    }

    func stop() async -> Double {
        stops += 1
        if holdStop && stops == 1 {
            return await withCheckedContinuation {
                stopWaiter = $0
                onStop?()
            }
        }
        if stops == 1 { onStop?() }
        return seconds
    }

    func releaseStart() { startWaiter?.resume(returning: succeeds); startWaiter = nil }
    func releaseStop() { stopWaiter?.resume(returning: seconds); stopWaiter = nil }
}

@MainActor
private final class FakeStudyProtection: StudyFocusProtecting {
    var failure: String?
    var starts: [(Data?, Date)] = []
    var endCount = 0
    func begin(selection: Data?, endsAt: Date) -> String? {
        starts.append((selection, endsAt))
        return failure
    }
    func end() { endCount += 1 }
}

@MainActor
final class StudyLifecycleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var currentDate = Date()
    private var email: String? = "study@example.com"

    override func setUp() {
        super.setUp()
        suite = "StudyLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        currentDate = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
        email = "study@example.com"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func service(_ recorder: StudyRecording, verified: Int = 900, protection: StudyFocusProtecting? = nil) -> StudyService {
        StudyService(
            defaults: defaults,
            balanceStore: ReelBalanceStore(defaults: defaults, now: { [self] in currentDate }, account: { [self] in email }),
            backend: FakeStudyBackend(),
            recording: recorder,
            protection: protection ?? FakeStudyProtection(),
            now: { [self] in currentDate },
            verifyVideo: { _ in verified },
            account: { [self] in email }
        )
    }

    func testStudyPlanPersistsWithReceiptAndProtectionUsesItsFocusGoal() async {
        let protection = FakeStudyProtection()
        let study = service(FakeStudyRecording(seconds: 600), verified: 600, protection: protection)
        let plan = PhoneStudyPlan(outcome: "Answer five questions", minutes: 25, websites: ["school.edu"],
                                  distractionSelection: Data([1, 2, 3]), distractionCount: 2)
        await study.start(task: "Biology", plan: plan)
        guard case .running(let active) = study.phase else { return XCTFail("Expected study to start") }
        XCTAssertEqual(active.plan, plan)
        XCTAssertEqual(study.savedPlan, plan)
        XCTAssertEqual(protection.starts.last?.0, plan.distractionSelection)
        XCTAssertEqual(protection.starts.last?.1, currentDate.addingTimeInterval(25 * 60))
        currentDate = currentDate.addingTimeInterval(600)
        await study.finish(hasPlus: true)
        guard case .finished(let receipt) = study.phase else { return XCTFail("Expected receipt") }
        XCTAssertEqual(receipt.entry.plan, plan)
        XCTAssertEqual(protection.endCount, 1)
    }

    func testErasingStudyDataRemovesThePrivateSetup() async {
        let study = service(FakeStudyRecording())
        await study.start(task: "Notes", plan: PhoneStudyPlan(outcome: "Private finish line", websites: ["school.edu"]))
        study.eraseAllData()
        XCTAssertNil(defaults.data(forKey: AccountScopedKey.make("mivo.study.setup", account: email)))
    }

    func testStudyProtectionFailureKeepsSetupOpen() async {
        let protection = FakeStudyProtection()
        protection.failure = "Allow Screen Time access"
        let recorder = FakeStudyRecording()
        let study = service(recorder, protection: protection)
        await study.start(task: "Notes", plan: PhoneStudyPlan(distractionSelection: Data([1]), distractionCount: 1))
        XCTAssertEqual(study.phase, .idle)
        XCTAssertFalse(study.isStarting)
        XCTAssertEqual(study.startMessage, protection.failure)
        XCTAssertNil(defaults.data(forKey: AccountScopedKey.make("mivo.study.active", account: email)))
        let stops = await recorder.stops
        XCTAssertEqual(stops, 1)
    }

    func testStudyInterruptionAndSignOutReleaseOnlyStudyProtection() async {
        let protection = FakeStudyProtection()
        let study = service(FakeStudyRecording(), protection: protection)
        await study.start(task: "Notes", plan: PhoneStudyPlan())
        study.interrupt()
        XCTAssertEqual(protection.endCount, 1)
        study.signOut()
        XCTAssertEqual(protection.endCount, 2)
    }

    func testRepeatedStartWhileCameraIsOpeningStartsOnlyOneSession() async {
        let opening = expectation(description: "Camera opening")
        let recorder = FakeStudyRecording(holdStart: true, onStart: { opening.fulfill() })
        let study = service(recorder)
        let first = Task { await study.start(task: "  Notes  ") }
        await fulfillment(of: [opening], timeout: 2)
        XCTAssertTrue(study.isStarting)
        await study.start(task: "Second tap")
        await recorder.releaseStart()
        await first.value
        let starts = await recorder.starts
        XCTAssertEqual(starts, 1)
        guard case .running(let active) = study.phase else { return XCTFail("Should be running") }
        XCTAssertEqual(active.task, "Notes")
        XCTAssertFalse(study.isStarting)
        study.signOut()
    }

    func testTaskMatchesTheAccountsLengthAndWhitespaceRules() async {
        let study = service(FakeStudyRecording())
        await study.start(task: "  Chapter\n4\t" + String(repeating: "x", count: 150))
        guard case .running(let active) = study.phase else { return XCTFail("Should be running") }
        XCTAssertTrue(active.task.hasPrefix("Chapter 4 "))
        XCTAssertEqual(active.task.count, StudyService.taskCharacterLimit)
        study.signOut()
    }

    func testRepeatedFinishDuringFileFinalizationCreditsOnlyOnce() async {
        let stopping = expectation(description: "Saving video")
        let recorder = FakeStudyRecording(holdStop: true, onStop: { stopping.fulfill() })
        let study = service(recorder)
        await study.start(task: "Notes")
        currentDate.addTimeInterval(900)
        let first = Task { await study.finish(hasPlus: true) }
        await fulfillment(of: [stopping], timeout: 2)
        XCTAssertTrue(study.isFinishing)
        await study.finish(hasPlus: true)
        await recorder.releaseStop()
        await first.value
        XCTAssertEqual(study.log.entries.count, 1)
        XCTAssertEqual(study.log.entries.first?.scrollSecondsEarned, 300)
        XCTAssertEqual(study.earnedTodaySeconds, 300)
        XCTAssertFalse(study.isFinishing)
    }

    func testSecondSessionStartsAndEarnsAfterReset() async {
        let recorder = FakeStudyRecording()
        let study = service(recorder)
        for _ in 0..<2 {
            await study.start(task: "Notes")
            currentDate.addTimeInterval(900)
            await study.finish(hasPlus: true)
            study.reset()
        }
        let starts = await recorder.starts
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(study.log.entries.count, 2)
        XCTAssertEqual(study.earnedTodaySeconds, 600)
    }

    func testBackgroundTimeDoesNotCountAndOnlySavedVideoEarns() async {
        let study = service(FakeStudyRecording(seconds: 600), verified: 540)
        await study.start(task: "Notes")
        currentDate.addTimeInterval(600)
        study.interrupt()
        currentDate.addTimeInterval(7_200)
        await study.finish(hasPlus: true)
        XCTAssertEqual(study.log.entries.first?.seconds, 600)
        XCTAssertEqual(study.log.entries.first?.recordedSeconds, 540)
        XCTAssertEqual(study.earnedTodaySeconds, 180)
    }

    func testRelaunchUsesCheckpointAndVerifiesRecoveredVideo() async throws {
        let active = StudyService.Active(task: "Recovered notes", startedAt: currentDate, recordingName: "recovery.mov",
                                         lastActiveAt: currentDate.addingTimeInterval(600))
        defaults.set(try JSONEncoder().encode(active), forKey: AccountScopedKey.make("mivo.study.active", account: email))
        currentDate.addTimeInterval(86_400)
        let study = service(FakeStudyRecording(seconds: 0), verified: 590)
        XCTAssertNotNil(study.interruptedAt)
        await study.finish(hasPlus: true)
        XCTAssertEqual(study.log.entries.first?.seconds, 600)
        XCTAssertEqual(study.log.entries.first?.recordedSeconds, 590)
    }

    func testUnavailableCameraStillLogsStudyWithoutCredit() async {
        let study = service(FakeStudyRecording(succeeds: false))
        await study.start(task: "Notes")
        XCTAssertTrue(study.cameraUnavailable)
        currentDate.addTimeInterval(900)
        await study.finish(hasPlus: true)
        XCTAssertEqual(study.log.entries.first?.seconds, 900)
        XCTAssertEqual(study.log.entries.first?.recordedSeconds, 0)
        XCTAssertEqual(study.earnedTodaySeconds, 0)
    }

    func testVideoVerificationRejectsMissingAndCorruptFiles() async throws {
        let absent = await StudyService.verifiedVideoSeconds(at: nil)
        XCTAssertEqual(absent, 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("study-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("This is not video".utf8).write(to: url)
        let corrupt = await StudyService.verifiedVideoSeconds(at: url)
        XCTAssertEqual(corrupt, 0)
    }

    func testUnplayableVideoCannotEarnScrollTime() async {
        let study = service(FakeStudyRecording(), verified: 0)
        await study.start(task: "Notes")
        currentDate.addTimeInterval(900)
        await study.finish(hasPlus: true)
        XCTAssertEqual(study.earnedTodaySeconds, 0)
    }

    func testBindingSameAccountDoesNotResetALiveSession() async {
        let study = service(FakeStudyRecording())
        await study.start(task: "Notes")
        let phase = study.phase
        study.bind()
        XCTAssertEqual(study.phase, phase)
        XCTAssertNil(study.interruptedAt)
        study.signOut()
    }

    func testAccountSwitchDuringFinishCannotCreditTheNextAccount() async {
        let stopping = expectation(description: "Saving video")
        let recorder = FakeStudyRecording(holdStop: true, onStop: { stopping.fulfill() })
        let study = service(recorder)
        await study.start(task: "Private notes")
        currentDate.addTimeInterval(900)
        let finishing = Task { await study.finish(hasPlus: true) }
        await fulfillment(of: [stopping], timeout: 2)
        email = "next@example.com"
        await recorder.releaseStop()
        study.bind()
        await finishing.value
        XCTAssertTrue(study.log.entries.isEmpty)
        XCTAssertEqual(study.earnedTodaySeconds, 0)
        XCTAssertEqual(study.phase, .idle)
    }

    func testSignOutWhileCameraIsOpeningCannotRestoreTheOldSession() async {
        let opening = expectation(description: "Camera opening")
        let recorder = FakeStudyRecording(holdStart: true, onStart: { opening.fulfill() })
        let study = service(recorder)
        let starting = Task { await study.start(task: "Private notes") }
        await fulfillment(of: [opening], timeout: 2)
        study.signOut()
        email = "next@example.com"
        study.bind()
        await recorder.releaseStart()
        await starting.value
        XCTAssertEqual(study.phase, .idle)
        XCTAssertFalse(study.isStarting)
        XCTAssertTrue(study.log.entries.isEmpty)
    }

    func testAnExpiredTrialLogsTheSessionWithoutCreditingIt() async throws {
        let first = currentDate.addingTimeInterval(-8 * 86_400)
        let entry = StudyEntry(task: "Last week", startedAt: first, endedAt: first.addingTimeInterval(600),
                               recordedSeconds: 600, scrollSecondsEarned: 200)
        defaults.set(try JSONEncoder().encode(StudyLog(entries: [entry])),
                     forKey: AccountScopedKey.make("mivo.study.log", account: email))
        let study = service(FakeStudyRecording())
        await study.start(task: "Notes")
        currentDate.addTimeInterval(900)
        await study.finish(hasPlus: false)
        XCTAssertEqual(study.earnedTodaySeconds, 0)
        guard case .finished(let receipt) = study.phase else { return XCTFail("Missing receipt") }
        XCTAssertEqual(receipt.lockedScrollSeconds, 300)
        XCTAssertEqual(receipt.entry.recordedSeconds, 900)
    }

    func testFinishingDuringAnExistingSyncQueuesAnotherSave() async {
        let pulling = expectation(description: "Initial sync in flight")
        let saved = expectation(description: "New receipt uploaded")
        let backend = FakeStudyBackend()
        var resumePull: CheckedContinuation<Void, Never>?
        backend.beforePull = {
            backend.beforePull = nil
            await withCheckedContinuation {
                resumePull = $0
                pulling.fulfill()
            }
        }
        backend.onPush = { saved.fulfill() }
        let study = StudyService(
            defaults: defaults,
            balanceStore: ReelBalanceStore(defaults: defaults, now: { [self] in currentDate }, account: { [self] in email }),
            backend: backend,
            recording: FakeStudyRecording(),
            now: { [self] in currentDate },
            verifyVideo: { _ in 900 },
            account: { [self] in email }
        )
        let firstSync = Task { await study.syncNow() }
        await fulfillment(of: [pulling], timeout: 2)
        await study.start(task: "Notes")
        currentDate.addTimeInterval(900)
        await study.finish(hasPlus: true)
        // This also covers the receipt's background sync request arriving during a pull.
        await study.syncNow()
        resumePull?.resume()
        await firstSync.value
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertEqual(backend.pushed.flatMap { $0 }.count, 1)
    }

    func testTheDailyCapStillAppliesAcrossStudySessions() async {
        let study = service(FakeStudyRecording(seconds: 10_800), verified: 10_800)
        for _ in 0..<2 {
            await study.start(task: "Long study")
            currentDate.addTimeInterval(10_800)
            await study.finish(hasPlus: true)
            study.reset()
        }
        XCTAssertEqual(study.earnedTodaySeconds, ReelBalance.dailyEarnCapSeconds)
        XCTAssertEqual(study.log.entries.last?.scrollSecondsEarned, 0)
    }

    func testSignOutRemovesPersistedActiveSession() async {
        let study = service(FakeStudyRecording())
        await study.start(task: "Notes")
        study.signOut()
        XCTAssertNil(defaults.data(forKey: AccountScopedKey.make("mivo.study.active", account: email)))
        study.bind()
        XCTAssertEqual(study.phase, .idle)
    }
}
