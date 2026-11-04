import AVFoundation
import Combine
import SwiftUI
import UIKit
#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

/// Separate from intervention and Lock-in shields; ending study only releases study's own choices.
@MainActor
protocol StudyFocusProtecting: AnyObject {
    func begin(selection: Data?, endsAt: Date) -> String?
    func end()
}

@MainActor
final class StudyFocusProtection: StudyFocusProtecting {
    func begin(selection data: Data?, endsAt: Date) -> String? {
        guard let data else { return nil }
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return "Choose your distraction apps again before starting."
        }
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty else { return nil }
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            return "Allow Screen Time access to pause distractions, or remove that selection."
        }
        guard let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup) else {
            return "Distraction protection isn't available. Remove the selection to study without it."
        }
        end()
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: endsAt),
            intervalEnd: calendar.dateComponents(fields, from: endsAt.addingTimeInterval(15 * 60)),
            repeats: false
        )
        defaults.set(endsAt.timeIntervalSince1970, forKey: MivoScreenTimeKeys.studyFocusEndsAt)
        defaults.synchronize()
        do {
            try DeviceActivityCenter().startMonitoring(DeviceActivityName(MivoScreenTimeKeys.studyFocusEndActivity), during: schedule)
        } catch {
            end()
            return "Couldn't schedule distraction protection. Try again or study without a distraction selection."
        }
        let store = ManagedSettingsStore(named: .init(MivoScreenTimeKeys.studyFocusStore))
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        return nil
        #else
        return "Screen Time protection isn't available here. Remove the distraction selection to continue."
        #endif
    }

    func end() {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        ManagedSettingsStore(named: .init(MivoScreenTimeKeys.studyFocusStore)).clearAllSettings()
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(MivoScreenTimeKeys.studyFocusEndActivity)])
        UserDefaults(suiteName: MivoScreenTimeKeys.appGroup)?.removeObject(forKey: MivoScreenTimeKeys.studyFocusEndsAt)
        #endif
    }
}

/// Injectable capture boundary; the service can exercise lifecycle races without a camera.
protocol StudyRecording: AnyObject {
    func start(to url: URL) async -> Bool
    func stop() async -> Double
}

