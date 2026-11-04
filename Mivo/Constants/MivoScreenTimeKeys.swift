import Foundation

enum MivoSessionState: String, Codable {
    case idle
    case pendingSetup
    case active
    case expiredAwaitingChoice
    case finished
}

enum MivoSessionExpirationSource: String, Codable {
    case sessionEnd = "session-end"
    case leaseEnd = "lease-end"
    case appRecovery = "app-recovery"
    case manualFinish = "manual-finish"
    /// The user said no to "still want to keep scrolling?" at a mid-session
    /// check-in, rather than the check-in simply timing out.
    case midScrollDeclined = "mid-scroll-declined"
    case unknown
}

enum SessionStartError: Error, Equatable, Identifiable {
    case screenTimeUnavailable
    case schedulingFailed(String)
    case noTimeRemaining

    var id: String { message }

    var message: String {
        switch self {
        case .screenTimeUnavailable:
            return "Screen Time blocker is not available on this device."
        case .schedulingFailed(let detail):
            return "Screen Time blocker could not start. \(detail)"
        case .noTimeRemaining:
            return "There is no approved time remaining."
        }
    }
}

enum MivoScreenTimeKeys {
    static let appGroup = "group.com.mivo.mivoapp"
    static let shieldStoreName = "mivo.intervention"
    static let studyFocusStore = "mivo.studyFocus"
    static let studyFocusEndActivity = "mivo.studyFocus.end"
    static let studyFocusEndsAt = "mivo.studyFocus.endsAt"

    static let familyActivitySelection = "mivo.familyActivitySelection"
    static let impulseProtectionEnabled = "mivo.impulseProtectionEnabled"
    static let impulseProtectionSignedIn = "mivo.impulseProtectionSignedIn"
    static let learningModeUnlocked = "mivo.learningModeUnlocked"
    static let sessionActive = "mivo.sessionActive"
    static let sessionEndsAt = "mivo.sessionEndsAt"
    static let pendingInterventionSetup = "mivo.pendingInterventionSetup"
    static let pendingInterventionSetupAt = "mivo.pendingInterventionSetupAt"
    static let shieldCountdownUntil = "mivo.shieldCountdownUntil"
    static let shieldCountdownRemaining = "mivo.shieldCountdownRemaining"
    static let checkInIntervalMinutes = "mivo.checkInIntervalMinutes"
    /// How many seconds the "Start" pause lasts before the glimpse. Default 5. Range 3–30.
    static let shieldPauseDuration = "mivo.shieldPauseDuration"
    static let experimentEnforced = "mivo.experiment.enforced"
    static let experimentType = "mivo.experiment.type"
    static let experimentTitle = "mivo.experiment.title"
    static let experimentEndsAt = "mivo.experiment.endsAt"
    static let experimentStartHour = "mivo.experiment.startHour"
    static let experimentEndHour = "mivo.experiment.endHour"
    static let experimentBlocksExtensions = "mivo.experiment.blocksExtensions"
    static let experimentStrongerFriction = "mivo.experiment.strongerFriction"
    static let mivoClearMappingPrefix = "mivo.clear.mapping."
    static let mivoClearEnabledPrefix = "mivo.clear.enabled."
    static let pendingMivoClearPlatform = "mivo.clear.pendingPlatform"
    static let pendingMivoClearEntryPoint = "mivo.clear.pendingEntryPoint"

    /// Set by the ShieldAction extension's `requestMidScrollCheckIn()` when
    /// the primary shield button is tapped during an already-active session —
    /// the app reads this on foreground and shows a short breathing pause
    /// followed by a real "still want to keep scrolling?" decision, rather
    /// than the countdown that used to (unreliably) run inside the extension.
    static let pendingMidScrollCheckIn = "mivo.pendingMidScrollCheckIn"
    /// Best-effort `Application(token:).localizedDisplayName` written
    /// alongside `pendingMidScrollCheckIn`, read once by `checkMidScrollCheckInFlag()`.
    /// Can be absent — Apple doesn't guarantee this name is populated.
    static let pendingMidScrollCheckInAppName = "mivo.pendingMidScrollCheckInAppName"

    /// Whether tapping a chosen social app opens it inside Mivo
    /// (`AppWrapperView`, via the window flow) instead of the normal
    /// intervention flow. On by default since 2026-11-02 (a missing key means
    /// on). The key name predates every app opening in Mivo; Instagram was first.
    /// See `FamilyControlsManager.isInstagramWrapperEnabled`.
    static let instagramWrapperEnabled = "mivo.instagramWrapperEnabled"
    /// Instagram's `ApplicationToken`, saved by the ShieldConfiguration
    /// extension (where `bundleIdentifier` is filled in) so the ShieldAction
    /// extension, which only sees the opaque token, can recognise Instagram.
    static let instagramShieldToken = "mivo.instagramShieldToken"
    /// Set by older ShieldAction builds for Instagram; still read once.
    static let pendingInstagramWrapper = "mivo.pendingInstagramWrapper"
    /// Set by the ShieldAction extension's `requestAppWindow(_:)` to the
    /// tapped app's `SocialApp` raw value; read once on foreground.
    static let pendingAppWindow = "mivo.pendingAppWindow"
    /// Each app's `ApplicationToken`, picked once in Settings, so the shield
    /// extensions (which only see opaque tokens) know which app was tapped.
    /// Followed by the `SocialApp` raw value.
    static let appMappingPrefix = "mivo.app.mapping."
    /// Instagram's real iOS bundle identifier — used to identify the shielded
    /// app without requiring the user to map it first (unlike Mivo Clear,
    /// which is deliberately per-app-opt-in).
    static let instagramBundleID = "com.burbn.instagram"
    static let stillLockActive = "mivo.still.lock.active"
    static let stillLockEndsAt = "mivo.still.lock.endsAt"
    static let stillLockPlannedMinutes = "mivo.still.lock.plannedMinutes"
    static let stillLockActivityName = "mivo.still.lock"
    static let stillLockBGTaskIdentifier = "com.mivo.mivoapp.stilllockend"

