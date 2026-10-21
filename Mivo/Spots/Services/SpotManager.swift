import Foundation
import SwiftUI

/// The lightweight confirmation shown after a tag tap.
struct SpotNotice: Identifiable, Equatable {
    let id = UUID()
    let createdAt = Date()
    var title: String
    var message: String?
    /// A plain-spoken note when something stopped the Spot doing everything it
    /// was set up to do (for example Screen Time access being off).
    var caveat: String?
    var spotID: String?
    var icon: String?
    /// Something the person needs to read and act on, not a confirmation. Stays up longer.
    var isError = false
}

/// A pause or intention question raised by tapping a shielded app.
struct SpotShieldPrompt: Identifiable, Equatable {
    enum Kind: Equatable { case pause, intention }
    let id = UUID()
    let kind: Kind
    let spotName: String
    let appName: String?
}

enum SpotActivationOutcome: Equatable {
    case started(sessionID: String)
    case ended(sessionID: String)
    case notFound
    case disabled
    /// The same tap delivered twice (iOS can hand a link over more than once).
    case ignoredDuplicate
}

enum SpotCopy {
    static func activationMessage(mode: SpotMode, durationMinutes: Int?) -> String {
        switch mode {
        case .focus:
            guard let minutes = durationMinutes else { return "Focus until you end it." }
            return "Focus for the next \(phrase(minutes: minutes))."
        case .pause:
            return "Mivo will pause you before these apps."
        case .intention:
            return "Mivo will ask what you came to do, once."
        case .awareness:
            return "Mivo will quietly note your time in these apps."
        }
    }

    static func phrase(minutes: Int) -> String {
        switch minutes {
        case 60: return "hour"
        case 90: return "hour and a half"
        case 120: return "two hours"
        default: return SpotFormat.duration(minutes: minutes)
        }
    }

    static func caveat(for limitations: [SpotLimitation], mode: SpotMode) -> String? {
        if limitations.contains(.screenTimeNotAuthorized) {
            return mode.usesShield
                ? "Screen Time access is off, so Mivo can't pause these apps. It will still keep the time."
                : "Screen Time access is off, so Mivo can't measure these apps."
        }
        if limitations.contains(.noAppsSelected) {
            return "No apps are chosen for this Spot yet."
        }
        if limitations.contains(.usageTrackingUnavailable) {
            return "iOS wouldn't start usage tracking this time, so app time won't be measured."
        }
        return nil
    }
}

/// Owns Mivo Spots: the list, the one running session, history, and every rule
/// about starting and ending. Screen Time itself is behind `SpotScreenTimeControlling`;
/// this class decides *when*, that one does the work.
@MainActor
final class SpotManager: ObservableObject {
    static let shared = SpotManager()

    static let maxSpots = 12
    static let maxHistory = 500
    static let maxNameLength = 28
    /// A second delivery of the same tap inside this window is ignored.
    static let duplicateTapWindow: TimeInterval = 4

    @Published private(set) var spots: [MivoSpot] = []
    @Published private(set) var sessions: [SpotSession] = []
    @Published private(set) var activeSession: SpotSession?
    @Published var notice: SpotNotice?
    @Published var summaryToShow: SpotSessionSummary?
    @Published var shieldPrompt: SpotShieldPrompt?
    /// Set when a shield tap asks to see the running Spot.
    @Published var showActiveSpotRequested = false
    /// An official Mivo Spot that was scanned and needs setting up. The UI shows
    /// the setup flow while this is set.
    @Published var claimRequest: PhysicalSpotClaimRequest?

    /// A scan that arrived before the person could be asked about it (logged out,
    /// or the UI wasn't up yet) is kept this long. Long enough to sign in.
    static let pendingLinkLifetime: TimeInterval = 30 * 60
    /// How often a running app re-checks its official Spots against the backend.
    static let physicalSyncInterval: TimeInterval = 15 * 60
    private static let pendingLinkKey = "mivo.spot.pendingPhysicalLink"

