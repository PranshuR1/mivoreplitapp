import Foundation
import StoreKit
import UIKit

/// When the "leave a review / give feedback" card shows. Pure, so it can be
/// unit tested; `MivoRatingPromptStore` keeps the dates.
///   - never more than once a day
///   - keeps coming back until the person opens the review page
///   - opening the review page stops it until the next app version
///   - "Not now" and sending feedback only wait for the next day
enum MivoRatingPromptRules {
    static let minimumGap: TimeInterval = 24 * 60 * 60

    static func shouldShow(lastShownAt: Date?, reviewedVersion: String?, currentVersion: String, now: Date) -> Bool {
        guard reviewedVersion != currentVersion else { return false }
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= minimumGap
    }
}

/// Builds before 3.1 stopped the card for good on any tap; that flag
/// (`mivo.ratingPrompt.stoppedForever`) is no longer read.
enum MivoRatingPromptStore {
    private static let lastShownKey = "mivo.ratingPrompt.lastShownAt"
    private static let reviewedVersionKey = "mivo.ratingPrompt.reviewedVersion"

    private static var defaults: UserDefaults { .standard }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func shouldShow(now: Date = Date()) -> Bool {
        MivoRatingPromptRules.shouldShow(
            lastShownAt: defaults.object(forKey: lastShownKey) as? Date,
            reviewedVersion: defaults.string(forKey: reviewedVersionKey),
            currentVersion: currentVersion,
            now: now
        )
    }

    /// Called the moment the card actually appears, so "once a day" is
    /// measured from when it was last shown, not when it was last acted on.
    static func markShown(now: Date = Date()) {
        defaults.set(now, forKey: lastShownKey)
    }

    /// The person opened the review page for this version.
    static func markReviewed() {
        defaults.set(currentVersion, forKey: reviewedVersionKey)
    }
}

@MainActor
enum MivoRatingPromptAction {
    /// Mivo's App Store listing ("Mivo Scrolling", checked live 2026-11-02).
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6762094544?action=write-review")!

    /// Opens the App Store's write-a-review page. Unlike the system prompt,
    /// which iOS shows at most three times a year, this works every time.
    static func openWriteReview() {
        MivoRatingPromptStore.markReviewed()
        UIApplication.shared.open(writeReviewURL)
    }

    /// The in-app system prompt, for happy moments. iOS decides whether it
    /// actually appears (about three times a year at most), so nothing
    /// depends on it showing.
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        AppStore.requestReview(in: scene)
    }
}
