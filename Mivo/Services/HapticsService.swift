import SwiftUI
import UIKit

struct HapticsService {
    /// A subtle response for ordinary taps. The short delay lets a more meaningful
    /// selection, success, warning, or error response take priority for the same tap.
    static func tap() {
        HapticFeedbackCoordinator.shared.scheduleTap()
    }

    static func success() {
        performExplicitFeedback {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
        }
    }

    static func warning() {
        performExplicitFeedback {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.warning)
        }
    }

    static func error() {
        performExplicitFeedback {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.error)
        }
    }

    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        performExplicitFeedback {
            let strongerStyle: UIImpactFeedbackGenerator.FeedbackStyle = style == .light ? .medium : style
            let gen = UIImpactFeedbackGenerator(style: strongerStyle)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
        }
    }

    static func selection() {
        performExplicitFeedback {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
        }
    }

    /// Strong, closely spaced feedback used only by the first-install story.
    /// Keeping it separate prevents the rest of Mivo's controls from becoming noisy.
    static func firstLaunchTypingBeat() {
        performExplicitFeedback {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 1.0)
        }
    }

    static func firstLaunchEmphasis() {
        performExplicitFeedback {
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.prepare()
            heavy.impactOccurred(intensity: 1.0)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                let rigid = UIImpactFeedbackGenerator(style: .rigid)
                rigid.prepare()
                rigid.impactOccurred(intensity: 1.0)
            }
        }
    }

    private static func performExplicitFeedback(_ feedback: @escaping () -> Void) {
        let work = {
            HapticFeedbackCoordinator.shared.noteExplicitFeedback()
            feedback()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

private final class HapticFeedbackCoordinator {
    static let shared = HapticFeedbackCoordinator()

    private var lastExplicitFeedbackTime: TimeInterval = -.infinity
    private var lastTapFeedbackTime: TimeInterval = -.infinity

    private init() {}

    func scheduleTap() {
        let schedule = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime

                // Do not stack the global tap vibration on top of a specific response.
                guard now - self.lastExplicitFeedbackTime > 0.12,
                      now - self.lastTapFeedbackTime > 0.04 else { return }

                self.lastTapFeedbackTime = now
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred(intensity: 1.0)
            }
        }

        if Thread.isMainThread {
            schedule()
        } else {
            DispatchQueue.main.async(execute: schedule)
        }
    }

    func noteExplicitFeedback() {
        lastExplicitFeedbackTime = ProcessInfo.processInfo.systemUptime
    }
}
