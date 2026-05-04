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

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makePauseConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makePauseConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makePauseConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makePauseConfiguration()
    }

    private func makePauseConfiguration() -> ShieldConfiguration {
        let isCountingDown = countdownRemaining() > 0
        let hasActiveSession = isSessionActive()
        let needsMivoSetup = pendingInterventionSetup()

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1.0),
            icon: timerIcon(isCountingDown: isCountingDown, isLocked: !hasActiveSession),
            title: ShieldConfiguration.Label(
                text: shieldTitle(hasActiveSession: hasActiveSession, isCountingDown: isCountingDown, needsMivoSetup: needsMivoSetup),
                color: UIColor(red: 0.10, green: 0.11, blue: 0.10, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: shieldSubtitle(hasActiveSession: hasActiveSession, isCountingDown: isCountingDown, needsMivoSetup: needsMivoSetup),
                color: UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: hasActiveSession
                    ? (isCountingDown ? "Opening soon..." : "Start 5-second pause")
                    : (needsMivoSetup ? "Open Mivo" : "Start 5-second hold"),
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not now",
                color: UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1.0)
            )
        )
    }

    private func shieldTitle(hasActiveSession: Bool, isCountingDown: Bool, needsMivoSetup: Bool) -> String {
        if hasActiveSession {
            return isCountingDown ? "5-second pause running" : "Take a 5-second pause"
        }
        if needsMivoSetup {
            return "Open Mivo to set intervention"
        }
        return isCountingDown ? "Hold for 5 seconds" : "Pause before opening"
    }

    private func shieldSubtitle(hasActiveSession: Bool, isCountingDown: Bool, needsMivoSetup: Bool) -> String {
        if hasActiveSession {
            return isCountingDown
                ? "Breathe. The selected app will open when this reaches zero."
                : "Mivo is giving you a short moment to choose with intention. Press continue, breathe, then the app will open."
        }
        if needsMivoSetup {
            return "This selected app stays locked. Open Mivo now and it will take you straight to Interventions so you can choose why and set a time limit."
        }
        return isCountingDown
            ? "Keep holding. After this, Mivo will ask you to set the intervention before this app can open."
            : "Start the 5-second hold. Then open Mivo to choose your intention and time limit for this app."
    }

    private func countdownRemaining() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return 0 }
        let explicitRemaining = defaults.integer(forKey: countdownRemainingKey)
        if explicitRemaining > 0 {
            return explicitRemaining
        }

        let endTime = defaults.double(forKey: countdownUntilKey)
        guard endTime > 0 else { return 0 }
        return max(0, Int(ceil(endTime - Date().timeIntervalSince1970)))
    }

    private func isSessionActive() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.bool(forKey: sessionActiveKey) else {
            return false
        }

        let endsAt = defaults.double(forKey: sessionEndsAtKey)
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            defaults.set(false, forKey: sessionActiveKey)
            defaults.removeObject(forKey: sessionEndsAtKey)
            defaults.synchronize()
            return false
        }

        return true
    }

    private func pendingInterventionSetup() -> Bool {
        UserDefaults(suiteName: appGroup)?.bool(forKey: pendingInterventionSetupKey) == true
    }

    private func timerIcon(isCountingDown: Bool, isLocked: Bool) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            let circleRect = bounds.insetBy(dx: 7, dy: 7)
            let foreground = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1.0)
            let ring = UIColor(red: 0.77, green: 0.72, blue: 0.62, alpha: 1.0)
            let fill = UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0)

            fill.setFill()
            UIBezierPath(ovalIn: circleRect).fill()
            ring.setStroke()
            let ringPath = UIBezierPath(ovalIn: circleRect)
            ringPath.lineWidth = 6
            ringPath.stroke()

            if isLocked {
                drawLock(in: bounds, color: foreground)
            } else if isCountingDown {
                drawHourglass(in: bounds, color: foreground)
            } else {
                foreground.setFill()
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 42, weight: .semibold),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ]
                ("5" as NSString).draw(in: CGRect(x: 0, y: 22, width: size.width, height: 52), withAttributes: attributes)
            }
        }
    }

    private func drawLock(in bounds: CGRect, color: UIColor) {
        color.setStroke()
        let shackle = UIBezierPath()
        shackle.lineWidth = 5
        shackle.lineCapStyle = .round
        shackle.addArc(withCenter: CGPoint(x: bounds.midX, y: 43), radius: 17, startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.stroke()

        color.setFill()
        let body = UIBezierPath(roundedRect: CGRect(x: 27, y: 43, width: 42, height: 32), cornerRadius: 8)
        body.fill()

        UIColor.white.withAlphaComponent(0.88).setFill()
        UIBezierPath(ovalIn: CGRect(x: bounds.midX - 4, y: 54, width: 8, height: 8)).fill()
        UIBezierPath(roundedRect: CGRect(x: bounds.midX - 2, y: 60, width: 4, height: 9), cornerRadius: 2).fill()
    }

    private func drawHourglass(in bounds: CGRect, color: UIColor) {
        let centerX = bounds.midX
        let topY: CGFloat = 24
        let bottomY: CGFloat = 72
        let leftX: CGFloat = 31
        let rightX: CGFloat = 65
        let neckY = bounds.midY

        color.setStroke()
        let framePath = UIBezierPath()
        framePath.lineWidth = 5
        framePath.lineCapStyle = .round
        framePath.lineJoinStyle = .round
        framePath.move(to: CGPoint(x: leftX, y: topY))
        framePath.addLine(to: CGPoint(x: rightX, y: topY))
        framePath.move(to: CGPoint(x: leftX, y: bottomY))
        framePath.addLine(to: CGPoint(x: rightX, y: bottomY))
        framePath.move(to: CGPoint(x: leftX + 4, y: topY + 5))
        framePath.addLine(to: CGPoint(x: centerX, y: neckY))
        framePath.addLine(to: CGPoint(x: rightX - 4, y: bottomY - 5))
        framePath.move(to: CGPoint(x: rightX - 4, y: topY + 5))
        framePath.addLine(to: CGPoint(x: centerX, y: neckY))
        framePath.addLine(to: CGPoint(x: leftX + 4, y: bottomY - 5))
        framePath.stroke()

        color.withAlphaComponent(0.18).setFill()
        let topSand = UIBezierPath()
        topSand.move(to: CGPoint(x: leftX + 9, y: topY + 9))
        topSand.addLine(to: CGPoint(x: rightX - 9, y: topY + 9))
        topSand.addLine(to: CGPoint(x: centerX, y: neckY - 4))
        topSand.close()
        topSand.fill()

        color.withAlphaComponent(0.35).setFill()
        let bottomSand = UIBezierPath()
        bottomSand.move(to: CGPoint(x: centerX, y: neckY + 4))
        bottomSand.addLine(to: CGPoint(x: rightX - 10, y: bottomY - 9))
        bottomSand.addLine(to: CGPoint(x: leftX + 10, y: bottomY - 9))
        bottomSand.close()
        bottomSand.fill()

        color.setStroke()
        let streamPath = UIBezierPath()
        streamPath.lineWidth = 3
        streamPath.lineCapStyle = .round
        streamPath.move(to: CGPoint(x: centerX, y: neckY - 2))
        streamPath.addLine(to: CGPoint(x: centerX, y: neckY + 11))
        streamPath.stroke()
    }
}
