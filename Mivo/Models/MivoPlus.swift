import Foundation

/// Mivo Plus: everything except the basic pause. Pure value logic — no
/// StoreKit, no clock, no storage — so it can be unit tested.
/// `MivoPlusStore` talks to the App Store and persists the result.

/// The three App Store products. These ids must match App Store Connect and
/// `Mivo/Mivo.storekit`.
enum MivoPlusProductID {
    static let monthly = "app.mivo.plus.monthly"
    static let annual = "app.mivo.plus.annual"
    static let lifetime = "app.mivo.plus.lifetime"
    static let all = [annual, monthly, lifetime]
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
        case .annual: return 39.99
        case .monthly: return 6.99
        case .lifetime: return 79.99
        }
    }

    var fallbackPriceText: String { "$\(MivoPlusPricing.format(fallbackPrice))" }

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
    /// "52" for $39.99 a year against $6.99 a month.
    static func yearlySavingsPercent(monthly: Decimal, annual: Decimal) -> Int {
        let yearOfMonths = monthly * 12
        guard yearOfMonths > 0, annual < yearOfMonths else { return 0 }
        let saved = NSDecimalNumber(decimal: (yearOfMonths - annual) / yearOfMonths * 100).doubleValue
        return Int(saved.rounded())
    }

    /// The yearly price per month, e.g. 3.33 for $39.99.
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
            if purchase.productID == MivoPlusProductID.lifetime { return .lifetime }
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
        case .instagramInMivo: return "Instagram in Mivo, replay mode and dull mode are part of Mivo Plus."
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
        ("camera.viewfinder", "Instagram inside Mivo, with dull mode and a daily time limit"),
        ("sparkles", "Mivo Clear and Mivo Still"),
        ("flask", "Weekly experiments and your 30-day forecast"),
        ("doc.text", "Your attention receipt, every day")
    ]

    static let disclosure = "Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends, and you can manage or cancel them in Settings > Apple ID > Subscriptions. Lifetime is a one-time purchase."
}
