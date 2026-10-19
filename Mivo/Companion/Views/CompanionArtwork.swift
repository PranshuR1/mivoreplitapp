import SwiftUI
import UIKit

/// The single place that turns (character, state) into pixels.
///
/// Replacing the placeholder vector art with production artwork needs no code:
/// add images to Assets.xcassets named `companion_<type>_<state>` (for example
/// `companion_meerkat_sleeping`) and they are used automatically for that
/// state. A state with no image keeps using the vector figure. To animate a
/// different way (Lottie, Rive), change `figure` here and nothing else.
@MainActor
enum CompanionArtworkRegistry {
    private static var imageCache: [String: UIImage?] = [:]

    @ViewBuilder
    static func figure(type: CompanionType, state: CompanionState, pose: MeerkatPose) -> some View {
        if let image = customImage(type: type, state: state) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                // Only the breathing delta, so supplied stills don't feel frozen
                // without being squashed into this state's vector posture.
                .scaleEffect(y: 1 + pose.bodyStretch - MeerkatMotion.staticPose(for: state).bodyStretch, anchor: .bottom)
        } else {
            switch type {
            case .meerkat:
                MeerkatCanvas(pose: pose)
            }
        }
    }

    private static func customImage(type: CompanionType, state: CompanionState) -> UIImage? {
        let name = "companion_\(type.rawValue)_\(state.rawValue)"
        if let cached = imageCache[name] { return cached }
        let image = UIImage(named: name)
        imageCache[name] = .some(image)
        return image
    }
}
