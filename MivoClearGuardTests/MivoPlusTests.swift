import XCTest
@testable import Mivo

final class MivoPlusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testProductIDsAreStable() {
        XCTAssertEqual(MivoPlusPlan.annual.productID, "app.mivo.plus.annual")
        XCTAssertEqual(MivoPlusPlan.monthly.productID, "app.mivo.plus.monthly")
        XCTAssertEqual(MivoPlusPlan.lifetime.productID, "app.mivo.plus.lifetime")
        XCTAssertEqual(Set(MivoPlusProductID.all).count, 3)
    }

    func testFallbackPrices() {
        XCTAssertEqual(MivoPlusPlan.monthly.fallbackPriceText, "$6.99")
        XCTAssertEqual(MivoPlusPlan.annual.fallbackPriceText, "$39.99")
        XCTAssertEqual(MivoPlusPlan.lifetime.fallbackPriceText, "$79.99")
    }

    func testYearlySavings() {
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 6.99, annual: 39.99), 52)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 4.99, annual: 29.99), 50)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 1, annual: 12), 0)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 1, annual: 20), 0)
        XCTAssertEqual(MivoPlusPricing.yearlySavingsPercent(monthly: 0, annual: 20), 0)
    }

    func testMonthlyEquivalentOfAnnual() {
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

    func testAccessForPlusAndAdmins() {
        XCTAssertTrue(MivoPlusAccess.allows(isPlus: true, isAdmin: false))
        XCTAssertTrue(MivoPlusAccess.allows(isPlus: false, isAdmin: true))
        XCTAssertFalse(MivoPlusAccess.allows(isPlus: false, isAdmin: false))
    }

    func testEveryLockedFeatureHasAReasonAndTheBasicPauseStaysFree() {
        for feature in [PlusFeature.instagramInMivo, .mivoClear, .mivoStill, .experiments, .receipt, .forecast, .general] {
            XCTAssertFalse(feature.lockedLine.isEmpty)
        }
        XCTAssertTrue(MivoPlusCopy.basicPauseLine.contains("free"))
        XCTAssertFalse(MivoPlusCopy.benefits.isEmpty)
    }
}