    private let persistence: SpotPersisting
    private let screenTime: SpotScreenTimeControlling
    private let registry: SpotRegistry
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var endWorkItem: DispatchWorkItem?
    private var relockWorkItem: DispatchWorkItem?
    private var hasLoaded = false
    private var loadedEmail: String?
    private var prepareSession: (() async throws -> Void)?
    private var isUIReady = false
    private var lastPhysicalScan: (id: String, at: Date)?
    private var lastHandledURL: (key: String, at: Date)?
    private var lastPhysicalSync: Date?

    init(
        persistence: SpotPersisting? = nil,
        screenTime: SpotScreenTimeControlling? = nil,
        registry: SpotRegistry? = nil,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence ?? StorageSpotPersistence()
        self.screenTime = screenTime ?? SpotManager.makeDefaultScreenTime()
        self.registry = registry ?? BackendSpotRegistry()
        self.defaults = defaults
        self.clock = clock
    }

    private static func makeDefaultScreenTime() -> SpotScreenTimeControlling {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        return SpotScreenTime()
        #else
        return NoopSpotScreenTime()
        #endif
    }

    // MARK: - Lifecycle

    /// Binds to the signed-in account and loads its Spots. Safe to call often.
    func setAccount(_ email: String?) {
        let normalized = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLoaded, loadedEmail == normalized {
            reconcile()
            return
        }
        // A Spot running for the previous account must not keep shielding apps
        // for the next one.
        if hasLoaded, activeSession != nil {
            end(reason: .signedOut)
        }
        persistence.accountEmail = normalized
        loadedEmail = normalized
        hasLoaded = true
        load()
        reconcile()
    }

    /// Binds to whoever is signed in, if nothing has bound an account yet. Used
    /// by entry points that can run before the UI exists (a tag tap that cold-
    /// launches Mivo, a Shortcut).
    func ensureLoaded() {
        if !hasLoaded { setAccount(StorageService.activeUserEmail) }
    }

    /// Signing out: the running Spot ends, but the account's Spots stay saved.
    func signOut() {
        if activeSession != nil { end(reason: .signedOut) }
        screenTime.clearEverything()
        cancelTimers()
        spots = []
        sessions = []
        summaryToShow = nil
        shieldPrompt = nil
        notice = nil
        claimRequest = nil
        lastPhysicalSync = nil
        // The signed-in UI is going away; the next sign-in attaches a new one.
        isUIReady = false
        prepareSession = nil
        persistence.accountEmail = nil
        loadedEmail = nil
        hasLoaded = true
    }

    /// Deleting the account: removes everything stored for it.
    func eraseAllData() {
        cancelTimers()
        screenTime.clearEverything()
        persistence.erase()
        activeSession = nil
        spots = []
        sessions = []
        summaryToShow = nil
        shieldPrompt = nil
        claimRequest = nil
        defaults.removeObject(forKey: Self.pendingLinkKey)
    }

    private func load() {
        spots = persistence.loadSpots()
        sessions = persistence.loadSessions()
        activeSession = persistence.loadActiveSession()
    }

    /// Brings the world back in step with the clock: finishes a Spot whose time
    /// is up, restores timers after a relaunch, and makes the shield match what
    /// the running Spot wants. Called on foreground and once a minute.
    func reconcile() {
        let now = clock()
        if let session = activeSession {
            if now >= session.plannedEndDate {
                finalize(session, at: session.plannedEndDate, reason: session.isOpenEnded ? .expired : .timerCompleted)
            } else if !screenTime.isLiveSpotRunning(now: now) {
                // The monitor extension (or a reset) already tore the Spot down.
                finalize(session, at: min(now, session.plannedEndDate), reason: .timerCompleted)
            } else {
                screenTime.reconcileShield(now: now)
                armEndTimer(for: session)
            }
        } else if screenTime.isLiveSpotRunning(now: now) {
            screenTime.clearEverything()
        }
        checkPendingShieldRoute()
        surfaceUnseenSummary(now: now)
    }

    #if DEBUG
    /// Fills the manager with fixtures for the `-MivoPreviewSpot…` launch arguments.
    /// Nothing is persisted.
    func loadPreviewState(spots: [MivoSpot], sessions: [SpotSession], active: SpotSession?) {
        self.spots = spots
        self.sessions = sessions
        self.activeSession = active
        hasLoaded = true
    }
    #endif

    // MARK: - Spots

