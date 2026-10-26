import Combine
import Foundation

/// What starting a lock came to.
enum LockInStartResult: Equatable {
    case started(LockIn)
    /// Not started: nothing would have been blocked.
    case blocked([LockInLimitation])
    /// The task line was empty or too short to commit to.
    case invalidTask
    case alreadyLocked
}

/// What sending a message to Milo came to.
enum LockInSendOutcome: Equatable {
    case sent(MiloReview)
    /// Nothing was added to the chat; the person can send the same thing again.
    case failed(LockInError)
    /// No lock, a request is waiting, the chat is full, or the message is empty.
    case notAllowed
}

/// The one place a lock is started, talked about and ended. Views read its state;
/// nothing else shields apps for Lock-in.
@MainActor
final class LockInManager: ObservableObject {
    private(set) static var shared = LockInManager()

    #if DEBUG
    /// Lets a launch-argument preview run on scripted state instead of real Screen Time.
    static func installPreview(_ manager: LockInManager) {
        shared = manager
    }

    func seedPreview(
        current: LockIn?,
        history: [LockIn] = [],
        keyholder: LockInKeyholder? = nil,
        lastApps: SpotAppSelection = .empty
    ) {
        self.current = current
        self.history = history
        self.keyholder = keyholder
        self.lastApps = lastApps
        justReleased = nil
    }
    #endif

    /// The running lock, if any.
    @Published private(set) var current: LockIn?
    /// Finished locks, newest first.
    @Published private(set) var history: [LockIn] = []
    @Published private(set) var keyholder: LockInKeyholder?
    /// The apps chosen for the last lock, offered again for the next one.
    @Published private(set) var lastApps: SpotAppSelection = .empty
    /// Milo is reading the latest message.
    @Published private(set) var isReviewing = false
    /// A lock that just ended, shown once as a wrap-up.
    @Published var justReleased: LockIn?
    /// Set by a shield tap or `mivo://lockin`; the root presents the Lock-in screen.
    @Published var showRequested = false
    /// A short message for the screen to show, then clear.
    @Published var notice: String?

    /// First name used in emails to a keyholder. Set by the signed-in UI.
    var ownerName = ""

    private let persistence: LockInPersisting
    private let screenTime: LockInScreenTimeControlling
    private let backend: LockInBackend
    private let clock: () -> Date

    private var hasLoaded = false
    private var loadedEmail: String?
    private var endTask: Task<Void, Never>?

    init(
        persistence: LockInPersisting? = nil,
        screenTime: LockInScreenTimeControlling? = nil,
        backend: LockInBackend? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence ?? StorageLockInPersistence()
        self.screenTime = screenTime ?? LockInManager.makeDefaultScreenTime()
        self.backend = backend ?? SupabaseLockInBackend()
        self.clock = clock
    }

    private static func makeDefaultScreenTime() -> LockInScreenTimeControlling {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        return LockInScreenTime()
        #else
        return NoopLockInScreenTime()
        #endif
    }

    // MARK: Derived state

    var isLocked: Bool { current != nil }
    var isScreenTimeAuthorized: Bool { screenTime.isAuthorized }
    var isBackendAvailable: Bool { backend.isAvailable }

    // MARK: Account

    func setAccount(_ email: String?) {
        let normalized = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLoaded, loadedEmail == normalized {
            reconcile()
            return
        }
        // A lock held for the previous account must not keep shielding apps for the next one.
        if hasLoaded, current != nil {
            release(reason: .cancelledEarly)
        }
        persistence.accountEmail = normalized
        loadedEmail = normalized
        hasLoaded = true
        load()
        reconcile()
    }

    func signOut() {
        if current != nil { release(reason: .cancelledEarly) }
        endTask?.cancel()
        persistence.accountEmail = nil
        loadedEmail = nil
        hasLoaded = true
        current = nil
        history = []
        keyholder = nil
        lastApps = .empty
        justReleased = nil
        showRequested = false
        notice = nil
    }

    /// Deleting the account: removes everything stored for it.
    func eraseAllData() {
        endTask?.cancel()
        screenTime.end()
        persistence.erase()
        current = nil
        history = []
        keyholder = nil
        lastApps = .empty
        justReleased = nil
    }

    private func load() {
        current = persistence.loadCurrent()
        history = persistence.loadHistory()
        keyholder = persistence.loadKeyholder()
        lastApps = persistence.loadLastApps() ?? .empty
    }

