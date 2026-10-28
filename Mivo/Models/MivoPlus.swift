import Foundation

/// Mivo Plus: everything except the basic pause. Pure value logic — no
/// StoreKit, no clock, no storage — so it can be unit tested.
/// `MivoPlusStore` talks to the App Store and persists the result.

/// The App Store products. These ids must match App Store Connect and
/// `Mivo/Mivo.storekit`. Each plan has a regular product and an `.offer` twin
/// at the limited-time price: the App Store only charges what App Store
/// Connect says, so the discount has to be its own product.
enum MivoPlusProductID {
    static let monthly = "app.mivo.plus.monthly"
    static let annual = "app.mivo.plus.annual"
    static let lifetime = "app.mivo.plus.lifetime"
    static let monthlyOffer = "app.mivo.plus.monthly.offer"
    static let annualOffer = "app.mivo.plus.annual.offer"
    static let lifetimeOffer = "app.mivo.plus.lifetime.offer"
    static let regular = [annual, monthly, lifetime]
    static let offers = [annualOffer, monthlyOffer, lifetimeOffer]
    static let all = regular + offers
    static let lifetimeIDs: Set<String> = [lifetime, lifetimeOffer]
}

enum MivoPlusPlan: String, CaseIterable, Identifiable {
    case annual
    case monthly
    case lifetime

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .annual: return MivoPlusProductID.annual
        case .monthly: return MivoPlusProductID.monthly
        case .lifetime: return MivoPlusProductID.lifetime
        }
    }

    var offerProductID: String {
        switch self {
        case .annual: return MivoPlusProductID.annualOffer
        case .monthly: return MivoPlusProductID.monthlyOffer
        case .lifetime: return MivoPlusProductID.lifetimeOffer
        }
    }

    func productID(offer: Bool) -> String { offer ? offerProductID : productID }

    var title: String {
        switch self {
        case .annual: return "Yearly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    /// US dollars, shown only until the App Store returns the real local price.
    var fallbackPrice: Decimal {
        switch self {
        case .annual: return 49.99
        case .monthly: return 9.99
        case .lifetime: return 99.99
        }
    }

    /// The limited-time price, in US dollars, with the same fallback rule.
    var fallbackOfferPrice: Decimal {
        switch self {
        case .annual: return 39.99
        case .monthly: return 6.99
        case .lifetime: return 79.99
        }
    }

    var fallbackPriceText: String { "$\(MivoPlusPricing.format(fallbackPrice))" }

    var fallbackOfferPriceText: String { "$\(MivoPlusPricing.format(fallbackOfferPrice))" }

    /// What the price covers, e.g. "per year".
    var period: String {
        switch self {
        case .annual: return "per year"
        case .monthly: return "per month"
        case .lifetime: return "one time"
        }
    }

    var isSubscription: Bool { self != .lifetime }
}

enum MivoPlusPricing {
    /// "58" for $49.99 a year against $9.99 a month.
    static func yearlySavingsPercent(monthly: Decimal, annual: Decimal) -> Int {
        let yearOfMonths = monthly * 12
        guard yearOfMonths > 0, annual < yearOfMonths else { return 0 }
        let saved = NSDecimalNumber(decimal: (yearOfMonths - annual) / yearOfMonths * 100).doubleValue
        return Int(saved.rounded())
    }

    /// "30" for $6.99 against $9.99. Zero when the offer isn't cheaper.
    static func percentOff(regular: Decimal, offer: Decimal) -> Int {
        guard regular > 0, offer < regular else { return 0 }
        let off = NSDecimalNumber(decimal: (regular - offer) / regular * 100).doubleValue
        return Int(off.rounded())
    }

    /// The yearly price per month, e.g. 4.17 for $49.99.
    static func monthlyEquivalent(ofAnnual annual: Decimal) -> Decimal {
        var value = annual / 12
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }

    static func format(_ price: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: price).doubleValue)
    }
}

/// The one-time discount that opens the first time someone closes the
/// paywall. It runs for five minutes from that moment and never restarts.
enum MivoPlusOfferClock {
    static let duration: TimeInterval = 5 * 60

    enum Phase: Equatable {
        case notStarted
        case running(remaining: TimeInterval)
        case expired
    }

    static func phase(deadline: Date?, now: Date) -> Phase {
        guard let deadline else { return .notStarted }
        let remaining = deadline.timeIntervalSince(now)
        return remaining > 0 ? .running(remaining: remaining) : .expired
    }

    /// "04:59". Rounds up so the display never shows 00:00 while time is left.
    static func format(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// What the person has paid for, kept so the app still knows offline.
enum PlusEntitlement: Codable, Equatable {
    case none
    case subscription(until: Date)
    case lifetime

    func isActive(at date: Date) -> Bool {
        switch self {
        case .none: return false
        case .subscription(let until): return until > date
        case .lifetime: return true
        }
    }

    struct Purchase {
        let productID: String
        let expiresAt: Date?
        let isRevoked: Bool
    }

    /// The best entitlement across the person's current App Store purchases.
    static func from(_ purchases: [Purchase]) -> PlusEntitlement {
        var best = PlusEntitlement.none
        for purchase in purchases where !purchase.isRevoked && MivoPlusProductID.all.contains(purchase.productID) {
            if MivoPlusProductID.lifetimeIDs.contains(purchase.productID) { return .lifetime }
            guard let expiry = purchase.expiresAt else { continue }
            if case .subscription(let current) = best, current >= expiry { continue }
            best = .subscription(until: expiry)
        }
        return best
    }
}

/// Who gets Plus features.
enum MivoPlusAccess {
    /// Admin accounts are the team's own, so they are never locked out of
    /// what they are building.
    static func allows(isPlus: Bool, isAdmin: Bool) -> Bool {
        isPlus || isAdmin
    }
}

/// The features behind Plus, with the line shown when one is tapped.
enum PlusFeature: String, Identifiable {
    case instagramInMivo
    case mivoClear
    case mivoStill
    case experiments
    case receipt
    case forecast
    case general

    var id: String { rawValue }

    var lockedLine: String {
        switch self {
        case .instagramInMivo: return "Replay mode is part of Mivo Plus."
        case .mivoClear: return "Mivo Clear is part of Mivo Plus."
        case .mivoStill: return "Mivo Still is part of Mivo Plus."
        case .experiments: return "Weekly experiments are part of Mivo Plus."
        case .receipt: return "Your attention receipt is part of Mivo Plus."
        case .forecast: return "The 30-day forecast is part of Mivo Plus."
        case .general: return "Mivo Plus unlocks everything beyond the basic pause."
        }
    }
}

enum MivoPlusCopy {
    static let basicPauseLine = "The 5-second pause on your protected apps stays free."

    static let benefits: [(icon: String, text: String)] = [
        ("repeat", "Replay mode: after your reels, only ones you've seen"),
        ("sparkles", "Mivo Clear and Mivo Still"),
        ("flask", "Weekly experiments and your 30-day forecast"),
        ("doc.text", "Your attention receipt, every day")
    ]

    static let disclosure = "Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends, and you can manage or cancel them in Settings > Apple ID > Subscriptions. Lifetime is a one-time purchase."
}