    enum SaveError: Error, Equatable {
        case emptyName
        case tooManySpots
    }

    @discardableResult
    func save(_ spot: MivoSpot) -> Result<MivoSpot, SaveError> {
        var spot = spot
        spot.name = String(spot.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        guard !spot.name.isEmpty else { return .failure(.emptyName) }

        if let index = spots.firstIndex(where: { $0.id == spot.id }) {
            spots[index] = spot
            // Changing what a running Spot covers mid-session would leave the
            // shield describing something else, so the change applies next time.
            if activeSession?.spotID == spot.id, !spot.isEnabled {
                end(reason: .spotRemoved)
            }
        } else {
            guard spots.count < Self.maxSpots else { return .failure(.tooManySpots) }
            spots.append(spot)
        }
        persistence.saveSpots(spots)
        return .success(spot)
    }

    func delete(spotID: String) {
        if activeSession?.spotID == spotID { end(reason: .spotRemoved) }
        spots.removeAll { $0.id == spotID }
        persistence.saveSpots(spots)
    }

    func setEnabled(_ enabled: Bool, spotID: String) {
        guard var spot = spots.first(where: { $0.id == spotID }) else { return }
        spot.isEnabled = enabled
        _ = save(spot)
    }

    /// Forgets a sticker or Shortcut from the first version. The Spot stays.
    func disconnectTag(spotID: String) {
        guard var spot = spots.first(where: { $0.id == spotID }) else { return }
        spot.tag = nil
        _ = save(spot)
    }

    func spot(id: String) -> MivoSpot? { spots.first { $0.id == id } }

    var activeSpot: MivoSpot? {
        guard let activeSession else { return nil }
        return spot(id: activeSession.spotID)
    }

    func isActive(_ spotID: String) -> Bool { activeSession?.spotID == spotID }

    // MARK: - Starting and ending

    /// Opens a Spot link. Returns true when the URL was a Spot link at all.
    @discardableResult
    func handle(url: URL, trigger: SpotTrigger = .link) -> Bool {
        // The shield extension asks to open Mivo with this; the question itself
        // is waiting in the App Group, so picking it up is all there is to do.
        if url.scheme == SpotLink.customScheme, url.host == SpotLink.promptHost {
            ensureLoaded()
            reconcile()
            return true
        }
        guard let target = SpotLink.target(from: url) else { return false }
        // iOS can deliver one tap through more than one path (the URL handler and
        // the universal-link user activity). The repeat must not end what the
        // first just started, or start what it just ended.
        let now = clock()
        let key = url.absoluteString.lowercased()
        if let last = lastHandledURL, last.key == key, now.timeIntervalSince(last.at) < Self.duplicateTapWindow {
            return true
        }
        lastHandledURL = (key, now)
        // A link can arrive before the UI has bound an account (cold launch from
        // a tag tap), so bind to whoever is signed in right now.
        ensureLoaded()
        handle(target: target, trigger: trigger)
        return true
    }

    /// Routes a scanned or opened Spot link: an official Mivo Spot, or a Spot made
    /// by the first version.
    func handle(target: SpotLink.Target, trigger: SpotTrigger) {
        switch target {
        case .legacy(let spotID):
            handleScan(spotID: spotID, trigger: trigger)
        case .physical(let physicalID):
            handlePhysicalScan(physicalID: physicalID, trigger: trigger)
        }
    }

    /// What a tag tap means: start the Spot, or end it if it is already running.
    @discardableResult
    func handleScan(spotID: String, trigger: SpotTrigger) -> SpotActivationOutcome {
        let now = clock()
        if let active = activeSession, active.spotID == spotID {
            if now.timeIntervalSince(active.startDate) < Self.duplicateTapWindow {
                return .ignoredDuplicate
            }
            end(reason: .endedByTag, now: now)
            return .ended(sessionID: active.id)
        }
        let outcome = activate(spotID: spotID, trigger: trigger, now: now)
        switch outcome {
        case .notFound:
            notice = SpotNotice(
                title: "That Spot isn't on this phone",
                message: StorageService.activeUserEmail == nil
                    ? "Sign in to Mivo to use your Spots."
                    : "Open Mivo Spots to create it, or connect a different tag."
            )
        case .disabled:
            if spot(id: spotID)?.isSwitchedOffByMivo == true {
                notice = SpotNotice(
                    title: "This Mivo Spot is switched off",
                    message: "Mivo has turned this Spot off.",
                    isError: true
                )
            } else {
                notice = SpotNotice(title: "This Spot is switched off", message: "Turn it on in Mivo Spots to use it.")
            }
        default:
            break
        }
        return outcome
    }

    @discardableResult
    func activate(spotID: String, trigger: SpotTrigger, now: Date? = nil) -> SpotActivationOutcome {
        let now = now ?? clock()
        guard let spot = spot(id: spotID) else { return .notFound }
        guard spot.isEnabled, !spot.isSwitchedOffByMivo else { return .disabled }

        if let active = activeSession {
            if active.spotID == spotID { return .ignoredDuplicate }
            end(reason: .replaced, now: now)
        }

        let minutes = spot.defaultDurationMinutes
        let isOpenEnded = minutes == nil
        let lengthMinutes = minutes ?? SpotKeys.openEndedCapHours * 60
        var session = SpotSession(
            id: UUID().uuidString.lowercased(),
            spotID: spot.id,
            spotName: spot.name,
            spotIcon: spot.icon,
            mode: spot.mode,
            startDate: now,
            plannedEndDate: now.addingTimeInterval(TimeInterval(lengthMinutes * 60)),
            isOpenEnded: isOpenEnded,
            endDate: nil,
            completionReason: nil,
            trigger: trigger,
            trackedApps: [],
            usageTracked: false,
            usage: nil,
            intention: nil,
            pausesContinued: 0,
            summarySeen: false
        )

        let start = screenTime.start(spot: spot, session: session)
        session.trackedApps = start.trackedApps
        session.usageTracked = start.usageTracked
        activeSession = session
        persistence.saveActiveSession(session)
        armEndTimer(for: session)
        recordScan(spotID: spot.id, trigger: trigger, at: now)

        notice = SpotNotice(
            title: "\(spot.name) activated",
            message: SpotCopy.activationMessage(mode: spot.mode, durationMinutes: minutes),
            caveat: SpotCopy.caveat(for: start.limitations, mode: spot.mode),
            spotID: spot.id,
            icon: spot.icon
        )
        HapticsService.success()
        return .started(sessionID: session.id)
    }

    func end(reason: SpotCompletionReason, now: Date? = nil) {
        guard let session = activeSession else { return }
        finalize(session, at: now ?? clock(), reason: reason)
    }

    private func finalize(_ session: SpotSession, at endDate: Date, reason: SpotCompletionReason) {
        cancelTimers()
        var finished = session
        finished.endDate = max(endDate, session.startDate)
        finished.completionReason = reason
        if let reading = screenTime.finish(session: finished) {
            finished.usage = SpotUsageRecord(
                totalMinutes: reading.totalMinutes,
                perApp: finished.trackedApps.map { app in
                    SpotAppUsage(
                        index: app.index,
                        name: app.name,
                        tokenData: app.tokenData,
                        minutes: reading.perApp[app.index] ?? 0
                    )
                }
            )
        }

        activeSession = nil
        persistence.saveActiveSession(nil)

        let isCounted = finished.activeSeconds() >= SpotInsights.minimumCountedSeconds
        let showsSummary = isCounted && reason != .signedOut && reason != .spotRemoved
        finished.summarySeen = !showsSummary
        sessions.insert(finished, at: 0)
        if sessions.count > Self.maxHistory { sessions = Array(sessions.prefix(Self.maxHistory)) }
        persistence.saveSessions(sessions)

        if showsSummary {
            summaryToShow = SpotInsights.summary(for: finished, history: sessions)
        }
        shieldPrompt = nil
        HapticsService.impact(style: .light)
    }

    // MARK: - Official Mivo Spots
    //
    // A Mivo Spot is a tag Mivo programmed with `https://usemivo.app/s/<ID>`. The
    // ID is all it carries. What the Spot *does* is the `MivoSpot` on this phone;
    // the backend only knows who owns the ID and whether Mivo has switched it off.

    /// Called by the signed-in UI. Gives the manager a way to refresh the sign-in
    /// before a backend call, and picks up a scan that arrived before there was a
    /// UI (cold launch, or logged out).
    func attachUI(prepareSession: @escaping () async throws -> Void) {
        self.prepareSession = prepareSession
        isUIReady = true
        processPendingPhysicalLink()
        Task { await syncPhysicalSpots() }
    }

    private func prepare() async throws {
        do { try await prepareSession?() }
        catch { throw BackendSpotRegistry.map(error) }
    }

    /// What a tap on an official Mivo Spot means.
    ///
    /// - Already set up on this account: starts it, or ends it if it is running.
    ///   No network is needed, so everyday use works offline.
    /// - Otherwise the backend is asked what the ID is, and the person is taken to
    ///   setup (unclaimed), or told plainly why not (someone else's, switched off,
    ///   unknown).
    /// - Logged out: the ID is kept and picked up once the person signs in.
    func handlePhysicalScan(physicalID: String, trigger: SpotTrigger) {
        guard let id = PhysicalSpotID.normalize(physicalID) else {
            notice = Self.errorNotice(.invalid)
            return
        }
        // iOS can hand the same tag over twice; the second delivery must not turn
        // a Spot that just started back off.
        let now = clock()
        if let last = lastPhysicalScan, last.id == id, now.timeIntervalSince(last.at) < Self.duplicateTapWindow {
            return
        }
        lastPhysicalScan = (id, now)

        if let local = spots.first(where: { $0.physical?.spotID == id }) {
            handleScan(spotID: local.id, trigger: trigger)
            Task { await syncPhysicalSpots() }
            return
        }
        guard loadedEmail != nil, isUIReady else {
            rememberPendingPhysicalLink(id)
            return
        }
        Task { await presentPhysicalSpot(id) }
    }

    /// Asks the backend about an ID this account hasn't set up, and responds.
    func presentPhysicalSpot(_ id: String, pairWith spotID: String? = nil) async {
        do {
            try await prepare()
            let state = try await registry.resolve(id)
            switch state {
            case .unclaimed, .yours:
                guard claimRequest == nil else { return }
                claimRequest = PhysicalSpotClaimRequest(
                    physicalID: id, alreadyYours: state == .yours, pairWithSpotID: spotID
                )
            case .taken: notice = Self.errorNotice(.taken)
            case .disabled: notice = Self.errorNotice(.disabled)
            case .invalid: notice = Self.errorNotice(.invalid)
            }
        } catch {
            let failure = BackendSpotRegistry.map(error)
            if failure == .signedOut { rememberPendingPhysicalLink(id) }
            notice = Self.errorNotice(failure)
        }
    }

    /// Claims `physicalID` for this account and saves `spot` — a new setup or an
    /// existing one — as what that Spot runs. Nothing is saved unless the claim
    /// succeeds, and the claim isn't made unless the setup is valid, so a failure
    /// never leaves a half-finished Spot behind.
    func claimPhysicalSpot(
        physicalID: String,
        configuring spot: MivoSpot
    ) async -> Result<MivoSpot, PhysicalSpotError> {
        guard let id = PhysicalSpotID.normalize(physicalID) else { return .failure(.invalid) }
        var spot = spot
        spot.name = String(spot.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        guard !spot.name.isEmpty else { return .failure(.emptyName) }
        let existing = self.spot(id: spot.id)
        if existing == nil, spots.count >= Self.maxSpots { return .failure(.tooManySpots) }
        let previousPhysicalID = existing?.physical?.spotID

        let outcome: PhysicalSpotClaimOutcome
        do {
            try await prepare()
            outcome = try await registry.claim(id)
        } catch {
            return .failure(BackendSpotRegistry.map(error))
        }
        guard case .claimed(let ownerUserID, let claimedAt) = outcome else {
            switch outcome {
            case .taken: return .failure(.taken)
            case .disabled: return .failure(.disabled)
            default: return .failure(.invalid)
            }
        }

        // One setup per Spot: free any other setup on this phone that held this ID.
        for index in spots.indices where spots[index].id != spot.id && spots[index].physical?.spotID == id {
            spots[index].physical = nil
        }
        spot.physical = PhysicalSpotLink(
            spotID: id,
            ownerUserID: ownerUserID,
            status: .claimed,
            claimedAt: claimedAt,
            lastScannedAt: nil,
            lastVerifiedAt: clock()
        )
        switch save(spot) {
        case .success(let saved):
            clearPendingPhysicalLink()
            // Re-pairing a Spot that already had a Mivo Spot gives the old one back.
            if let previousPhysicalID, previousPhysicalID != id {
                try? await registry.release(previousPhysicalID)
            }
            return .success(saved)
        case .failure(.emptyName): return .failure(.emptyName)
        case .failure(.tooManySpots): return .failure(.tooManySpots)
        }
    }

    /// Detaches a Spot from its Mivo Spot: the backend frees the ID (so it can be
    /// set up again or passed on) and the setup stays here as a Digital Spot.
    /// Needs the internet, so the two sides can't disagree.
    func disconnectPhysicalSpot(spotID: String) async -> Result<Void, PhysicalSpotError> {
        guard var spot = spot(id: spotID), let physical = spot.physical else { return .success(()) }
        do {
            try await prepare()
            try await registry.release(physical.spotID)
        } catch {
            return .failure(BackendSpotRegistry.map(error))
        }
        spot.physical = nil
        _ = save(spot)
        return .success(())
    }

    /// Deletes a Spot and, if it ran from a Mivo Spot, frees that too. Offline, the
    /// Spot is still deleted; scanning the Mivo Spot later offers setup again.
    func deleteSpot(spotID: String) async {
        let physicalID = spot(id: spotID)?.physical?.spotID
        delete(spotID: spotID)
        guard let physicalID else { return }
        do {
            try await prepare()
            try await registry.release(physicalID)
        } catch {}
    }

    /// Compares this phone's Mivo Spots with the backend's view of the account:
    /// a Spot Mivo switched off stops working, and one that was released elsewhere
    /// becomes a Digital Spot. Quiet and throttled; a failure changes nothing.
    func syncPhysicalSpots(force: Bool = false) async {
        guard isUIReady, spots.contains(where: { $0.physical != nil }) else { return }
        let now = clock()
        if !force, let last = lastPhysicalSync, now.timeIntervalSince(last) < Self.physicalSyncInterval { return }
        do {
            try await prepare()
            let records = try await registry.mine()
            lastPhysicalSync = clock()
            applyPhysicalRecords(records)
        } catch {}
    }

    func applyPhysicalRecords(_ records: [PhysicalSpotRecord]) {
        let byID = Dictionary(records.map { ($0.spotID, $0) }, uniquingKeysWith: { first, _ in first })
        let now = clock()
        for index in spots.indices {
            guard var link = spots[index].physical else { continue }
            if let record = byID[link.spotID] {
                link.status = record.status
                link.lastVerifiedAt = now
                spots[index].physical = link
                if record.status == .disabled, activeSession?.spotID == spots[index].id {
                    end(reason: .spotRemoved)
                }
            } else {
                spots[index].physical = nil
            }
        }
        persistence.saveSpots(spots)
    }

    // MARK: Scans that arrive before the person can be asked

    private func rememberPendingPhysicalLink(_ id: String) {
        defaults.set(["id": id, "at": clock().timeIntervalSince1970], forKey: Self.pendingLinkKey)
    }

    private func clearPendingPhysicalLink() {
        defaults.removeObject(forKey: Self.pendingLinkKey)
    }

    /// The ID of a scan waiting for sign-in, if it hasn't gone stale. Consumes it.
    func takePendingPhysicalLink() -> String? {
        defer { clearPendingPhysicalLink() }
        guard let stored = defaults.dictionary(forKey: Self.pendingLinkKey),
              let id = stored["id"] as? String,
              let at = stored["at"] as? TimeInterval,
              clock().timeIntervalSince1970 - at < Self.pendingLinkLifetime else { return nil }
        return PhysicalSpotID.normalize(id)
    }

    func processPendingPhysicalLink() {
        guard isUIReady, loadedEmail != nil, let id = takePendingPhysicalLink() else { return }
        // Skip the double-delivery guard: this is a deferred scan, not a repeat.
        lastPhysicalScan = nil
        handlePhysicalScan(physicalID: id, trigger: .link)
    }

    static func errorNotice(_ error: PhysicalSpotError) -> SpotNotice {
        SpotNotice(title: error.message, isError: true)
    }

    // MARK: - Shield hand-off

    /// Picks up a tap on a shielded app. Called when Mivo comes to the foreground.
    func checkPendingShieldRoute() {
        guard let pending = screenTime.consumePendingRoute(), let session = activeSession else { return }
        switch pending.route {
        case .pause where session.mode == .pause:
            shieldPrompt = SpotShieldPrompt(kind: .pause, spotName: session.spotName, appName: pending.appName)
        case .intention where session.mode == .intention && session.intention == nil:
            shieldPrompt = SpotShieldPrompt(kind: .intention, spotName: session.spotName, appName: pending.appName)
        default:
            showActiveSpotRequested = true
        }
    }

    /// The person finished a pause and chose to continue: open the apps for a while.
    func continuePastPause(minutes: Int) {
        guard var session = activeSession, session.mode == .pause else { return }
        let now = clock()
        let until = min(now.addingTimeInterval(TimeInterval(max(1, minutes) * 60)), session.plannedEndDate)
        screenTime.liftShield(until: until)
        session.pausesContinued += 1
        activeSession = session
        persistence.saveActiveSession(session)
        armRelockTimer(until: until)
        shieldPrompt = nil
    }

    func declinePause() {
        shieldPrompt = nil
    }

    /// The person answered "What did you come here to do?". Asked once per Spot.
    func answerIntention(choice: SpotIntentionChoice?, note: String?) {
        guard var session = activeSession, session.mode == .intention else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.intention = SpotIntentionAnswer(
            choice: choice,
            note: (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(140)),
            answeredAt: clock()
        )
        activeSession = session
        persistence.saveActiveSession(session)
        screenTime.liftShieldForRestOfSpot()
        shieldPrompt = nil
    }

    func dismissSummary() {
        guard let summary = summaryToShow else { return }
        markSummarySeen(sessionID: summary.sessionID)
        summaryToShow = nil
    }

    private func markSummarySeen(sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].summarySeen = true
        persistence.saveSessions(sessions)
    }

    /// A Spot that ended while Mivo was closed still gets its summary — once.
    private func surfaceUnseenSummary(now: Date) {
        guard summaryToShow == nil, activeSession == nil,
              let session = sessions.first(where: {
                  !$0.summarySeen && $0.endDate != nil
                      && $0.activeSeconds() >= SpotInsights.minimumCountedSeconds
                      && now.timeIntervalSince($0.endDate ?? now) < 12 * 3600
              }) else { return }
        summaryToShow = SpotInsights.summary(for: session, history: sessions)
    }

    private func recordScan(spotID: String, trigger: SpotTrigger, at date: Date) {
        guard trigger == .link || trigger == .inAppScan || trigger == .shortcut,
              let index = spots.firstIndex(where: { $0.id == spotID }) else { return }
        if spots[index].physical != nil {
            spots[index].physical?.lastScannedAt = date
        } else if spots[index].tag != nil {
            spots[index].tag?.lastScannedAt = date
        } else {
            return
        }
        persistence.saveSpots(spots)
    }

    // MARK: - History

    func sessions(for spotID: String) -> [SpotSession] {
        sessions.filter { $0.spotID == spotID }
    }

    func stats(for spotID: String) -> SpotStats {
        SpotInsights.stats(for: sessions, spotID: spotID)
    }

    var overallStats: SpotOverallStats {
        SpotInsights.overall(for: sessions)
    }

    // MARK: - Timers

    private func armEndTimer(for session: SpotSession) {
        endWorkItem?.cancel()
        let delay = max(0.5, session.plannedEndDate.timeIntervalSince(clock()))
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.reconcile() }
        }
        endWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func armRelockTimer(until date: Date) {
        relockWorkItem?.cancel()
        let delay = max(0.5, date.timeIntervalSince(clock()))
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.screenTime.reconcileShield(now: self.clock())
            }
        }
        relockWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.25, execute: item)
    }

    private func cancelTimers() {
        endWorkItem?.cancel()
        endWorkItem = nil
        relockWorkItem?.cancel()
        relockWorkItem = nil
    }
}
