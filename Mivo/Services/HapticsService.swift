import SwiftUI
import UIKit

struct HapticsService {
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }

    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
    }

    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }

    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }
}
