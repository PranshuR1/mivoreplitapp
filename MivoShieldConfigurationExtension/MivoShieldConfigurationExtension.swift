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
        makeConfiguration(applicationToken: application.token)
    }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration(applicationToken: ApplicationToken? = nil) -> ShieldConfiguration {
        let isCountingDown    = countdownRemaining() > 0
        let hasActiveSession  = isSessionActive()
        let needsMivoSetup    = pendingInterventionSetup() && !hasActiveSession
        let sessionExpired    = sessionExpiredAfterTimer()

        // ── 1. Counting down (highest priority — shown during pause) ──
        // No buttons: the countdown finishes on its own. Every visible element
        // (icon, title, subtitle) changes each second so the user can see the
        // pause is actually progressing even when iOS is slow to re-render the
        // shield surface.
        if isCountingDown {
            let n = countdownRemaining()
            let total = pauseDurationSeconds()
            let elapsed = max(0, total - n)
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .countdown(remaining: n, total: total)),
                title: label(countdownTitle(remaining: n, total: total, isActiveSession: hasActiveSession), color: textPrimary),
                subtitle: label(progressDotsSubtitle(elapsed: elapsed, total: total, remaining: n), color: textMuted),
                primaryButtonLabel: nil,
                primaryButtonBackgroundColor: nil,
                secondaryButtonLabel: nil
            )
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
        // Single primary "Pause & continue" button starts a 5-second countdown that
        // automatically unlocks the app. No "Not now" option — the goal is a brief
        // mid-scroll moment of notice, not a wall.
        if hasActiveSession {
            let seconds = pauseDurationSeconds()
            let experimentPause = isExperimentActive() && experimentStrongerFriction()
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .timer),
                title: label(experimentPause ? "Experiment pause" : "Take a breath", color: textPrimary),
                subtitle: label(
                    "Quick \(seconds)-second pause, then back to scrolling. Tap to begin — Mivo unlocks the app on its own.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Pause & continue", color: .white),
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
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: cream,
            icon: timerIcon(state: .locked),
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
        /// `remaining` and `total` drive the progress ring + countdown digit so
        /// every tick draws a visibly different icon.
        case countdown(remaining: Int, total: Int)
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
            case .countdown(let remaining, let total):
                drawCountdownProgress(in: bounds, remaining: remaining, total: total, foreground: foreground)
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

    /// Title that visibly changes each tick — different verb per second, plus a
    /// monospaced digit so the redraw is obvious even when iOS lags.
    private func countdownTitle(remaining: Int, total: Int, isActiveSession: Bool) -> String {
        // Verb cycles by remaining seconds: gives the user something concrete to
        // notice every second so it feels alive even if iOS coalesces ticks.
        let verbs: [String]
        if isActiveSession {
            verbs = ["Almost there", "Easing back", "Settling", "Steady", "Breathing"]
        } else {
            verbs = ["One last beat", "Almost there", "Settling in", "Steady", "Breathing"]
        }
        // Pick verb by remaining (clamped). Higher remaining = earlier in pause.
        let idx = min(max(remaining - 1, 0), verbs.count - 1)
        let verb = verbs[idx]
        return "\(verb)  ·  \(remaining)s"
    }

    /// Progress dots that fill in left-to-right as the pause elapses. Even if
    /// the title text gets cached, the dots row changes shape every second.
    private func progressDotsSubtitle(elapsed: Int, total: Int, remaining: Int) -> String {
        let clampedTotal = min(max(total, 1), 10)
        let clampedElapsed = min(max(elapsed, 0), clampedTotal)
        let filled = String(repeating: "●", count: clampedElapsed)
        let empty = String(repeating: "○", count: max(0, clampedTotal - clampedElapsed))
        return "\(filled)\(empty)   \(remaining) second\(remaining == 1 ? "" : "s") left"
    }

    /// Draws an arc-style progress ring + large digit. `remaining`/`total` mean
    /// each tick paints a different arc length and a different number — iOS
    /// can't cache this to a single static image.
    private func drawCountdownProgress(in bounds: CGRect, remaining: Int, total: Int, foreground: UIColor) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 34
        let clampedTotal = max(total, 1)
        let progress = CGFloat(max(0, min(clampedTotal - remaining, clampedTotal))) / CGFloat(clampedTotal)
        // Background ring (dim)
        UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 0.55).setStroke()
        let bg = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        bg.lineWidth = 6
        bg.stroke()
        // Foreground arc — grows as the pause elapses.
        if progress > 0 {
            let startAngle = -CGFloat.pi / 2
            let endAngle = startAngle + (.pi * 2 * progress)
            let arc = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            arc.lineWidth = 6
            arc.lineCapStyle = .round
            foreground.setStroke()
            arc.stroke()
        }
        // Large monospaced digit so even the bitmap of the icon differs per tick.
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold),
            .foregroundColor: foreground,
            .paragraphStyle: para
        ]
        let text = "\(remaining)" as NSString
        text.draw(in: CGRect(x: 0, y: bounds.midY - 19, width: bounds.width, height: 36), withAttributes: attrs)
    }

    // MARK: - State readers

    private func countdownRemaining() -> Int {
        guard let d = UserDefaults(suiteName: appGroup) else { return 0 }
        let explicit = d.integer(forKey: countdownRemainingKey)
        if explicit > 0 { return explicit }
        let end = d.double(forKey: countdownUntilKey)
        guard end > 0 else { return 0 }
        return max(0, Int(ceil(end - Date().timeIntervalSince1970)))
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
