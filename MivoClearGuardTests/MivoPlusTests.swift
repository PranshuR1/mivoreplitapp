import XCTest
@testable import Mivo

final class MivoPlusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testProductIDsAreStable() {
        XCTAssertEqual(MivoPlusPlan.annual.productID, "app.mivo.plus.annual")
        XCTAssertEqual(MivoPlusPlan.monthly.productID, "app.mivo.plus.monthly")
        XCTAssertEqual(MivoPlusPlan.lifetime.productID, "app.mivo.plus.lifetime")
        XCTAssertEqual(Set(MivoPlusProductID.all).count, 6)
        XCTAssertEqual(MivoPlusPlan.annual.offerProductID, "app.mivo.plus.annual.offer")
        XCTAssertEqual(MivoPlusPlan.monthly.offerProductID, "app.mivo.plus.monthly.offer")
        XCTAssertEqual(MivoPlusPlan.lifetime.offerProductID, "app.mivo.plus.lifetime.offer")
        XCTAssertEqual(MivoPlusPlan.annual.productID(offer: true), MivoPlusProductID.annualOffer)
        XCTAssertEqual(MivoPlusPlan.annual.productID(offer: false), MivoPlusProductID.annual)
    }

    func testFallbackPrices() {
        XCTAssertEqual(MivoPlusPlan.monthly.fallbackPriceText, "$9.99")
        XCTAssertEqual(MivoPlusPlan.annual.fallbackPriceText, "$49.99")
        XCTAssertEqual(MivoPlusPlan.lifetime.fallbackPriceText, "$99.99")
    }

    func testOfferPrices() {
        XCTAssertEqual(MivoPlusPlan.monthly.fallbackOfferPriceText, "$6.99")
        XCTAssertEqual(MivoPlusPlan.annual.fallbackOfferPriceText, "$39.99")
        XCTAssertEqual(MivoPlusPlan.lifetime.fallbackOfferPriceText, "$79.99")
    }

    func testPercentOff() {
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 9.99, offer: 6.99), 30)
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 49.99, offer: 39.99), 20)
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 99.99, offer: 79.99), 20)
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 10, offer: 10), 0)
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 10, offer: 12), 0)
        XCTAssertEqual(MivoPlusPricing.percentOff(regular: 0, offer: 0), 0)
    }

    func testOfferClock() {
        let deadline = now.addingTimeInterval(MivoPlusOfferClock.duration)
        XCTAssertEqual(MivoPlusOfferClock.phase(deadline: nil, now: now), .notStarted)
        XCTAssertEqual(MivoPlusOfferClock.phase(deadline: deadline, now: now), .running(remaining: 300))
        XCTAssertEqual(MivoPlusOfferClock.phase(deadline: deadline, now: now.addingTimeInterval(299)), .running(remaining: 1))
        XCTAssertEqual(MivoPlusOfferClock.phase(deadline: deadline, now: deadline), .expired)
        XCTAssertEqual(MivoPlusOfferClock.phase(deadline: deadline, now: deadline.addingTimeInterval(60)), .expired)
    }

    func testOfferClockFormat() {
        XCTAssertEqual(MivoPlusOfferClock.format(300), "05:00")
        XCTAssertEqual(MivoPlusOfferClock.format(299.2), "05:00")
        XCTAssertEqual(MivoPlusOfferClock.format(65), "01:05")
        XCTAssertEqual(MivoPlusOfferClock.format(0.4), "00:01")
        XCTAssertEqual(MivoPlusOfferClock.format(0), "00:00")
        XCTAssertEqual(MivoPlusOfferClock.format(-5), "00:00")
    }

    @MainActor
    func testOfferStartsOnceAndSurvivesRelaunch() {
        let suite = "mivo.plus.offer.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = MivoPlusOffer(defaults: defaults)
        XCTAssertEqual(first.phase(at: now), .notStarted)
        XCTAssertTrue(first.startIfNeeded(now: now))
        XCTAssertFalse(first.startIfNeeded(now: now.addingTimeInterval(120)))
        XCTAssertEqual(first.phase(at: now.addingTimeInterval(120)), .running(remaining: 180))

        let relaunched = MivoPlusOffer(defaults: defaults)
        XCTAssertEqual(relaunched.phase(at: now.addingTimeInterval(120)), .running(remaining: 180))
        XCTAssertFalse(relaunched.startIfNeeded(now: now.addingTimeInterval(400)))
        XCTAssertEqual(relaunched.phase(at: now.addingTimeInterval(400)), .expired)
    }

    func testYearlySavings() {
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 9.99, annual: 49.99), 58)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 6.99, annual: 39.99), 52)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 4.99, annual: 29.99), 50)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 1, annual: 12), 0)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 1, annual: 20), 0)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 0, annual: 20), 0)
    }

    func testMonthlyEquivalentOfAnnual() {
        XCTAssertEqual(MivoPlusPricing.monthlyEquivalent(ofAnnual: 49.99), 4.17)
        XCTAssertEqual(MivoPlusPricing.monthlyEquivalent(ofAnnual: 39.99), 3.33)
        XCTAssertEqual(MivoPlusPricing.format(3.33), "3.33")
        XCTAssertEqual(MivoPlusPricing.format(80), "80.00")
    }

    func testSubscriptionIsActiveUntilItExpires() {
        let entitlement = PlusEntitlement.subscription(until: now.addingTimeInterval(3600))
        XCTAssertTrue(entitlement.isActive(at: now))
        XCTAssertFalse(entitlement.isActive(at: now.addingTimeInterval(3601)))
    }

    func testLifetimeNeverExpiresAndNoneIsNeverActive() {
        XCTAssertTrue(PlusEntitlement.lifetime.isActive(at: now.addingTimeInterval(86_400 * 3650)))
        XCTAssertFalse(PlusEntitlement.none.isActive(at: now))
    }

    func testDiscountedLifetimeIsLifetime() {
        let offerLifetime = PlusEntitlement.Purchase(productID: MivoPlusProductID.lifetimeOffer, expiresAt: nil, isRevoked: false)
        let offerAnnual = PlusEntitlement.Purchase(productID: MivoPlusProductID.annualOffer, expiresAt: now.addingTimeInterval(9000), isRevoked: false)
        XCTAssertEqual(PlusEntitlement.from([offerLifetime]), .lifetime)
        XCTAssertEqual(PlusEntitlement.from([offerAnnual]), .subscription(until: now.addingTimeInterval(9000)))
    }

    func testEntitlementFromPurchases() {
        let soon = now.addingTimeInterval(1000), later = now.addingTimeInterval(9000)
        let monthly = PlusEntitlement.Purchase(productID: MivoPlusProductID.monthly, expiresAt: soon, isRevoked: false)
        let annual = PlusEntitlement.Purchase(productID: MivoPlusProductID.annual, expiresAt: later, isRevoked: false)
        let lifetime = PlusEntitlement.Purchase(productID: MivoPlusProductID.lifetime, expiresAt: nil, isRevoked: false)

        XCTAssertEqual(PlusEntitlement.from([]), .none)
        XCTAssertEqual(PlusEntitlement.from([monthly]), .subscription(until: soon))
        XCTAssertEqual(PlusEntitlement.from([monthly, annual]), .subscription(until: later))
        XCTAssertEqual(PlusEntitlement.from([annual, monthly]), .subscription(until: later))
        XCTAssertEqual(PlusEntitlement.from([monthly, lifetime, annual]), .lifetime)
    }

    func testRevokedAndUnknownPurchasesGiveNothing() {
        let revoked = PlusEntitlement.Purchase(productID: MivoPlusProductID.annual, expiresAt: now.addingTimeInterval(1000), isRevoked: true)
        let other = PlusEntitlement.Purchase(productID: "app.mivo.spot", expiresAt: now.addingTimeInterval(1000), isRevoked: false)
        let noExpiry = PlusEntitlement.Purchase(productID: MivoPlusProductID.monthly, expiresAt: nil, isRevoked: false)
        XCTAssertEqual(PlusEntitlement.from([revoked, other, noExpiry]), .none)
    }

    func testEntitlementSurvivesEncodeDecode() throws {
        for entitlement in [PlusEntitlement.none, .lifetime, .subscription(until: now)] {
            let decoded = try JSONDecoder().decode(PlusEntitlement.self, from: JSONEncoder().encode(entitlement))
            XCTAssertEqual(decoded, entitlement)
        }
    }

    func testPostOnboardingPaywallIsRememberedPerAccountUntilCleared() {
        let suite = "PostOnboardingPaywallTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let flag = PostOnboardingPaywall(defaults: defaults)

        XCTAssertFalse(flag.isDue(account: "a@example.com"))
        flag.markDue(account: "A@example.com")
        XCTAssertTrue(flag.isDue(account: "a@EXAMPLE.com"))
        XCTAssertFalse(flag.isDue(account: "b@example.com"))

        flag.clear(account: "a@example.com")
        XCTAssertFalse(flag.isDue(account: "a@example.com"))
    }

    func testAccessForPlusAndAdmins() {
        XCTAssertTrue(MivoPlusAccess.allows(isPlus: true, isAdmin: false))
        XCTAssertTrue(MivoPlusAccess.allows(isPlus: false, isAdmin: true))
        XCTAssertFalse(MivoPlusAccess.allows(isPlus: false, isAdmin: false))
    }

    func testEveryLockedFeatureHasAReasonAndTheBasicPauseStaysFree() {
        for feature in [PlusFeature.studyScroll, .instagramInMivo, .mivoClear, .mivoStill, .experiments, .receipt, .forecast, .general] {
            XCTAssertFalse(feature.lockedLine.isEmpty)
        }
        XCTAssertTrue(MivoPlusCopy.basicPauseLine.contains("free"))
        XCTAssertFalse(MivoPlusCopy.benefits.isEmpty)
    }
}
