import Foundation

/// Reconciles "Block my iPhone too" commands the Mac companion app writes
/// to `cross_device_focus_sessions`. Implements
/// `mivomac/IPHONE_FOCUS_RECEIVER.md`'s spec against the app's existing
/// `FamilyControlsManager` rather than a new blocking mechanism:
///
/// - Reconciles on foreground and cold launch (see call sites in
///   `MivoApp.swift`, `MainTabView.swift`, `HomeView.swift`) rather than
///   relying solely on push delivery, which Apple doesn't guarantee.
/// - Applies/clears via `FamilyControlsManager`'s dedicated
///   `mivo.crossDeviceFocus` `ManagedSettingsStore`, so this can never
///   step on Mivo's own intervention or Still Lock shields.
/// - Never treats a command as permission to bypass Family Controls
///   authorization — it only re-applies the user's own existing
///   protected-apps selection (`loadFamilyActivitySelection()`), and does
///   nothing at all if Screen Time access was never granted.
/// - Always sets the shield state to match the command's presence/absence
///   directly, rather than tracking "did I apply it" in memory — an
///   in-memory flag doesn't survive the process being relaunched (which
///   happens routinely: background eviction, a crash, a fresh install), so
///   a shield applied by one process instance could never be cleared by a
///   later one that had no memory of applying it, leaving the phone
///   permanently locked after the Mac session had long since ended.
///   `ManagedSettingsStore` writes are idempotent, so unconditionally
///   applying/clearing on every reconcile has no downside.
@MainActor
final class CrossDeviceFocusService {
    static let shared = CrossDeviceFocusService()
    private init() {}

    func reconcile() async {
        guard #available(iOS 16.0, *) else { return }
        guard FamilyControlsManager.shared.liveAuthorizationStatus() else { return }
        guard let email = StorageService.load(String.self, forKey: .rememberedEmail),
              var record = SecureAuthService.loadRecord(email: email) else {
            FamilyControlsManager.shared.clearCrossDeviceFocusShield()
            return
        }

        // `fetchActiveCrossDeviceFocusCommand` uses whatever access token is
        // already cached and treats ANY failure — including a 401 from an
        // expired token — as "no active command" (see its doc comment: it's
        // an RLS-scoped read with no error surface). The access token is
        // otherwise only refreshed on cold launch
        // (`AppViewModel.validateActiveRemoteSessionIfNeeded`), so resuming
        // from background after the ~1hr token lifetime silently looked
        // identical to "Mac never asked to lock the phone." Refreshing here
        // first (self-healing, same pattern as `validateStoredSession`'s own
        // 401-then-refresh) means a stale token can't masquerade as an
        // absent command.
        if let remoteUser = try? await RemoteAuthService.validateStoredSession(record: record) {
            record.remoteAccessToken = remoteUser.accessToken ?? record.remoteAccessToken
            record.remoteRefreshToken = remoteUser.refreshToken ?? record.remoteRefreshToken
            try? SecureAuthService.saveRecord(record)
        }

        cacheCredentialsForExtension(record: record)

        let command = await RemoteAuthService.fetchActiveCrossDeviceFocusCommand(record: record)
        if let command {
            FamilyControlsManager.shared.applyCrossDeviceFocusShield(endsAt: command.endsAt)
        } else {
            FamilyControlsManager.shared.clearCrossDeviceFocusShield()
        }

        // Re-arm both background-discovery chains on every reconcile — cold
        // launch, foreground, or a previous firing — so they keep running
        // as long as the user opens the app at all, without needing a
        // dedicated "start the chain" call site. The BGAppRefreshTask is
        // kept as a second, independent fallback; the DeviceActivity poll
        // is the one that actually delivers reasonably-prompt discovery
        // while backgrounded/locked.
        FamilyControlsManager.shared.scheduleCrossDeviceFocusBackgroundCheck()
        FamilyControlsManager.shared.scheduleCrossDeviceFocusPoll()
    }

    /// The extension has no way to run `RemoteAuthService`'s own
    /// sign-in/token-refresh flow, so it authenticates with whatever the
    /// app last saw here — refreshed on every reconcile, meaning it's
    /// usually well within the token's ~1hr lifetime by the time the
    /// extension wakes.
    private func cacheCredentialsForExtension(record: SecureAuthRecord) {
        let defaults = UserDefaults(suiteName: "group.com.mivo.mivoapp")
        defaults?.set(record.remoteAccessToken, forKey: MivoScreenTimeKeys.crossDeviceFocusCachedAccessToken)
        defaults?.set(record.remoteUserId, forKey: MivoScreenTimeKeys.crossDeviceFocusCachedUserId)
        defaults?.synchronize()
    }
}