    // MARK: Starting

    @discardableResult
    func start(
        task rawTask: String,
        durationMinutes: Int,
        apps: SpotAppSelection
    ) -> LockInStartResult {
        guard current == nil else { return .alreadyLocked }
        guard let task = LockInRules.cleanTask(rawTask) else { return .invalidTask }

        let now = clock()
        let lock = LockIn(
            id: UUID().uuidString,
            task: task,
            startedAt: now,
            endsAt: now.addingTimeInterval(LockInRules.duration(minutes: durationMinutes)),
            keyholder: keyholder,
            apps: apps
        )
        let result = screenTime.start(lock: lock)
        guard result.limitations.isEmpty else { return .blocked(result.limitations) }

        current = lock
        lastApps = apps
        persistence.saveCurrent(lock)
        persistence.saveLastApps(apps)
        justReleased = nil
        armEndTimer(for: lock)
        return .started(lock)
    }

    // MARK: Links

    /// `mivo://lockin` — from a lock's shield notification or any link. Returns
    /// whether the link was this feature's.
    func handle(url: URL) -> Bool {
        guard url.scheme == "mivo", url.host == "lockin" else { return false }
        reconcile()
        showRequested = true
        return true
    }

    // MARK: Time

    /// Brings stored state in line with the clock and with what Screen Time is
    /// actually doing. Safe to call as often as is convenient.
    func reconcile() {
        let now = clock()
        if screenTime.consumePendingRoute() { showRequested = true }
        guard let lock = current else {
            // A shield with no lock behind it is left over from a crash or a reset.
            screenTime.reconcile(now: now)
            return
        }
        if lock.isPastCheckIn(now: now) {
            release(reason: .timeRanOut, at: lock.endsAt)
        } else if !screenTime.reconcile(now: now) {
            // The shield was torn down early (Screen Time reset, extension). Put it back.
            let result = screenTime.start(lock: lock)
            if !result.limitations.isEmpty {
                notice = "Screen Time access is off, so your apps aren't locked right now."
            }
            armEndTimer(for: lock)
        } else {
            armEndTimer(for: lock)
        }
    }

