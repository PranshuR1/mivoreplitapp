import Foundation

/// Remembers when the five-minute Plus discount ends, so closing the app or
/// reopening the paywall never gives a fresh five minutes.
@MainActor
final class MivoPlusOffer: ObservableObject {
    static let shared = MivoPlusOffer()

    private static let deadlineKey = "mivo.plus.offer.deadline"
    private let defaults: UserDefaults

    @Published private(set) var deadline: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deadline = (defaults.object(forKey: Self.deadlineKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
    }

    var hasStarted: Bool { deadline != nil }

    func phase(at now: Date = Date()) -> MivoPlusOfferClock.Phase {
        MivoPlusOfferClock.phase(deadline: deadline, now: now)
    }

    /// Starts the countdown once. Returns false when it already ran.
    @discardableResult
    func startIfNeeded(now: Date = Date()) -> Bool {
        guard deadline == nil else { return false }
        let end = now.addingTimeInterval(MivoPlusOfferClock.duration)
        defaults.set(end.timeIntervalSince1970, forKey: Self.deadlineKey)
        deadline = end
        return true
    }

    #if DEBUG
    /// Debug previews only: forget the countdown so the offer can be seen again.
    func resetForPreview() {
        defaults.removeObject(forKey: Self.deadlineKey)
        deadline = nil
    }
    #endif
}