/// Video only, kept on this phone. All capture state belongs to the serial queue.
final class StudyRecorder: NSObject, ObservableObject, StudyRecording, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published private(set) var isRecording = false
    @Published private(set) var wasCutShort = false

    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "app.mivo.study.recorder", qos: .userInitiated)
    private var stopRequested = false
    private var recordedSeconds: Double?
    private var currentURL: URL?
    private var startWaiter: CheckedContinuation<Bool, Never>?
    private var finishWaiters: [CheckedContinuation<Double, Never>] = []

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Completes when capture actually starts, rather than when it is merely requested.
    func start(to url: URL) async -> Bool {
        guard await Self.authorize() else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard currentURL == nil else {
                    continuation.resume(returning: false)
                    return
                }
                // Reuse the configured input/output across successive study sessions.
                if session.inputs.isEmpty {
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: camera) else {
                        continuation.resume(returning: false)
                        return
                    }
                    session.beginConfiguration()
                    if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
                    let usable = session.canAddInput(input) && session.canAddOutput(output)
                    if usable {
                        session.addInput(input)
                        session.addOutput(output)
                        // Keep long recordings recoverable if the process is interrupted.
                        output.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
                    }
                    session.commitConfiguration()
                    guard usable else {
                        continuation.resume(returning: false)
                        return
                    }
                }
                stopRequested = false
                recordedSeconds = nil
                currentURL = url
                startWaiter = continuation
                DispatchQueue.main.async { self.wasCutShort = false }
                session.startRunning()
                guard session.isRunning else {
                    currentURL = nil
                    startWaiter = nil
                    continuation.resume(returning: false)
                    return
                }
                output.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stop() async -> Double {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopRequested = true
                if let seconds = recordedSeconds {
                    continuation.resume(returning: seconds)
                } else if currentURL == nil {
                    continuation.resume(returning: 0)
                } else {
                    finishWaiters.append(continuation)
                    // A stop during startup waits for didStart, then stops there.
                    if output.isRecording { output.stopRecording() }
                }
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { [self] in
            guard currentURL == fileURL else { return }
            startWaiter?.resume(returning: true)
            startWaiter = nil
            DispatchQueue.main.async { self.isRecording = true }
            if stopRequested { self.output.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let wroteFile = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        let duration = output.recordedDuration.seconds
        let seconds = wroteFile && duration.isFinite ? max(0, duration) : 0
        queue.async { [self] in
            guard currentURL == outputFileURL else { return }
            let cutShort = !stopRequested
            recordedSeconds = seconds
            currentURL = nil
            session.stopRunning()
            startWaiter?.resume(returning: false)
            startWaiter = nil
            let waiters = finishWaiters
            finishWaiters.removeAll()
            waiters.forEach { $0.resume(returning: seconds) }
            DispatchQueue.main.async {
                self.isRecording = false
                self.wasCutShort = cutShort
            }
        }
    }
}

// MARK: - The account side

/// Why a call to the account failed, in the terms the study flow cares about.
enum StudyBackendFailure: Equatable {
    case offline
    case signedOut
    /// The account service does not have the study functions yet.
    case notReady
    case failed

    static func classify(_ error: Error) -> StudyBackendFailure {
        if let backend = error as? MivoBackendError {
            switch backend {
            case .unavailable: return .offline
            case .authenticationRequired: return .signedOut
            case .server(let message):
                let lowered = message.lowercased()
                if lowered.contains("could not find the function") || lowered.contains("schema cache") { return .notReady }
                if lowered.contains("jwt") || lowered.contains("authentication_required") { return .signedOut }
                return .failed
            }
        }
        return error is URLError ? .offline : .failed
    }
}

/// Everything the study flow asks the account: saving sessions, reading them back, and the study
/// room. `StudyService` only talks to this, so the rules can be exercised without a network.
protocol StudyBackend: AnyObject {
    func push(_ entries: [StudyEntry]) async throws
    func pull(since: Date) async throws -> [RemoteStudySession]
    func room() async throws -> StudyRoomState
    func ensureRoom() async throws -> StudyRoomState
    func updateRoom(displayName: String?, isOpen: Bool?, showTask: Bool?) async throws -> StudyRoomState
    func rotateRoomLink() async throws -> StudyRoomState
    func removeVisitor(_ id: UUID) async throws -> StudyRoomState
    func ping(task: String, startedAt: Date) async throws -> StudyRoomState
    func endLive() async throws -> StudyRoomState
}

final class BackendStudyBackend: StudyBackend {
    func push(_ entries: [StudyEntry]) async throws { try await MivoBackendService.syncStudySessions(entries) }
    func pull(since: Date) async throws -> [RemoteStudySession] { try await MivoBackendService.myStudySessions(since: since) }
    func room() async throws -> StudyRoomState { try await MivoBackendService.myStudyRoom() }
    func ensureRoom() async throws -> StudyRoomState { try await MivoBackendService.ensureStudyRoom() }
    func updateRoom(displayName: String?, isOpen: Bool?, showTask: Bool?) async throws -> StudyRoomState {
        try await MivoBackendService.updateStudyRoom(displayName: displayName, isOpen: isOpen, showTask: showTask)
    }
    func rotateRoomLink() async throws -> StudyRoomState { try await MivoBackendService.rotateStudyRoomCode() }
    func removeVisitor(_ id: UUID) async throws -> StudyRoomState { try await MivoBackendService.removeStudyRoomVisitor(id: id) }
    func ping(task: String, startedAt: Date) async throws -> StudyRoomState {
        try await MivoBackendService.studyRoomPing(task: task, startedAt: startedAt)
    }
    func endLive() async throws -> StudyRoomState { try await MivoBackendService.studyRoomEnd() }
}

/// The study flow's state: one thing at a time, timed, filmed, and turned into
/// a receipt, a streak and scroll time. The video and the scroll balance stay on
/// this phone, kept apart per signed-in account; signed in, the task and the
/// times of each session are also saved to the account so the website shows the
/// same streak, and the person's study room can show they are studying.
@MainActor
final class StudyService: ObservableObject {
    static let shared = StudyService()

    /// Scroll time is earned from video, so a session that was not recorded
    /// still counts for the streak but earns none.
    static let requiresRecording = true
    static let taskCharacterLimit = 120
    /// Recordings are kept this long, then deleted.
    nonisolated static let keepRecordingsDays = 7

    private static let logKey = "mivo.study.log"
    private static let activeKey = "mivo.study.active"
    private static let syncedKey = "mivo.study.synced"

    /// How far back sessions are read from the account.
    static let syncWindowDays = 120
    private static let pushChunk = 50
    private static let heartbeatSeconds: UInt64 = 30

    struct Active: Codable, Equatable {
        var task: String
        var startedAt: Date
        var recordingName: String
        var lastActiveAt: Date? = nil
        var plan: PhoneStudyPlan? = nil
    }

    struct Receipt: Equatable {
        var entry: StudyEntry
        var streak: Int
        var capReached: Bool
        /// Wrapper seconds the session would have earned but the free week is over.
        var lockedScrollSeconds = 0
    }

    enum Phase: Equatable {
        case idle
        case running(Active)
        case finished(Receipt)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var log = StudyLog()
    @Published private(set) var cameraUnavailable = false
    @Published var showRequested = false
    /// What to fill in when the study screen next opens; set by the way back
    /// to studying from a social app (`AppWrapperView`), used once.
    @Published var suggestedTask: String?
    @Published private(set) var isStarting = false
    @Published private(set) var startMessage: String?
    @Published private(set) var isFinishing = false
    @Published private(set) var interruptedAt: Date?

    /// The person's study room. Nil until it has been asked for; `.none` when they have none.
    @Published private(set) var room: StudyRoomState?
    /// False once the account service turns out not to have rooms yet.
    @Published private(set) var roomAvailable = true
    @Published private(set) var roomBusy = false
    @Published var roomMessage: String?

    /// Renews the sign-in so a call that was refused can be tried again. Set by the screen
    /// that holds the app's account.
    var refreshSession: (() async throws -> Void)?

    let recorder = StudyRecorder()
    private let recording: StudyRecording
    private let protection: StudyFocusProtecting
    private let now: () -> Date
    private let verifyVideo: (URL?) async -> Int
    private var boundAccount: String?
    private var hasBound = false
    private var generation = UUID()
    private var checkpoint: Task<Void, Never>?
    private var recoveredSession = false
    private var recorderObservation: AnyCancellable?
    private let defaults: UserDefaults
    private let balanceStore: ReelBalanceStore
    private let account: () -> String?
    private let backend: StudyBackend
    private let linkedBackend: LinkedStudyBackend
    @Published private(set) var linkedSession: LinkedStudySession?
    @Published private(set) var linkedMessage: String?
    @Published private(set) var linkedBusy = false
    @Published private(set) var linkedEarnedSeconds = 0
    private var linkedRefreshing = false
    private var linkedRevision = 0
    private var syncedIDs: Set<UUID> = []
    private var isSyncing = false
    private var syncAgain = false
    private var presenceEnd: Task<Void, Never>?
    private var startupInterrupted = false
    private var pendingStart: Task<Bool, Never>?
    private var captureCleanup: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var roomRevision = 0

    init(
        defaults: UserDefaults = .standard,
        balanceStore: ReelBalanceStore = .shared,
        backend: StudyBackend = BackendStudyBackend(),
        linkedBackend: LinkedStudyBackend = BackendLinkedStudyBackend(),
        recording: StudyRecording? = nil,
        protection: StudyFocusProtecting? = nil,
        now: @escaping () -> Date = Date.init,
        verifyVideo: @escaping (URL?) async -> Int = StudyService.verifiedVideoSeconds,
        account: @escaping () -> String? = { StorageService.activeUserEmail }
    ) {
        self.defaults = defaults
        self.balanceStore = balanceStore
        self.backend = backend
        self.linkedBackend = linkedBackend
        self.recording = recording ?? recorder
        self.protection = protection ?? StudyFocusProtection()
        self.now = now
        self.verifyVideo = verifyVideo
        self.account = account
        bind()
        recorderObservation = recorder.$wasCutShort
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.cameraUnavailable, self.phase.isRunning else { return }
                self.interrupt()
            }
        Task.detached(priority: .utility) { Self.pruneOldRecordings() }
    }

    var savedPlan: PhoneStudyPlan {
        defaults.data(forKey: key("mivo.study.setup")).flatMap { try? JSONDecoder().decode(PhoneStudyPlan.self, from: $0) } ?? PhoneStudyPlan()
    }

    var streak: Int { log.streak(asOf: now()) }
    var studiedTodaySeconds: Int { log.seconds(on: now()) }
    var earnedTodaySeconds: Int { balanceStore.current().bonusSeconds }
    var trialPhase: StudyTrial.Phase { StudyTrial.phase(firstSessionAt: log.firstSessionAt, now: now()) }

    private func key(_ base: String) -> String { AccountScopedKey.make(base, account: boundAccount) }

    // MARK: - Account

    /// Loads the signed-in account's log and any session it left running.
    /// Called whenever the account may have changed.
    func bind() {
        let owner = account()
        guard !hasBound || boundAccount != owner else { return }
        if hasBound { signOut() }
        hasBound = true
        boundAccount = owner
        generation = UUID()
        roomAvailable = true
        log = defaults.data(forKey: key(Self.logKey)).flatMap { try? JSONDecoder().decode(StudyLog.self, from: $0) } ?? StudyLog()
        if let data = defaults.data(forKey: key(Self.activeKey)),
           let active = try? JSONDecoder().decode(Active.self, from: data) {
            phase = .running(active)
            recoveredSession = true
            protection.end()
            // Never count hours while the app was terminated as study time.
            interruptedAt = active.lastActiveAt ?? active.startedAt
        } else {
            phase = .idle
        }
        linkedSession = nil
        linkedMessage = nil
        linkedEarnedSeconds = 0
        cameraUnavailable = false
        syncedIDs = Set((defaults.stringArray(forKey: key(Self.syncedKey)) ?? []).compactMap(UUID.init(uuidString:)))
        room = nil
        roomMessage = nil
        stopHeartbeat()
    }

    /// Signing out ends a running session without crediting it; the account's
    /// log and balance stay saved for next time.
    func signOut() {
        protection.end()
        startMessage = nil
        generation = UUID()
        linkedRevision += 1
        linkedSession = nil
        linkedMessage = nil
        linkedBusy = false
        linkedEarnedSeconds = 0
        hasBound = false
        defaults.removeObject(forKey: AccountScopedKey.make(Self.activeKey, account: boundAccount))
        if isStarting || isFinishing || phase.isRunning {
            let recording = recording
            let start = pendingStart
            let previousCleanup = captureCleanup
            captureCleanup = Task {
                await previousCleanup?.value
                _ = await start?.value
                _ = await recording.stop()
            }
        }
        checkpoint?.cancel()
        checkpoint = nil
        stopHeartbeat()
        // The server expires presence after two minutes. Do not dispatch an account call
        // after sign-out: its credentials may already belong to the next person.
        UIApplication.shared.isIdleTimerDisabled = false
        showRequested = false
        phase = .idle
        log = StudyLog()
        syncedIDs = []
        room = nil
        roomMessage = nil
        roomBusy = false
        interruptedAt = nil
        isStarting = false
        isFinishing = false
        recoveredSession = false
    }

    /// Deleting the account removes its log, its balance and its recordings.
    func eraseAllData() {
        bind()
        signOut()
        defaults.removeObject(forKey: key(Self.logKey))
        defaults.removeObject(forKey: key(Self.activeKey))
        defaults.removeObject(forKey: key(Self.syncedKey))
        defaults.removeObject(forKey: key("mivo.study.setup"))
        balanceStore.erase()
        if let directory = Self.recordingsDirectory(account: account()) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Start and finish

    func start(task: String, plan: PhoneStudyPlan? = nil) async {
        bind()
        let cleaned = task.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ")
        let task = String(cleaned.prefix(Self.taskCharacterLimit))
        guard !task.isEmpty, !isStarting, !isFinishing, !linkedBusy, linkedSession == nil, case .idle = phase else { return }
        isStarting = true
        startMessage = nil
        startupInterrupted = false
        let token = generation
        let owner = account()
        defer { if generation == token { isStarting = false } }
        await captureCleanup?.value
        guard generation == token, account() == owner, !Task.isCancelled else { return }
        let name = "\(UUID().uuidString).mov"
        let captured: Bool
        let captureURL = Self.recordingURL(name, account: owner)
        if let url = captureURL {
            let recording = recording
            let operation = Task { await recording.start(to: url) }
            pendingStart = operation
            captured = await operation.value
        } else {
            captured = false
        }
        guard generation == token else { return } // signOut owns capture cleanup.
        pendingStart = nil
        guard account() == owner, !Task.isCancelled else {
            protection.end()
            _ = await recording.stop()
            return
        }
        let startedAt = now()
        if let message = protection.begin(selection: plan?.hasDistractions == true ? plan?.distractionSelection : nil,
                                          endsAt: startedAt.addingTimeInterval(TimeInterval(plan?.goalSeconds ?? 25 * 60))) {
            _ = await recording.stop()
            if let captureURL { try? FileManager.default.removeItem(at: captureURL) }
            if generation == token { startMessage = message }
            return
        }
        cameraUnavailable = !captured
        interruptedAt = nil
        recoveredSession = false
        let active = Active(task: task, startedAt: startedAt, recordingName: name, plan: plan)
        if let plan, let data = try? JSONEncoder().encode(plan) { defaults.set(data, forKey: key("mivo.study.setup")) }
        UIApplication.shared.isIdleTimerDisabled = true
        saveActive(active)
        phase = .running(active)
        startCheckpoint()
        startHeartbeat(for: active)
        if startupInterrupted || (captured && recorder.wasCutShort) { interrupt() }
    }

    private func saveActive(_ active: Active) {
        if let data = try? JSONEncoder().encode(active) { defaults.set(data, forKey: key(Self.activeKey)) }
    }

    private func startCheckpoint() {
        checkpoint?.cancel()
        checkpoint = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self, self.account() == self.boundAccount,
                      case .running(var active) = self.phase, self.interruptedAt == nil else { return }
                active.lastActiveAt = self.now()
                if let plan = active.plan, plan.hasDistractions,
                   self.now().timeIntervalSince(active.startedAt) >= Double(plan.goalSeconds) { self.protection.end() }
                self.saveActive(active)
            }
        }
    }

    /// Freeze the timer and preserve the captured portion when leaving the app.
    func interrupt() {
        if isStarting { startupInterrupted = true }
        guard case .running(var active) = phase, interruptedAt == nil, !isFinishing else { return }
        protection.end()
        interruptedAt = now()
        active.lastActiveAt = interruptedAt
        saveActive(active)
        checkpoint?.cancel()
        endPresence()
        UIApplication.shared.isIdleTimerDisabled = false
        let recording = recording
        Task { _ = await recording.stop() }
    }

    /// A session earns scroll time when it began inside the free week or the
    /// person has Plus. Otherwise it is logged in full and the scroll time it
    /// would have earned is shown on the receipt, not added.
    func finish(hasPlus: Bool) async {
        guard !isFinishing, case .running(let active) = phase else { return }
        isFinishing = true
        protection.end()
        let token = generation
        let owner = account()
        defer { if generation == token { isFinishing = false } }
        checkpoint?.cancel()
        endPresence()
        let endedAt = max(active.startedAt, interruptedAt ?? now())
        let recorderSeconds = cameraUnavailable ? 0 : await recording.stop()
        guard generation == token, account() == owner else { return }
        UIApplication.shared.isIdleTimerDisabled = false

        // Scroll time rests on the saved video, not on the recorder's say-so:
        // the file has to exist and play, and its length caps what is credited.
        let fileSeconds = cameraUnavailable ? 0 : await verifyVideo(Self.recordingURL(active.recordingName, account: account()))
        guard generation == token, account() == owner else { return }
        let elapsed = max(0, Int(endedAt.timeIntervalSince(active.startedAt)))
        let safeRecorderSeconds = recorderSeconds.isFinite ? Int(max(0, recorderSeconds)) : 0
        let recorded = max(0, min(elapsed, recoveredSession ? fileSeconds : safeRecorderSeconds, fileSeconds))
        let creditable = Self.requiresRecording ? recorded : elapsed

        let trial = StudyTrial.phase(firstSessionAt: log.firstSessionAt ?? active.startedAt, now: active.startedAt)
        var balance = balanceStore.current()
        let before = balance.bonusSeconds
        var earned = 0
        var locked = 0
        if StudyTrial.earnsScroll(trial, hasPlus: hasPlus) {
            earned = balance.creditStudy(seconds: creditable)
            balanceStore.save(balance)
        } else {
            var preview = balance
            locked = preview.creditStudy(seconds: creditable)
        }

        let entry = StudyEntry(
            task: active.task, startedAt: active.startedAt, endedAt: endedAt,
            recordedSeconds: recorded, scrollSecondsEarned: earned, plan: active.plan
        )
        log.entries.append(entry)
        persistLog()
        defaults.removeObject(forKey: key(Self.activeKey))
        stopHeartbeat()

        let capReached = before + earned >= ReelBalance.dailyEarnCapSeconds
        phase = .finished(Receipt(entry: entry, streak: streak, capReached: capReached, lockedScrollSeconds: locked))

        // The receipt does not wait on the network: the session is saved to the account, and the
        // room told it is over, in the background.
        Task { [weak self] in await self?.afterFinish(generation: token) }
    }

    private func persistLog() {
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: key(Self.logKey)) }
    }

    func reset() {
        if case .finished = phase {
            phase = .idle
            interruptedAt = nil
            recoveredSession = false
        }
    }

    // MARK: - Linked computer study

    private var linkedDeviceID: UUID {
        let key = "mivo.study.phoneInstallation"
        if let value = defaults.string(forKey: key), let id = UUID(uuidString: value) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    func startLinked(task: String) async {
        bind()
        let cleaned = String(task.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ").prefix(Self.taskCharacterLimit))
        guard account() != nil, !cleaned.isEmpty, !isStarting, !linkedBusy,
              linkedSession == nil, case .idle = phase else { return }
        linkedBusy = true
        linkedMessage = nil
        linkedRevision += 1
        let token = generation
        defer { if generation == token { linkedBusy = false } }
        // Keep the request ID on an ambiguous network failure. A retry reuses it.
        let requestKey = key("mivo.study.linkedRequest")
        let id = defaults.string(forKey: requestKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(id.uuidString, forKey: requestKey)
        do {
            let session = try await authorized { try await linkedBackend.create(id: id, task: cleaned) }
            guard generation == token, account() == boundAccount else { return }
            linkedSession = session
            linkedEarnedSeconds = 0
            defaults.removeObject(forKey: requestKey)
        } catch {
            guard generation == token else { return }
            linkedMessage = linkedFailureMessage(error)
        }
    }

    /// Called while the app is in front. Desktop monitoring continues with the phone closed.
    func refreshLinked(hasPlus: Bool) async {
        bind()
        guard account() != nil, !linkedBusy, !isStarting, !isFinishing,
              !linkedRefreshing, case .idle = phase else { return }
        linkedRefreshing = true
        let token = generation
        let revision = linkedRevision
        defer { linkedRefreshing = false }
        do {
            let session = try await authorized { try await linkedBackend.current() }
            guard generation == token, revision == linkedRevision, !linkedBusy, !isStarting,
                  case .idle = phase else { return }
            // A completed receipt remains visible until Done. Old receipts aren't reopened.
            if let session, !session.isFinished || linkedSession?.id == session.id {
                linkedSession = session
            } else if linkedSession?.isFinished != true {
                linkedSession = nil
            }
            linkedMessage = nil
            if session?.isFinished == true { await syncNow() }
            guard generation == token else { return }
            let grants = try await authorized {
                try await linkedBackend.rewards(deviceID: linkedDeviceID, hasPlus: hasPlus, timeZone: TimeZone.current.identifier)
            }
            guard generation == token else { return }
            var balance = balanceStore.current()
            for grant in grants { balance.creditLinkedStudy(grant) }
            // The balance and redemption IDs are one durable value, even if the app exits now.
            balanceStore.save(balance)
            for index in log.entries.indices where log.entries[index].origin == .desktop {
                if let earned = balance.linkedStudyCreditAmounts?[log.entries[index].id] {
                    log.entries[index].scrollSecondsEarned = earned
                }
            }
            if let id = linkedSession?.id {
                linkedEarnedSeconds = balance.linkedStudyCreditAmounts?[id] ?? 0
            }
            persistLog()
        } catch {
            guard generation == token, revision == linkedRevision else { return }
            // Keep the session, but make transport failure explicit; never imply live tracking.
            linkedMessage = linkedFailureMessage(error)
        }
    }

    func finishLinked(hasPlus: Bool) async {
        guard let active = linkedSession, !linkedBusy, !active.isFinished else { return }
        linkedBusy = true
        linkedRevision += 1
        let token = generation
        do {
            let session = try await authorized { try await linkedBackend.finish(id: active.id) }
            guard generation == token else { return }
            linkedSession = session
            linkedMessage = nil
        } catch {
            guard generation == token else { return }
            linkedMessage = linkedFailureMessage(error)
        }
        guard generation == token else { return }
        linkedBusy = false
        await refreshLinked(hasPlus: hasPlus)
    }

    func dismissLinkedReceipt() {
        guard linkedSession?.isFinished == true else { return }
        linkedRevision += 1
        linkedSession = nil
        linkedEarnedSeconds = 0
        linkedMessage = nil
    }

    private func linkedFailureMessage(_ error: Error) -> String {
        switch StudyBackendFailure.classify(error) {
        case .notReady: return "Computer study isn't available on your account yet. Try again after the service is updated."
        case .signedOut: return "Sign in again to connect computer study."
        case .offline: return "Can't reach Mivo. Reconnect to see the latest session status."
        case .failed: return "Couldn't sync computer study. Try again."
        }
    }

    // MARK: - Account sync

    /// Runs a call, and once more after renewing the sign-in if it was refused for that.
    private func authorized<T>(_ call: () async throws -> T) async throws -> T {
        let token = generation
        let owner = boundAccount
        do {
            guard hasBound, account() == owner, !Task.isCancelled else { throw CancellationError() }
            return try await call()
        } catch {
            guard generation == token, account() == owner, !Task.isCancelled,
                  StudyBackendFailure.classify(error) == .signedOut, let refreshSession else { throw error }
            try await refreshSession()
            guard generation == token, account() == owner, !Task.isCancelled else { throw CancellationError() }
            return try await call()
        }
    }

    /// Saves this phone's sessions to the account, reads the account's back in, and refreshes the
    /// study room. Quiet by design: with no connection, or no account service yet, it does nothing
    /// and tries again next time. Safe to call often.
    func syncNow() async {
        bind()
        guard let owner = account() else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        let token = generation
        isSyncing = true
        defer {
            isSyncing = false
            if syncAgain {
                syncAgain = false
                Task { [weak self] in await self?.syncNow() }
            }
        }

        do {
            let pending = log.unsynced(alreadySynced: syncedIDs)
            for start in stride(from: 0, to: pending.count, by: Self.pushChunk) {
                let chunk = Array(pending[start..<min(start + Self.pushChunk, pending.count)])
                try await authorized { try await backend.push(chunk) }
                guard account() == owner, generation == token else { return }
                syncedIDs.formUnion(chunk.map(\.id))
                defaults.set(syncedIDs.map(\.uuidString), forKey: key(Self.syncedKey))
            }

            let since = Date().addingTimeInterval(-Double(Self.syncWindowDays) * 86_400)
            let remote = try await authorized { try await backend.pull(since: since) }
            guard account() == owner, generation == token else { return }
            // The account answers with at most 500 sessions, newest first. If it was full, it only
            // spoke for the stretch back to its oldest one.
            let windowStart = remote.count >= 500 ? (remote.map(\.startedAt).min() ?? since) : since
            var merged = log
            merged.merge(remote: remote, windowStart: windowStart)
            if merged != log {
                log = merged
                persistLog()
            }
        } catch {
            guard generation == token else { return }
            if StudyBackendFailure.classify(error) == .notReady { roomAvailable = false }
            return
        }
        await refreshRoom()
    }

    private func afterFinish(generation token: UUID) async {
        guard generation == token else { return }
        await syncNow()
    }

    /// Serialize the final presence update before any new session's first heartbeat.
    private func endPresence() {
        let previousHeartbeat = heartbeat
        stopHeartbeat()
        guard account() != nil else { return }
        let previousEnd = presenceEnd
        let token = generation
        presenceEnd = Task { [weak self] in
            await previousHeartbeat?.value
            await previousEnd?.value
            guard let self, self.generation == token else { return }
            _ = try? await self.authorized { try await self.backend.endLive() }
        }
    }

    // MARK: - Study room

    func refreshRoom() async {
        bind()
        guard roomAvailable, let owner = account() else { return }
        let token = generation
        let revision = roomRevision
        do {
            let state = try await authorized { try await backend.room() }
            guard account() == owner, generation == token, roomRevision == revision, !roomBusy else { return }
            room = state
            if case .running(let active) = phase, interruptedAt == nil { startHeartbeat(for: active) }
        } catch {
            guard generation == token else { return }
            noteRoomFailure(error, quiet: true)
        }
    }

    /// Opens or closes the room, making it first if the person has none.
    func setRoomOpen(_ open: Bool) async {
        await performRoom { [backend] in
            _ = try await backend.ensureRoom()
            return try await backend.updateRoom(displayName: nil, isOpen: open, showTask: nil)
        }
    }

    func setRoomShowsTask(_ show: Bool) async {
        await performRoom { [backend] in try await backend.updateRoom(displayName: nil, isOpen: nil, showTask: show) }
    }

    /// A new link. The old one stops working and everyone sitting is sent away.
    func rotateRoomLink() async {
        await performRoom { [backend] in try await backend.rotateRoomLink() }
    }

    func removeVisitor(_ id: UUID) async {
        await performRoom { [backend] in try await backend.removeVisitor(id) }
    }

    private func performRoom(_ action: () async throws -> StudyRoomState) async {
        guard !roomBusy, let owner = account() else { return }
        let token = generation
        roomRevision += 1
        roomBusy = true
        roomMessage = nil
        defer { if generation == token { roomBusy = false } }
        do {
            let state = try await authorized(action)
            guard account() == owner, generation == token else { return }
            room = state
            if case .running(let active) = phase, interruptedAt == nil { startHeartbeat(for: active) }
        } catch {
            guard generation == token else { return }
            noteRoomFailure(error, quiet: false)
        }
    }

    private func noteRoomFailure(_ error: Error, quiet: Bool) {
        switch StudyBackendFailure.classify(error) {
        case .notReady: roomAvailable = false
        case .offline: if !quiet { roomMessage = "Mivo couldn't reach the internet. Try again when you're online." }
        case .signedOut: if !quiet { roomMessage = "Sign in again to use your study room." }
        case .failed: if !quiet { roomMessage = "Something went wrong. Try again." }
        }
    }

    /// While a session runs, tells the room every 30 seconds that the person is still at it. The
    /// room reads two quiet minutes as "not studying", so a phone that dies never leaves it live.
    /// Nothing is sent for a person who has no room.
    private func startHeartbeat(for active: Active) {
        let previousHeartbeat = heartbeat
        previousHeartbeat?.cancel()
        guard account() != nil, roomAvailable else { return }
        let token = generation
        let previousEnd = presenceEnd
        heartbeat = Task { [weak self] in
            await previousHeartbeat?.value
            await previousEnd?.value
            while !Task.isCancelled {
                guard let self, self.generation == token, self.interruptedAt == nil,
                      case .running(let current) = self.phase, current == active else { return }
                if self.room?.hasRoom == false || self.room?.isOpen == false { return }
                let owner = self.account()
                let revision = self.roomRevision
                do {
                    let state = try await self.authorized { try await self.backend.ping(task: active.task, startedAt: active.startedAt) }
                    guard self.account() == owner, self.generation == token, !Task.isCancelled else { return }
                    if self.roomRevision == revision, !self.roomBusy { self.room = state }
                    if !state.hasRoom { return }
                } catch {
                    guard self.generation == token, !Task.isCancelled else { return }
                    if StudyBackendFailure.classify(error) == .notReady {
                        self.noteRoomFailure(error, quiet: true)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: Self.heartbeatSeconds * 1_000_000_000)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Recordings

    /// Seconds of playable video in the file, or 0 when it is missing, empty
    /// or has no video track.
    nonisolated static func verifiedVideoSeconds(at url: URL?) async -> Int {
        guard let url,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0 else { return 0 }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric,
              (try? await asset.load(.isPlayable)) == true,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return 0 }
        return max(0, Int(duration.seconds))
    }

    nonisolated private static func recordingsRoot() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Study", isDirectory: true)
    }

    /// One folder per account, so recordings never mix across accounts.
    private static func recordingsDirectory(account: String?) -> URL? {
        let id = AccountScopedKey.make("", account: account)
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return recordingsRoot()?.appendingPathComponent(id.isEmpty ? "device" : id, isDirectory: true)
    }

    private static func recordingURL(_ name: String, account: String?) -> URL? {
        guard let directory = recordingsDirectory(account: account) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    nonisolated private static func pruneOldRecordings() {
        guard let root = Self.recordingsRoot(),
              let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.keepRecordingsDays) * 86_400)
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            if (values.creationDate ?? Date()) < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}

extension StudyService.Phase {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