    private func armEndTimer(for lock: LockIn) {
        endTask?.cancel()
        let delay = max(0, lock.endsAt.timeIntervalSince(clock()))
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    // MARK: Releasing

    /// Ends the lock for the given reason. The only place a lock ends.
    func release(reason: LockInReleaseReason, at date: Date? = nil) {
        guard var lock = current else { return }
        endTask?.cancel()
        endTask = nil
        screenTime.end()

        lock.releasedAt = date ?? clock()
        lock.releaseReason = reason
        current = nil
        persistence.saveCurrent(nil)

        history.insert(lock, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        persistence.saveHistory(history)

        // A mistaken start isn't worth a wrap-up screen.
        justReleased = reason == .cancelledEarly ? nil : lock
    }

    /// The undo for a lock started by mistake. False once the window has closed.
    @discardableResult
    func cancelFreely() -> Bool {
        guard let lock = current, lock.canCancelFreely(now: clock()) else { return false }
        release(reason: .cancelledEarly)
        return true
    }

    func dismissWrapUp() {
        justReleased = nil
    }

    // MARK: Milo

    /// Shows Milo what was done. Photos are passed through once and not kept.
    func send(text rawText: String, images: [Data] = []) async -> LockInSendOutcome {
        guard let lock = current, lock.canSendMessage, !isReviewing else { return .notAllowed }
        let text = LockInRules.cleanMessage(rawText)
        guard !text.isEmpty else { return .notAllowed }
        let pictures = Array(images.prefix(LockInRules.maxImagesPerMessage))

        let userMessage = LockInMessage(role: .user, text: text, imageCount: pictures.count, sentAt: clock())
        let thread = lock.messages + [userMessage]

        isReviewing = true
        defer { isReviewing = false }

        let review: MiloReview
        do {
            review = try await backend.reviewProof(
                task: lock.task,
                startedAt: lock.startedAt,
                messages: thread,
                images: pictures
            )
        } catch let error as LockInError {
            return .failed(error)
        } catch {
            return .failed(.failed)
        }

        // The lock may have ended while Milo was thinking (time ran out).
        guard var updated = current, updated.id == lock.id else { return .notAllowed }
        updated.messages = thread + [LockInMessage(role: .milo, text: review.reply, sentAt: clock())]
        updated.miloSummary = review.verdict == .convinced ? review.summary : nil
        current = updated
        persistence.saveCurrent(updated)

        if review.verdict == .convinced, !(updated.keyholder?.status == .active) {
            release(reason: .miloConvinced)
        }
        return .sent(review)
    }

    // MARK: Keyholder

    /// Emails a friend a link to agree to be the keyholder.
    func inviteKeyholder(name rawName: String, email rawEmail: String) async -> Result<LockInKeyholder, LockInError> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isPlausibleEmail(email), !name.isEmpty else { return .failure(.invalidEmail) }
        do {
            let invited = try await backend.inviteKeyholder(
                name: String(name.prefix(40)),
                email: email,
                ownerName: String(ownerName.prefix(40))
            )
            setKeyholder(invited)
            return .success(invited)
        } catch let error as LockInError {
            return .failure(error)
        } catch {
            return .failure(.failed)
        }
    }

    /// Asks the server whether the friend has agreed yet.
    func refreshKeyholder() async {
        guard let keyholder, keyholder.status != .revoked else { return }
        guard let latest = try? await backend.keyholderStatus(id: keyholder.id) else { return }
        guard latest != keyholder else { return }
        setKeyholder(latest)
    }

    /// Takes the keyholder away. Blocked while a lock is running: a lock can't be
    /// loosened by removing the person who guards it.
    @discardableResult
    func removeKeyholder() async -> Bool {
        guard current == nil, let keyholder else { return false }
        try? await backend.revokeKeyholder(id: keyholder.id)
        self.keyholder = nil
        persistence.saveKeyholder(nil)
        return true
    }

    private func setKeyholder(_ value: LockInKeyholder?) {
        keyholder = value
        persistence.saveKeyholder(value)
        if var lock = current {
            lock.keyholder = value
            current = lock
            persistence.saveCurrent(lock)
        }
    }

    /// Sends the keyholder an unlock request carrying Milo's summary. The person
    /// taps this on purpose; nothing is sent to a friend on its own.
    @discardableResult
    func askKeyholder() async -> Result<LockInUnlockRequest, LockInError> {
        guard let lock = current, lock.canRequestKeyholder, let keyholder else { return .failure(.failed) }
        let summary = lock.miloSummary ?? Self.unreviewedSummary(for: lock)
        do {
            let request = try await backend.requestUnlock(
                keyholderID: keyholder.id,
                lockID: lock.id,
                task: lock.task,
                summary: summary,
                endsAt: lock.endsAt,
                ownerName: String(ownerName.prefix(40))
            )
            guard var updated = current, updated.id == lock.id else { return .failure(.failed) }
            updated.requests.append(request)
            current = updated
            persistence.saveCurrent(updated)
            return .success(request)
        } catch let error as LockInError {
            return .failure(error)
        } catch {
            return .failure(.failed)
        }
    }

    /// Checks whether the keyholder has answered. Approval ends the lock.
    func pollKeyholderRequest() async {
        guard let lock = current, let pending = lock.pendingRequest else { return }
        guard let latest = try? await backend.requestStatus(id: pending.id) else { return }
        guard latest.status != .pending else { return }
        guard var updated = current, updated.id == lock.id,
              let index = updated.requests.firstIndex(where: { $0.id == pending.id }) else { return }

        updated.requests[index].status = latest.status
        updated.requests[index].keyholderNote = latest.keyholderNote
        current = updated
        persistence.saveCurrent(updated)

        if latest.status == .approved {
            release(reason: .keyholderApproved)
        }
    }

    // MARK: Helpers

    /// What a keyholder sees when the person skips Milo's review.
    static func unreviewedSummary(for lock: LockIn) -> String {
        let lastClaim = lock.messages.last { $0.role == .user }?.text
        guard let lastClaim, !lastClaim.isEmpty else {
            return "Milo hasn't reviewed this. They're asking you to decide."
        }
        return "Milo hasn't reviewed this. In their words: \(String(lastClaim.prefix(300)))"
    }

    /// Catches typos before an email is sent; the server checks again.
    static func isPlausibleEmail(_ value: String) -> Bool {
        guard value.count <= 254, !value.contains(" ") else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }
}
