import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Records a study session on the back camera: video only, written to this
/// phone and never uploaded. iOS stops capture when the app leaves the screen,
/// so the recorder reports how much video actually exists; that, not the
/// clock, is what earns scroll time.
final class StudyRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published private(set) var isRecording = false
    /// Capture stopped before the person finished (app left the screen, a call).
    @Published private(set) var wasCutShort = false

    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "app.mivo.study.recorder")
    private var stopRequested = false
    private var recordedSeconds: Double?
    private var finishWaiters: [CheckedContinuation<Double, Never>] = []

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Starts recording to `url`. False when there is no usable camera.
    func start(to url: URL) async -> Bool {
        stopRequested = false
        recordedSeconds = nil
        await MainActor.run { wasCutShort = false }
        let started: Bool = await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let camera = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: camera) else {
                    continuation.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .medium
                if session.canAddInput(input) { session.addInput(input) }
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                guard session.inputs.count == 1, session.outputs.count == 1 else {
                    continuation.resume(returning: false)
                    return
                }
                session.startRunning()
                output.startRecording(to: url, recordingDelegate: self)
                continuation.resume(returning: true)
            }
        }
        return started
    }

    /// Stops and returns the seconds of video that were written.
    func stop() async -> Double {
        stopRequested = true
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let seconds = recordedSeconds {
                    session.stopRunning()
                    continuation.resume(returning: seconds)
                    return
                }
                finishWaiters.append(continuation)
                if output.isRecording { output.stopRecording() } else { finish(seconds: 0) }
            }
        }
    }

    private func finish(seconds: Double) {
        recordedSeconds = seconds
        session.stopRunning()
        let waiters = finishWaiters
        finishWaiters = []
        waiters.forEach { $0.resume(returning: seconds) }
        DispatchQueue.main.async { self.isRecording = false }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.isRecording = true }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let wroteFile = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        let seconds = wroteFile ? max(0, output.recordedDuration.seconds) : 0
        let cutShort = !stopRequested
        queue.async { [self] in
            finish(seconds: seconds.isFinite ? seconds : 0)
            if cutShort { DispatchQueue.main.async { self.wasCutShort = true } }
        }
    }
}

/// The study flow's state: one thing at a time, timed, filmed, and turned into
/// a receipt, a streak and scroll time. Everything stays on this device, kept
/// apart per signed-in account.
@MainActor
final class StudyService: ObservableObject {
    static let shared = StudyService()

    /// Scroll time is earned from video, so a session that was not recorded
    /// still counts for the streak but earns none.
    static let requiresRecording = true
    /// Recordings are kept this long, then deleted.
    static let keepRecordingsDays = 7

    private static let logKey = "mivo.study.log"
    private static let activeKey = "mivo.study.active"

    struct Active: Codable, Equatable {
        var task: String
        var startedAt: Date
        var recordingName: String
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

    let recorder = StudyRecorder()
    private let defaults: UserDefaults
    private let balanceStore: ReelBalanceStore
    private let account: () -> String?

    init(
        defaults: UserDefaults = .standard,
        balanceStore: ReelBalanceStore = .shared,
        account: @escaping () -> String? = { StorageService.activeUserEmail }
    ) {
        self.defaults = defaults
        self.balanceStore = balanceStore
        self.account = account
        bind()
        pruneOldRecordings()
    }

    var streak: Int { log.streak(asOf: Date()) }
    var studiedTodaySeconds: Int { log.seconds(on: Date()) }
    var earnedTodaySeconds: Int { balanceStore.current().bonusSeconds }
    var trialPhase: StudyTrial.Phase { StudyTrial.phase(firstSessionAt: log.firstSessionAt, now: Date()) }

    private func key(_ base: String) -> String { AccountScopedKey.make(base, account: account()) }

    // MARK: - Account

    /// Loads the signed-in account's log and any session it left running.
    /// Called whenever the account may have changed.
    func bind() {
        log = defaults.data(forKey: key(Self.logKey)).flatMap { try? JSONDecoder().decode(StudyLog.self, from: $0) } ?? StudyLog()
        if let data = defaults.data(forKey: key(Self.activeKey)),
           let active = try? JSONDecoder().decode(Active.self, from: data) {
            phase = .running(active)
        } else {
            phase = .idle
        }
        cameraUnavailable = false
    }

    /// Signing out ends a running session without crediting it; the account's
    /// log and balance stay saved for next time.
    func signOut() {
        if case .running = phase { Task { _ = await recorder.stop() } }
        UIApplication.shared.isIdleTimerDisabled = false
        showRequested = false
        phase = .idle
        log = StudyLog()
    }

    /// Deleting the account removes its log, its balance and its recordings.
    func eraseAllData() {
        signOut()
        defaults.removeObject(forKey: key(Self.logKey))
        defaults.removeObject(forKey: key(Self.activeKey))
        balanceStore.erase()
        if let directory = Self.recordingsDirectory(account: account()) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Start and finish

    func start(task: String) async {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, case .idle = phase else { return }
        let name = "\(UUID().uuidString).mov"
        let active = Active(task: task, startedAt: Date(), recordingName: name)

        cameraUnavailable = true
        if await StudyRecorder.authorize(), let url = Self.recordingURL(name, account: account()) {
            cameraUnavailable = !(await recorder.start(to: url))
        }
        UIApplication.shared.isIdleTimerDisabled = true
        if let data = try? JSONEncoder().encode(active) { defaults.set(data, forKey: key(Self.activeKey)) }
        phase = .running(active)
    }

    /// A session earns scroll time when it began inside the free week or the
    /// person has Plus. Otherwise it is logged in full and the scroll time it
    /// would have earned is shown on the receipt, not added.
    func finish(hasPlus: Bool) async {
        guard case .running(let active) = phase else { return }
        let endedAt = Date()
        let recorderSeconds = cameraUnavailable ? 0 : await recorder.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        // Scroll time rests on the saved video, not on the recorder's say-so:
        // the file has to exist and play, and its length caps what is credited.
        let fileSeconds = cameraUnavailable ? 0 : await Self.verifiedVideoSeconds(
            at: Self.recordingURL(active.recordingName, account: account()))
        let elapsed = max(0, Int(endedAt.timeIntervalSince(active.startedAt)))
        let recorded = min(elapsed, Int(recorderSeconds), fileSeconds)
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
            recordedSeconds: recorded, scrollSecondsEarned: earned
        )
        log.entries.append(entry)
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: key(Self.logKey)) }
        defaults.removeObject(forKey: key(Self.activeKey))

        let capReached = before + earned >= ReelBalance.dailyEarnCapSeconds
        phase = .finished(Receipt(entry: entry, streak: streak, capReached: capReached, lockedScrollSeconds: locked))
    }

    func reset() {
        if case .finished = phase { phase = .idle }
    }

    // MARK: - Recordings

    /// Seconds of playable video in the file, or 0 when it is missing, empty
    /// or has no video track.
    static func verifiedVideoSeconds(at url: URL?) async -> Int {
        guard let url,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0 else { return 0 }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return 0 }
        return max(0, Int(duration.seconds))
    }

    private static func recordingsRoot() -> URL? {
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

    private func pruneOldRecordings() {
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
