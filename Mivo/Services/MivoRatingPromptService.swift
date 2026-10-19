import Foundation
import StoreKit
import UIKit

/// Persistence for the periodic "rate us / give feedback" card. Three rules,
/// each independent of the others:
///   - never shows more than once every two days
///   - reappears on that cadence until the user acts or explicitly stops it
///   - either rating or sending feedback counts as "acted" and stops it for good,
///     same as a dedicated "don't ask again" tap
enum MivoRatingPromptStore {
    private static let lastShownKey = "mivo.ratingPrompt.lastShownAt"
    private static let stoppedKey = "mivo.ratingPrompt.stoppedForever"
    private static let minimumGap: TimeInterval = 2 * 24 * 60 * 60

    private static var lastShownAt: Date? {
        get { UserDefaults.standard.object(forKey: lastShownKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastShownKey) }
    }

    private static var isStoppedForever: Bool {
        get { UserDefaults.standard.bool(forKey: stoppedKey) }
        set { UserDefaults.standard.set(newValue, forKey: stoppedKey) }
    }

    static func shouldShow(now: Date = Date()) -> Bool {
        guard !isStoppedForever else { return false }
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= minimumGap
    }

    /// Called the moment the card actually appears, so "every two days" is
    /// measured from when it was last shown, not when it was last acted on.
    static func markShown(now: Date = Date()) {
        lastShownAt = now
    }

    /// Rating, sending feedback, and the explicit "stop showing" control all
    /// call this — every one of them is a legitimate reason to stop.
    static func stopForever() {
        isStoppedForever = true
    }
}

@MainActor
enum MivoRatingPromptAction {
    /// `SKStoreReviewController` rather than a direct App Store link — Mivo's
    /// numeric App Store ID does not exist anywhere in this project (the app
    /// may not even be listed yet), and guessing one would risk linking to
    /// someone else's app. This needs no ID at all. The tradeoff: iOS decides
    /// whether the system prompt actually appears (it throttles repeat calls,
    /// capped around 3 times a year per Apple's own docs) — Mivo's own
    /// two-day cadence controls how often it's *asked for*, not whether iOS
    /// honors any given ask.
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}
