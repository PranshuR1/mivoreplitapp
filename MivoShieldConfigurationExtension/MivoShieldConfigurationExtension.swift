import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class MivoShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let appGroup = "group.com.mivo.mivoapp"
    private let countdownUntilKey = "mivo.shieldCountdownUntil"
    private let countdownRemainingKey = "mivo.shieldCountdownRemaining"
    private let sessionActiveKey = "mivo.sessionActive"
    private let sessionEndsAtKey = "mivo.sessionEndsAt"
    private let pendingInterventionSetupKey = "mivo.pendingInterventionSetup"
    private let pendingInterventionSetupAtKey = "mivo.pendingInterventionSetupAt"
    private let sessionExpiredAtKey = "mivo.sessionExpiredAt"
    private let sessionExpiredSourceKey = "mivo.sessionExpiredSource"
    private let shieldPauseDurationKey = "mivo.shieldPauseDuration"
    private let experimentEnforcedKey = "mivo.experiment.enforced"
    private let experimentTypeKey = "mivo.experiment.type"
    private let experimentEndsAtKey = "mivo.experiment.endsAt"
    private let experimentStartHourKey = "mivo.experiment.startHour"
    private let experimentEndHourKey = "mivo.experiment.endHour"
    private let experimentStrongerFrictionKey = "mivo.experiment.strongerFriction"
    private let mivoClearMappingPrefix = "mivo.clear.mapping."
    private let mivoClearEnabledPrefix = "mivo.clear.enabled."
    private let pendingSetupFreshnessWindow: TimeInterval = 10 * 60
    private let stillLockActiveKey = "mivo.still.lock.active"
    private let stillLockEndsAtKey = "mivo.still.lock.endsAt"
    private let crossDeviceFocusActiveKey = "mivo.crossDeviceFocus.active"
    private let crossDeviceFocusEndsAtKey = "mivo.crossDeviceFocus.endsAt"

    // Brand colours (match Mivo's palette)
    private let cream        = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1.0)
    private let textPrimary  = UIColor(red: 0.10, green: 0.11, blue: 0.10, alpha: 1.0)
    private let textMuted    = UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1.0)
    private let btnLight     = UIColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1.0)
    private let btnBrown     = UIColor(red: 0.55, green: 0.31, blue: 0.16, alpha: 1.0) // #8C4F28

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(applicationToken: application.token)
    }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(applicationToken: application.token, categoryToken: category.token)
    }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(webDomainToken: webDomain.token)
    }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(categoryToken: category.token, webDomainToken: webDomain.token)
    }

    private func makeConfiguration(
        applicationToken: ApplicationToken? = nil,
        categoryToken: ActivityCategoryToken? = nil,
        webDomainToken: WebDomainToken? = nil
    ) -> ShieldConfiguration {
        let hasActiveSession  = isSessionActive()
        let needsMivoSetup    = pendingInterventionSetup() && !hasActiveSession
        let sessionExpired    = sessionExpiredAfterTimer()

        // ── 0. Mivo Still Lock Mode (overrides everything else) ──
        // No buttons — same "resolves on its own, nothing to tap" shape as
        // the countdown below. The timer is the only way this screen changes.
        if let remaining = stillLockRemainingMinutes() {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("Locked by Mivo Still", color: textPrimary),
                subtitle: label(
                    remaining > 0
                        ? "Every app is locked. \(remaining) minute\(remaining == 1 ? "" : "s") left."
                        : "Unlocking shortly.",
                    color: textMuted
                ),
                primaryButtonLabel: nil,
                primaryButtonBackgroundColor: nil,
                secondaryButtonLabel: nil
            )
        }

        // ── 0.5. Cross-device focus lock ("Block my iPhone too" from Mac) ──
        // No buttons, same shape as Still Lock above — only ending the
        // session on Mac clears this, so "Open Mivo" would be a dead end.
        if let remaining = crossDeviceFocusRemainingMinutes() {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("Focus mode on your Mac", color: textPrimary),
                subtitle: label(
                    remaining > 0
                        ? "Every app is locked while your Mac focus session runs. \(remaining) minute\(remaining == 1 ? "" : "s") left."
                        : "Unlocking shortly.",
                    color: textMuted
                ),
                primaryButtonLabel: nil,
                primaryButtonBackgroundColor: nil,
                secondaryButtonLabel: nil
            )
        }

        // ── 0.7. Lock-in ──
        // The person's own commitment to finish something. It shields only the apps
        // they chose for it, so this applies only when the tapped app (or its
        // category/site) belongs to the lock. Never a dead end: "Open Mivo" is where
        // they show Milo what they did.
        if let lock = lockInShield(application: applicationToken, category: categoryToken, webDomain: webDomainToken) {
            return lockInConfiguration(for: lock)
        }

        // ── 1. Mivo Spot ──
        // A running Spot shields only its own apps, so this applies only when the
        // tapped app (or its category/site) belongs to the Spot. Copy is calm and
        // never a dead end: every Spot shield has "Open Mivo", where the Spot can
        // be ended.
        if let spot = spotShield(application: applicationToken, category: categoryToken, webDomain: webDomainToken) {
            return spotConfiguration(for: spot)
        }

        // ── 2. Session expired ──
        if sessionExpired {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("App is restricted", color: textPrimary),
                subtitle: label(
                    "Your Mivo timer ended. Tap the notification above, or press Open Mivo below, to add time or save the session.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Open Mivo", color: .white),
                primaryButtonBackgroundColor: btnBrown,
                secondaryButtonLabel: nil
            )
        }

        // ── 3. Active session check-in (mid-scroll pause) ──
        // A ShieldActionDelegate extension is a short-lived service process
        // with no UI of its own, so it never runs its own countdown here —
        // the shield just points to Mivo, where a real Timer runs the pause
        // (see MidScrollCheckInView).
        if hasActiveSession {
            let experimentPause = isExperimentActive() && experimentStrongerFriction()
            let seconds = pauseDurationSeconds()
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .timer),
                title: label(experimentPause ? "Experiment pause" : "Check-in time", color: textPrimary),
                subtitle: label(
                    "Open Mivo for your \(seconds)-second timer before you're let back in.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Open Mivo", color: .white),
                primaryButtonBackgroundColor: btnBrown,
                secondaryButtonLabel: nil
            )
        }

        // ── 4. Approved protected-window experiment ──
        if isProtectedExperimentHour() {
            if let applicationToken, let clearPlatform = mappedMivoClearPlatform(for: applicationToken) {
                return ShieldConfiguration(
                    backgroundBlurStyle: .systemUltraThinMaterialLight,
                    backgroundColor: cream,
                    icon: timerIcon(state: .locked),
                    title: label("This hour is protected", color: textPrimary),
                    subtitle: label(
                        "Your approved 7-day experiment keeps the native app locked \(protectedExperimentWindowText()). Mivo Clear stays available.",
                        color: textMuted
                    ),
                    primaryButtonLabel: label("Use Mivo Clear", color: .white),
                    primaryButtonBackgroundColor: btnBrown,
                    secondaryButtonLabel: label("Open Mivo", color: textMuted)
                )
            }

            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("This hour is protected", color: textPrimary),
                subtitle: label(
                    "Your approved 7-day experiment keeps this app locked \(protectedExperimentWindowText()).",
                    color: textMuted
                ),
                primaryButtonLabel: label("Open Mivo", color: .white),
                primaryButtonBackgroundColor: btnBrown,
                secondaryButtonLabel: label("Not now", color: textMuted)
            )
        }

        // ── 5. "Open Mivo" session-setup screen ──
        if needsMivoSetup {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("Open Mivo", color: textPrimary),
                subtitle: label(
                    "Tap the notification above to open Mivo. If you do not see it, press Open Mivo below and tap the notification that appears.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Open Mivo", color: .white),
                primaryButtonBackgroundColor: btnBrown,
                secondaryButtonLabel: nil
            )
        }

        if let applicationToken, let clearPlatform = mappedMivoClearPlatform(for: applicationToken) {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .locked),
                title: label("Open \(clearPlatform.title) with less noise", color: textPrimary),
                subtitle: label(
                    "Use the focused tools in Mivo Clear, or start a timed session in the native app.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Use Mivo Clear", color: .white),
                primaryButtonBackgroundColor: btnBrown,
                secondaryButtonLabel: label("Start timed session", color: textMuted)
            )
        }

        // ── 6. Default — route to Mivo; the pause follows intention selection ──
        // With Companion on, the character stands in for the lock glyph on this
        // everyday shield only; every restricted/locked state above keeps the lock.
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: cream,
            icon: companionPortrait() ?? timerIcon(state: .locked),
            title: label("Open Mivo", color: textPrimary),
            subtitle: label(
                "Set your intention and time in Mivo. This app stays locked until the pause is complete and your session starts.",
                color: textMuted
            ),
            primaryButtonLabel: label("Open Mivo", color: .white),
            primaryButtonBackgroundColor: btnBrown,
            secondaryButtonLabel: label("Not now", color: textMuted)
        )
    }

    // MARK: - Lock-in

    /// The running lock, if it covers what was tapped.
    private func lockInShield(
        application: ApplicationToken?,
        category: ActivityCategoryToken?,
        webDomain: WebDomainToken?
    ) -> LockInLiveState? {
        let defaults = UserDefaults(suiteName: LockInKeys.appGroup)
        guard let live = LockInLiveState.read(from: defaults),
              let data = defaults?.data(forKey: LockInKeys.liveSelection),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return nil }
        if let application, selection.applicationTokens.contains(application) { return live }
        if let category, selection.categoryTokens.contains(category) { return live }
        if let webDomain, selection.webDomainTokens.contains(webDomain) { return live }
        return nil
    }

    private func lockInConfiguration(for lock: LockInLiveState) -> ShieldConfiguration {
        let task = lock.task.count > 60 ? String(lock.task.prefix(57)) + "…" : lock.task
        let minutes = lock.minutesLeft()
        let timeLeft = minutes >= 60
            ? "about \(minutes / 60) hr\(minutes >= 120 ? "s" : "")"
            : "\(minutes) min"
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: cream,
            icon: timerIcon(state: .locked),
            title: label("Locked in", color: textPrimary),
            subtitle: label(
                task.isEmpty
                    ? "Show Milo what you did to unlock this. The lock ends in \(timeLeft) at the latest."
                    : "“\(task)”. Show Milo what you did to unlock this. The lock ends in \(timeLeft) at the latest.",
                color: textMuted
            ),
            primaryButtonLabel: label("Open Mivo", color: .white),
            primaryButtonBackgroundColor: btnBrown,
            secondaryButtonLabel: label("Not now", color: textMuted)
        )
    }

    // MARK: - Mivo Spots

    /// The running Spot, if it wants a shield right now and covers what was tapped.
    private func spotShield(
        application: ApplicationToken?,
        category: ActivityCategoryToken?,
        webDomain: WebDomainToken?
    ) -> SpotLiveState? {
        let defaults = UserDefaults(suiteName: SpotKeys.appGroup)
        guard let live = SpotLiveState.read(from: defaults), live.wantsShield(),
              let data = defaults?.data(forKey: SpotKeys.liveSelection),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return nil }
        if let application, selection.applicationTokens.contains(application) { return live }
        if let category, selection.categoryTokens.contains(category) { return live }
        if let webDomain, selection.webDomainTokens.contains(webDomain) { return live }
        return nil
    }

    private func spotConfiguration(for spot: SpotLiveState) -> ShieldConfiguration {
        let minutesLeft = max(1, Int(ceil(spot.endsAt.timeIntervalSinceNow / 60)))
        let title: String
        let subtitle: String
        let primary: String
        switch spot.mode {
        case .pause:
            title = "\(spot.name) is on"
            subtitle = "Take a breath first. Open Mivo for a short pause, then decide."
            primary = "Open Mivo"
        case .focus:
            title = "Focus at \(spot.name)"
            subtitle = "\(minutesLeft) min left. You can end this Spot any time from Mivo."
            primary = "Open Mivo"
        case .intention:
            title = "What did you come here to do?"
            subtitle = "One quick answer in Mivo, and \(spot.name) won't ask again."
            primary = "Answer in Mivo"
        case .awareness:
            title = "\(spot.name) is on"
            subtitle = "Open Mivo to see this Spot."
            primary = "Open Mivo"
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: cream,
            icon: timerIcon(state: .timer),
            title: label(title, color: textPrimary),
            subtitle: label(subtitle, color: textMuted),
            primaryButtonLabel: label(primary, color: .white),
            primaryButtonBackgroundColor: btnBrown,
            secondaryButtonLabel: label("Not now", color: textMuted)
        )
    }

    // MARK: - Helpers

    private func label(_ text: String, color: UIColor) -> ShieldConfiguration.Label {
        ShieldConfiguration.Label(text: text, color: color)
    }

    private func mappedMivoClearPlatform(for token: ApplicationToken) -> ClearPlatform? {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        for platform in ClearPlatform.allCases {
            guard defaults.bool(forKey: mivoClearEnabledPrefix + platform.rawValue) else { continue }
            guard let data = defaults.data(forKey: mivoClearMappingPrefix + platform.rawValue),
                  let mapped = try? JSONDecoder().decode(ApplicationToken.self, from: data) else { continue }
            if mapped == token { return platform }
        }
        return nil
    }

    private enum ClearPlatform: String, CaseIterable {
        case instagram, tiktok, youtube, snapchat

        var title: String {
            switch self {
            case .instagram: return "Instagram"
            case .tiktok: return "TikTok"
            case .youtube: return "YouTube"
            case .snapchat: return "Snapchat"
            }
        }
    }

    private enum IconState {
        case timer
        case locked
    }

    /// The badge the app renders into the App Group while Companion is on (see
    /// `CompanionPortraitRenderer`). A shield can only display a bitmap, so this
    /// just reads the file; it is `nil` — and the lock icon is used — whenever
    /// Companion is off or the shared container isn't reachable.
    private func companionPortrait() -> UIImage? {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("mivo-companion-portrait.png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data, scale: 3)
    }

    private func timerIcon(state: IconState) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            let circleRect = bounds.insetBy(dx: 7, dy: 7)
            let foreground = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1.0)
            let ring       = UIColor(red: 0.77, green: 0.72, blue: 0.62, alpha: 1.0)
            let fill       = UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0)
            fill.setFill(); UIBezierPath(ovalIn: circleRect).fill()
            ring.setStroke()
            let rp = UIBezierPath(ovalIn: circleRect); rp.lineWidth = 6; rp.stroke()
            switch state {
            case .locked:
                drawLock(in: bounds, color: foreground)
            case .timer:
                let n = pauseDurationSeconds()
                let fontSize: CGFloat = n >= 10 ? 34 : 42
                let yOffset: CGFloat = n >= 10 ? 26 : 22
                let para = NSMutableParagraphStyle(); para.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: foreground, .paragraphStyle: para
                ]
                ("\(n)" as NSString).draw(in: CGRect(x: 0, y: yOffset, width: size.width, height: 52), withAttributes: attrs)
            }
        }
    }

    // MARK: - State readers

    /// Returns remaining whole minutes if a Lock Mode block is active and not
    /// yet past its end time, nil otherwise. Does not self-clear the flag —
    /// that's the extension's `intervalDidStart`/`intervalDidEnd` job; this
    /// is read-only, matching how the other state readers here work.
    private func stillLockRemainingMinutes() -> Int? {
        guard let d = UserDefaults(suiteName: appGroup), d.bool(forKey: stillLockActiveKey) else { return nil }
        let endsAt = d.double(forKey: stillLockEndsAtKey)
        guard endsAt > Date().timeIntervalSince1970 else { return nil }
        return max(0, Int(ceil((endsAt - Date().timeIntervalSince1970) / 60)))
    }

    /// Set by `FamilyControlsManager.applyCrossDeviceFocusShield(endsAt:)`
    /// whenever `CrossDeviceFocusService.reconcile()` finds an active "Block
    /// my iPhone too" command from Mac. Same shape as `stillLockRemainingMinutes`.
    private func crossDeviceFocusRemainingMinutes() -> Int? {
        guard let d = UserDefaults(suiteName: appGroup), d.bool(forKey: crossDeviceFocusActiveKey) else { return nil }
        let endsAt = d.double(forKey: crossDeviceFocusEndsAtKey)
        guard endsAt > Date().timeIntervalSince1970 else { return nil }
        return max(0, Int(ceil((endsAt - Date().timeIntervalSince1970) / 60)))
    }

    private func pauseDurationSeconds() -> Int {
        guard let d = UserDefaults(suiteName: appGroup) else { return 5 }
        let stored = d.integer(forKey: shieldPauseDurationKey)
        guard stored > 0 else { return 5 }
        return min(max(stored, 3), 30)
    }

    private func isExperimentActive() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.bool(forKey: experimentEnforcedKey) else { return false }
        let endsAt = defaults.double(forKey: experimentEndsAtKey)
        return endsAt <= 0 || endsAt > Date().timeIntervalSince1970
    }

    private func experimentStrongerFriction() -> Bool {
        guard isExperimentActive(),
              let defaults = UserDefaults(suiteName: appGroup) else { return false }
        return defaults.bool(forKey: experimentStrongerFrictionKey)
    }

    private func isProtectedExperimentHour() -> Bool {
        guard isExperimentActive(),
              let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: experimentTypeKey) == "protected_window" else { return false }
        let start = normalizedHour(defaults.integer(forKey: experimentStartHourKey))
        let end = normalizedHour(defaults.integer(forKey: experimentEndHourKey))
        let current = Calendar.current.component(.hour, from: Date())
        if start == end { return true }
        return start < end
            ? (current >= start && current < end)
            : (current >= start || current < end)
    }

    private func protectedExperimentWindowText() -> String {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return "during this hour" }
        let start = normalizedHour(defaults.integer(forKey: experimentStartHourKey))
        let end = normalizedHour(defaults.integer(forKey: experimentEndHourKey))
        return "from \(hourText(start)) to \(hourText(end))"
    }

    private func normalizedHour(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }

    private func hourText(_ hour: Int) -> String {
        let normalized = normalizedHour(hour)
        if normalized == 0 { return "12 AM" }
        if normalized == 12 { return "12 PM" }
        return normalized < 12 ? "\(normalized) AM" : "\(normalized - 12) PM"
    }

    private func isSessionActive() -> Bool {
        guard let d = UserDefaults(suiteName: appGroup), d.bool(forKey: sessionActiveKey) else { return false }
        let endsAt = d.double(forKey: sessionEndsAtKey)
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            let now = Date().timeIntervalSince1970
            d.set(false, forKey: sessionActiveKey)
            d.removeObject(forKey: sessionEndsAtKey)
            d.set(true, forKey: pendingInterventionSetupKey)
            d.set(now, forKey: pendingInterventionSetupAtKey)
            d.set(now, forKey: sessionExpiredAtKey)
            d.set("session-end", forKey: sessionExpiredSourceKey)
            d.removeObject(forKey: countdownUntilKey)
            d.removeObject(forKey: countdownRemainingKey)
            d.synchronize()
            return false
        }
        return true
    }

    private func sessionExpiredAfterTimer() -> Bool {
        guard let d = UserDefaults(suiteName: appGroup) else { return false }
        if d.double(forKey: sessionExpiredAtKey) > 0 {
            let src = d.string(forKey: sessionExpiredSourceKey) ?? ""
            return ["session-end","usage-limit","app-recovery","app-foreground-recovery",
                    "mivo-app","shield-action-state-check","shield-configuration-state-check"].contains(src)
        }
        let endsAt = d.double(forKey: sessionEndsAtKey)
        return endsAt > 0 && endsAt < Date().timeIntervalSince1970
    }

    private func pendingInterventionSetup() -> Bool {
        guard let d = UserDefaults(suiteName: appGroup), d.bool(forKey: pendingInterventionSetupKey) else { return false }
        let createdAt = d.double(forKey: pendingInterventionSetupAtKey)
        guard createdAt > 0 else { clearStalePending(d); return false }
        if Date().timeIntervalSince1970 - createdAt > pendingSetupFreshnessWindow { clearStalePending(d); return false }
        return true
    }

    private func clearStalePending(_ d: UserDefaults) {
        d.set(false, forKey: pendingInterventionSetupKey)
        d.removeObject(forKey: pendingInterventionSetupAtKey)
        d.removeObject(forKey: countdownUntilKey)
        d.removeObject(forKey: countdownRemainingKey)
        d.synchronize()
    }

    // MARK: - Icon drawing

    private func drawLock(in bounds: CGRect, color: UIColor) {
        color.setStroke()
        let shackle = UIBezierPath(); shackle.lineWidth = 5; shackle.lineCapStyle = .round
        shackle.addArc(withCenter: CGPoint(x: bounds.midX, y: 43), radius: 17,
                       startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.stroke()
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: 27, y: 43, width: 42, height: 32), cornerRadius: 8).fill()
        UIColor.white.withAlphaComponent(0.88).setFill()
        UIBezierPath(ovalIn: CGRect(x: bounds.midX - 4, y: 54, width: 8, height: 8)).fill()
        UIBezierPath(roundedRect: CGRect(x: bounds.midX - 2, y: 60, width: 4, height: 9), cornerRadius: 2).fill()
    }

    private func drawHourglass(in bounds: CGRect, color: UIColor) {
        let cx = bounds.midX, topY: CGFloat = 24, botY: CGFloat = 72
        let lx: CGFloat = 31, rx: CGFloat = 65, ny = bounds.midY
        color.setStroke()
        let fp = UIBezierPath(); fp.lineWidth = 5; fp.lineCapStyle = .round; fp.lineJoinStyle = .round
        fp.move(to: CGPoint(x: lx, y: topY)); fp.addLine(to: CGPoint(x: rx, y: topY))
        fp.move(to: CGPoint(x: lx, y: botY)); fp.addLine(to: CGPoint(x: rx, y: botY))
        fp.move(to: CGPoint(x: lx+4, y: topY+5)); fp.addLine(to: CGPoint(x: cx, y: ny)); fp.addLine(to: CGPoint(x: rx-4, y: botY-5))
        fp.move(to: CGPoint(x: rx-4, y: topY+5)); fp.addLine(to: CGPoint(x: cx, y: ny)); fp.addLine(to: CGPoint(x: lx+4, y: botY-5))
        fp.stroke()
        color.withAlphaComponent(0.18).setFill()
        let ts = UIBezierPath(); ts.move(to: CGPoint(x: lx+9, y: topY+9)); ts.addLine(to: CGPoint(x: rx-9, y: topY+9)); ts.addLine(to: CGPoint(x: cx, y: ny-4)); ts.close(); ts.fill()
        color.withAlphaComponent(0.35).setFill()
        let bs = UIBezierPath(); bs.move(to: CGPoint(x: cx, y: ny+4)); bs.addLine(to: CGPoint(x: rx-10, y: botY-9)); bs.addLine(to: CGPoint(x: lx+10, y: botY-9)); bs.close(); bs.fill()
        color.setStroke()
        let sp = UIBezierPath(); sp.lineWidth = 3; sp.lineCapStyle = .round
        sp.move(to: CGPoint(x: cx, y: ny-2)); sp.addLine(to: CGPoint(x: cx, y: ny+11)); sp.stroke()
    }
}
