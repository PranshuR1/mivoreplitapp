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
/// a receipt, a streak and scroll time. Everything stays on this device.
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

    let recorder = StudyRecorder()
    private let defaults: UserDefaults
    private let balanceStore: ReelBalanceStore

    init(defaults: UserDefaults = .standard, balanceStore: ReelBalanceStore = .shared) {
        self.defaults = defaults
        self.balanceStore = balanceStore
        log = defaults.data(forKey: Self.logKey).flatMap { try? JSONDecoder().decode(StudyLog.self, from: $0) } ?? StudyLog()
        if let data = defaults.data(forKey: Self.activeKey),
           let active = try? JSONDecoder().decode(Active.self, from: data) {
            phase = .running(active)
        }
        pruneOldRecordings()
    }

    var streak: Int { log.streak(asOf: Date()) }
    var studiedTodaySeconds: Int { log.seconds(on: Date()) }
    var earnedTodaySeconds: Int { balanceStore.current().bonusSeconds }

    // MARK: - Start and finish

    func start(task: String) async {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, case .idle = phase else { return }
        let name = "\(UUID().uuidString).mov"
        let active = Active(task: task, startedAt: Date(), recordingName: name)

        cameraUnavailable = true
        if await StudyRecorder.authorize(), let url = Self.recordingURL(name) {
            cameraUnavailable = !(await recorder.start(to: url))
        }
        UIApplication.shared.isIdleTimerDisabled = true
        if let data = try? JSONEncoder().encode(active) { defaults.set(data, forKey: Self.activeKey) }
        phase = .running(active)
    }

    func finish() async {
        guard case .running(let active) = phase else { return }
        let endedAt = Date()
        let videoSeconds = cameraUnavailable ? 0 : await recorder.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        let elapsed = max(0, Int(endedAt.timeIntervalSince(active.startedAt)))
        let recorded = min(elapsed, Int(videoSeconds))
        let creditable = Self.requiresRecording ? recorded : elapsed

        var balance = balanceStore.current()
        let before = balance.bonusSeconds
        let earned = balance.creditStudy(seconds: creditable)
        balanceStore.save(balance)

        let entry = StudyEntry(
            task: active.task, startedAt: active.startedAt, endedAt: endedAt,
            recordedSeconds: recorded, scrollSecondsEarned: earned
        )
        log.entries.append(entry)
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: Self.logKey) }
        defaults.removeObject(forKey: Self.activeKey)

        let capReached = before + earned >= ReelBalance.dailyEarnCapSeconds
        phase = .finished(Receipt(entry: entry, streak: streak, capReached: capReached))
    }

    func reset() {
        if case .finished = phase { phase = .idle }
    }

    // MARK: - Recordings

    private static func recordingsDirectory() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let directory = documents.appendingPathComponent("Study", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func recordingURL(_ name: String) -> URL? {
        recordingsDirectory()?.appendingPathComponent(name)
    }

    private func pruneOldRecordings() {
        guard let directory = Self.recordingsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.keepRecordingsDays) * 86_400)
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            if created < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