    /// Mirrors `stillLockActive`/`stillLockEndsAt` for "Block my iPhone
    /// too" — set by `FamilyControlsManager.applyCrossDeviceFocusShield()`
    /// so `MivoShieldConfigurationExtension` can show "Focus mode on your
    /// Mac" instead of falling through to the generic "Open Mivo" default,
    /// which made no sense here since opening Mivo can't end a session only
    /// the Mac controls.
    static let crossDeviceFocusActive = "mivo.crossDeviceFocus.active"
    static let crossDeviceFocusEndsAt = "mivo.crossDeviceFocus.endsAt"
    /// DeviceActivity name scheduled at the command's `endsAt` whenever the
    /// shield is applied, so iOS reliably clears it (via the monitor
    /// extension) even if Mivo is never reopened after the Mac session
    /// ends — otherwise a shield applied while backgrounded/foregrounded
    /// once could stay orphaned forever. Mirrors `stillLockActivityName`.
    static let crossDeviceFocusActivityName = "mivo.crossDeviceFocus.clear"
    /// Best-effort background discovery: since there is no push channel
    /// yet for "Mac just started a session," this BGAppRefreshTask is the
    /// only way the phone can pick one up while the app isn't foregrounded.
    /// iOS schedules it opportunistically — not a guarantee, just a chain
    /// that keeps re-arming itself alongside every reconcile.
    static let crossDeviceFocusBGTaskIdentifier = "com.mivo.mivoapp.crossdevicefocus"
    /// Self-rearming DeviceActivity alarm that actually discovers a new
    /// Mac-side command while the app is backgrounded/killed — unlike the
    /// BGAppRefreshTask above (opportunistic, no minimum latency guarantee,
    /// can silently not fire for hours on an idle/locked phone),
    /// `MivoDeviceActivityMonitorExtension` is woken reliably for this the
    /// same way it already reliably re-locks/unlocks Still Lock and session
    /// leases — because DeviceActivityMonitor wakes are a Screen-Time-class
    /// system service, not ordinary background app refresh.
    static let crossDeviceFocusPollActivityName = "mivo.crossDeviceFocus.poll"
    /// Bearer token + user id `CrossDeviceFocusService.reconcile()` caches
    /// here on every successful foreground/poll cycle so the extension
    /// (which has no way to run the app's own token-refresh flow) has
    /// something to authenticate with when it wakes on its own. A stale
    /// cached token just means one poll cycle sees "no command" — no worse
    /// than the extension not running at all, and it's naturally refreshed
    /// the next time the app is foregrounded.
    static let crossDeviceFocusCachedAccessToken = "mivo.crossDeviceFocus.cachedAccessToken"
    static let crossDeviceFocusCachedUserId = "mivo.crossDeviceFocus.cachedUserId"

    /// "Always block drifting apps" — a Home-screen commitment toggle,
    /// distinct from Still Lock: it shields the user's own protected-apps
    /// selection (not every category), and once armed it stays on until
    /// local midnight regardless of what the user does in the app — there
    /// is deliberately no "turn off early" path once `alwaysBlockDriftActive`
    /// is true for today's date.
    static let alwaysBlockDriftActive = "mivo.alwaysBlockDrift.active"
    static let alwaysBlockDriftArmedDate = "mivo.alwaysBlockDrift.armedDate"
    static let alwaysBlockDriftActivityName = "mivo.alwaysBlockDrift.clear"

    static let sessionExpiredAt = "mivo.sessionExpiredAt"
    static let sessionExpiredSource = "mivo.sessionExpiredSource"
    static let lastShieldSource = "mivo.lastShieldSource"
    static let lastScheduleError = "mivo.lastScheduleError"

    static let sessionLeaseStartedAt = "mivo.sessionLeaseStartedAt"
    static let sessionLeaseEndsAt = "mivo.sessionLeaseEndsAt"
    static let sessionLeaseDurationSeconds = "mivo.sessionLeaseDurationSeconds"
    static let leaseMonitorScheduledAt = "mivo.leaseMonitorScheduledAt"
    static let leaseMonitorDidStartAt = "mivo.leaseMonitorDidStartAt"
    static let leaseMonitorDidEndAt = "mivo.leaseMonitorDidEndAt"

    static let sessionMonitorScheduledAt = "mivo.sessionMonitorScheduledAt"
    static let sessionMonitorDidStartAt = "mivo.sessionMonitorDidStartAt"
    static let sessionMonitorDidEndAt = "mivo.sessionMonitorDidEndAt"
    static let lastSessionMonitorCallback = "mivo.lastSessionMonitorCallback"

    static let sessionRelockActivityName = "mivo.session.relock"
    static let sessionUsageLimitEventName = "mivo.session.usageLimit"
    // Backup watcher: interval starts now, ends at session-end time.
    // intervalDidEnd fires at session end as a second trigger point.
    static let sessionEndWatcherActivityName = "mivo.session.endwatcher"
    static let sessionEndWatcherUsageLimitEventName = "mivo.session.endwatcher.usageLimit"
    static let leaseEnforcementActivityName = "mivo.lease.enforcement"
    static let blockerSelfTestActivityName = "mivo.blocker.selftest"

    static let defaultCheckInIntervalMinutes = 3
    static let defaultLeaseSeconds: TimeInterval = TimeInterval(defaultCheckInIntervalMinutes * 60)
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
