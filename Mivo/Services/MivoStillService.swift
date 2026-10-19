import Foundation
import CoreMotion
import UIKit

/// Persistence for Still sessions. Deliberately separate from
/// `AppViewModel.sessions` and modeled after `MivoClearStore` — its own small
/// store rather than another array bolted onto the view model.
@MainActor
final class MivoStillStore: ObservableObject {
    static let shared = MivoStillStore()
    private static let currentTutorialVersion = 1

    @Published private(set) var sessions: [MivoStillSession] = []
    private var loadedEmail: String?

    private init() {}

    func prepare(for appVM: AppViewModel) async {
        guard let email = appVM.user?.email, loadedEmail != email else { return }
        loadedEmail = email
        sessions = StorageService.load([MivoStillSession].self, forKey: .mivoStillSessions, email: email) ?? []
    }

    func record(_ session: MivoStillSession) {
        sessions.insert(session, at: 0)
        sessions = Array(sessions.prefix(180))
        if let email = loadedEmail {
            StorageService.save(sessions, forKey: .mivoStillSessions, email: email)
        }
    }

    func hasCompletedTutorial() -> Bool {
        guard let email = loadedEmail else { return false }
        let completedVersion = StorageService.load(
            Int.self,
            forKey: .mivoStillTutorialVersion,
            email: email
        ) ?? 0
        return completedVersion >= Self.currentTutorialVersion
    }

    func completeTutorial() {
        guard let email = loadedEmail else { return }
        StorageService.save(
            Self.currentTutorialVersion,
            forKey: .mivoStillTutorialVersion,
            email: email
        )
    }

    var minutesToday: Int {
        let today = MivoDay.todayKey
        return sessions.filter { $0.date == today }.reduce(0) { $0 + $1.actualSeconds } / 60
    }

    var completedTodayCount: Int {
        sessions.filter { $0.date == MivoDay.todayKey && $0.outcome == .completed }.count
    }

    /// Consecutive days, ending today or yesterday, with at least one
    /// completed session. Stops at the first gap.
    var currentStreakDays: Int {
        let completedDates = Set(sessions.filter { $0.outcome == .completed }.map(\.date))
        guard !completedDates.isEmpty else { return 0 }
        var offset = 0
        if !completedDates.contains(MivoDay.key(offsetFromToday: 0)) {
            offset = -1
            guard completedDates.contains(MivoDay.key(offsetFromToday: offset)) else { return 0 }
        }
        var streak = 0
        while completedDates.contains(MivoDay.key(offsetFromToday: offset)) {
            streak += 1
            offset -= 1
        }
        return streak
    }
}

/// While a Still session is running, `MivoAppDelegate.willPresent` checks
/// this to hold back Mivo's own notification banners and sounds — the whole
/// point is not to tempt a pickup. This is the extent of what a third-party
/// app is able to silence: there is no public API to suppress notifications
/// from *other* apps or the system, only the ones Mivo itself schedules.
enum MivoStillNotificationSuppression {
    private static let key = "mivo.still.notificationsSuppressed"

    static var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Wraps `CMMotionManager` and feeds every reading through `MivoStillEngine`,
/// so the on-device sensor loop is a thin adapter around logic that is
/// otherwise fully unit-tested.
///
/// Face-down detection uses `gravity.z`: Apple's device frame has +Z pointing
/// out of the screen, so when the screen faces down that axis points toward
/// the ground and gravity's component along it is positive (≈ +1); face-up it
/// is ≈ −1. `userAcceleration` is gravity already removed by CoreMotion's
/// sensor fusion, so it reads near zero at rest and spikes on any pickup.
@MainActor
final class MivoStillMotionMonitor: ObservableObject {
    @Published private(set) var phase: MivoStillPhase = .waitingToSettle(stillElapsed: 0)
    @Published private(set) var lastSample: MivoStillSample?
    @Published private(set) var pickupCount = 0
    /// Seconds actually counted down (i.e. time since settling finished), for
    /// the session record. Distinct from `plannedSeconds - remaining` because
    /// the terminal phases carry no remaining-time payload.
    @Published private(set) var elapsedActiveSeconds: Double = 0

    private let motionManager = CMMotionManager()
    private var plannedSeconds: Double = 0
    private var lastUpdateTimestamp: TimeInterval?
    private var idleTimerWasDisabled = false
    /// The countdown must only advance while Mivo is the app on screen. Motion
    /// samples that arrive while backgrounded are dropped, and the clock
    /// anchor is cleared on the way out so a resumed session doesn't read the
    /// time spent away as one giant still (or moving) tick.
    private var isForeground = true
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func start(plannedSeconds: Double) {
        guard motionManager.isDeviceMotionAvailable else { return }
        self.plannedSeconds = plannedSeconds
        pickupCount = 0
        elapsedActiveSeconds = 0
        phase = .waitingToSettle(stillElapsed: 0)
        lastUpdateTimestamp = nil
        isForeground = true
        MivoStillNotificationSuppression.isActive = true

        // The countdown only keeps receiving motion updates while the screen
        // is on, and the phone is meant to sit untouched face-down for many
        // minutes — the idle timer would otherwise lock it mid-session.
        idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true

        registerAppStateObservers()

        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
        removeAppStateObservers()
        MivoStillNotificationSuppression.isActive = false
    }

    private func registerAppStateObservers() {
        removeAppStateObservers()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isForeground = false
                self?.lastUpdateTimestamp = nil
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isForeground = true
                self?.lastUpdateTimestamp = nil
            }
        }
    }

    private func removeAppStateObservers() {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        backgroundObserver = nil
        foregroundObserver = nil
    }

    private func handle(_ motion: CMDeviceMotion) {
        guard isForeground else { return }
        let now = motion.timestamp
        defer { lastUpdateTimestamp = now }

        // The first sample only anchors the clock — there is no prior reading
        // to compute a delta against.
        guard let last = lastUpdateTimestamp else { return }
        let dt = now - last
        // A large gap (e.g. a brief suspension) would otherwise be read as one
        // giant motionless tick and silently fast-forward the countdown.
        guard dt > 0, dt < 1.0 else { return }

        let a = motion.userAcceleration
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        let sample = MivoStillSample(gravityZ: motion.gravity.z, userAccelerationMagnitude: magnitude)
        lastSample = sample

        let previousPhase = phase
        let next = MivoStillEngine.advance(
            phase: phase,
            sample: sample,
            dt: dt,
            plannedSeconds: plannedSeconds
        )
        // The countdown is only running once settling has finished, so only
        // count ticks whose starting phase was already past that point.
        if case .waitingToSettle = previousPhase {} else if !previousPhase.isTerminal {
            elapsedActiveSeconds += dt
        }
        switch next {
        case .active(_, let pickups), .disturbed(_, let pickups, _, _):
            pickupCount = pickups
        case .waitingToSettle, .completed:
            break
        }
        phase = next
    }
}
