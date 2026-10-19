import SwiftUI

/// Renders the companion. Animation is sampled from a pure function of time, so
/// it costs nothing when it isn't visible, stops in the background, and falls
/// back to a still pose for Reduce Motion or when the person turned animations off.
struct CompanionFigureView: View {
    var type: CompanionType = .meerkat
    var state: CompanionState
    /// Plays a specific clip (previews). `nil` plays the state's own clip.
    var clip: CompanionAnimation?
    /// The person's "Animations" preference.
    var animated: Bool = true
    var stretchUnlocked: Bool = true
    /// Change this value to restart a one-shot clip.
    var playToken: Int = 0
    var accessibilityName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date()
    @State private var previousState: CompanionState?
    @State private var stateChangedAt = Date.distantPast

    private let transitionDuration: TimeInterval = 0.5

    private var shouldAnimate: Bool { animated && !reduceMotion && scenePhase == .active }

    private var frameInterval: TimeInterval {
        switch state {
        case .sleeping, .focused, .resting: return 1.0 / 10
        default: return 1.0 / 24
        }
    }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    CompanionArtworkRegistry.figure(type: type, state: state, pose: pose(at: timeline.date))
                }
            } else {
                CompanionArtworkRegistry.figure(type: type, state: state, pose: MeerkatMotion.staticPose(for: state))
            }
        }
        .onChange(of: state) { oldValue, _ in
            previousState = oldValue
            stateChangedAt = Date()
            epoch = Date()
        }
        .onChange(of: playToken) { _, _ in epoch = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let name = accessibilityName ?? type.defaultName
        return "\(name), your \(type.displayName.lowercased()) companion, \(state.label.lowercased())"
    }

    private func pose(at date: Date) -> MeerkatPose {
        let elapsed = date.timeIntervalSince(epoch)
        let activeClip = clip ?? state.defaultAnimation
        let current = MeerkatMotion.pose(state: state, clip: activeClip, elapsed: elapsed, stretchUnlocked: stretchUnlocked)
        guard let previousState else { return current }
        let sinceChange = date.timeIntervalSince(stateChangedAt)
        guard sinceChange < transitionDuration else { return current }
        let x = sinceChange / transitionDuration
        let eased = x * x * (3 - 2 * x)
        let previous = MeerkatMotion.pose(
            state: previousState, clip: previousState.defaultAnimation, elapsed: elapsed, stretchUnlocked: stretchUnlocked
        )
        return previous.blended(to: current, fraction: eased)
    }
}
