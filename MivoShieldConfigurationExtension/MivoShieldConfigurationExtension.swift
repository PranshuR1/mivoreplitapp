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
    private let pendingSetupFreshnessWindow: TimeInterval = 10 * 60

    // Brand colours (match Mivo's palette)
    private let cream        = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1.0)
    private let textPrimary  = UIColor(red: 0.10, green: 0.11, blue: 0.10, alpha: 1.0)
    private let textMuted    = UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1.0)
    private let btnLight     = UIColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1.0)
    private let btnBrown     = UIColor(red: 0.55, green: 0.31, blue: 0.16, alpha: 1.0) // #8C4F28

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let isCountingDown    = countdownRemaining() > 0
        let hasActiveSession  = isSessionActive()
        let needsMivoSetup    = pendingInterventionSetup() && !hasActiveSession
        let sessionExpired    = sessionExpiredAfterTimer()

        // ── 1. Counting down (highest priority — shown during pause) ──
        // No buttons: the countdown finishes on its own, then the glimpse + re-lock
        // happens automatically. The user just waits — there is nothing to tap.
        if isCountingDown {
            let n = countdownRemaining()
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .countdown),
                title: label(hasActiveSession ? "Pausing…  \(n)s" : "Pausing…  \(n)s", color: textPrimary),
                subtitle: label(
                    hasActiveSession
                        ? "Hang on. The app opens when the pause ends."
                        : "Wait for the pause to finish. This gives your mind a moment.",
                    color: textMuted
                ),
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

        // ── 3. Active session check-in ──
        if hasActiveSession {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialLight,
                backgroundColor: cream,
                icon: timerIcon(state: .timer),
                title: label("Pause to check in", color: textPrimary),
                subtitle: label(
                    "Your reminder interval is up. Tap Continue session for the 5-second pause, then Mivo will reopen this app.",
                    color: textMuted
                ),
                primaryButtonLabel: label("Not now", color: textMuted),
                primaryButtonBackgroundColor: btnLight,
                secondaryButtonLabel: label("Continue session", color: .white)
            )
        }

        // ── 4. Post-countdown "Open Mivo" screen ──
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

        // ── 5. Default — "Pause before opening" with Start button ──
        let pauseSecs = pauseDurationSeconds()
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: cream,
            icon: timerIcon(state: .timer),
            title: label("Pause before opening", color: textPrimary),
            subtitle: label(
                "Start the \(pauseSecs)-second pause to check your intention before this app opens.",
                color: textMuted
            ),
            primaryButtonLabel: label("Start", color: .white),
            primaryButtonBackgroundColor: btnBrown,
            secondaryButtonLabel: label("Not now", color: textMuted)
        )
    }

    // MARK: - Helpers

    private func label(_ text: String, color: UIColor) -> ShieldConfiguration.Label {
        ShieldConfiguration.Label(text: text, color: color)
    }

    private enum IconState { case timer, countdown, locked }

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
            case .locked:    drawLock(in: bounds, color: foreground)
            case .countdown: drawHourglass(in: bounds, color: foreground)
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
