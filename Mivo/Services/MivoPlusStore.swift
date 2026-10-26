import Foundation
import StoreKit

/// Mivo Plus on the App Store: loads the three products, buys and restores
/// them, and keeps `entitlement` current from the person's real purchases.
/// The last answer is cached so Plus still works offline.
@MainActor
final class MivoPlusStore: ObservableObject {
    static let shared = MivoPlusStore()

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case restoring
        case failed(String)
    }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var entitlement: PlusEntitlement
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var productsUnavailable = false
    @Published private(set) var annualHasFreeTrial = false
    /// False until the App Store has answered once this launch, so the app
    /// never strips Plus on the strength of an empty answer it hasn't got yet.
    @Published private(set) var hasCheckedPurchases = false

    private static let entitlementKey = "mivo.plus.entitlement"
    private let defaults: UserDefaults
    private var started = false
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entitlement = defaults.data(forKey: Self.entitlementKey)
            .flatMap { try? JSONDecoder().decode(PlusEntitlement.self, from: $0) } ?? .none
    }

    var isPlus: Bool {
        entitlement.isActive(at: Date()) || debugUnlocked
    }

    var isLifetime: Bool { entitlement == .lifetime }

    #if DEBUG
    /// Debug builds only: launch with `-MivoPlusForce` to see Plus without buying it.
    private var debugUnlocked: Bool {
        ProcessInfo.processInfo.arguments.contains("-MivoPlusForce")
    }
    #else
    private var debugUnlocked: Bool { false }
    #endif

    /// Starts listening for purchases and loads products. Safe to call again.
    func start() {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func product(for plan: MivoPlusPlan) -> Product? {
        products[plan.productID]
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: MivoPlusProductID.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            productsUnavailable = loaded.isEmpty
            if let subscription = products[MivoPlusProductID.annual]?.subscription,
               subscription.introductoryOffer?.paymentMode == .freeTrial {
                annualHasFreeTrial = await subscription.isEligibleForIntroOffer
            } else {
                annualHasFreeTrial = false
            }
        } catch {
            productsUnavailable = true
        }
    }

    func refreshEntitlement() async {
        var purchases: [PlusEntitlement.Purchase] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            purchases.append(PlusEntitlement.Purchase(
                productID: transaction.productID,
                expiresAt: transaction.expirationDate,
                isRevoked: transaction.revocationDate != nil
            ))
        }
        entitlement = PlusEntitlement.from(purchases)
        if let data = try? JSONEncoder().encode(entitlement) {
            defaults.set(data, forKey: Self.entitlementKey)
        }
        hasCheckedPurchases = true
    }

    /// Returns true when the person ends up with Plus.
    @discardableResult
    func purchase(_ plan: MivoPlusPlan) async -> Bool {
        guard let product = product(for: plan) else {
            purchaseState = .failed("Prices aren't available right now. Check your connection and try again.")
            await loadProducts()
            return false
        }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseState = .failed("The App Store couldn't verify that purchase.")
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                purchaseState = .idle
                return isPlus
            case .userCancelled:
                purchaseState = .idle
                return false
            case .pending:
                purchaseState = .failed("Your purchase is waiting for approval. Plus unlocks once it's approved.")
                return false
            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            purchaseState = .failed("The purchase didn't go through. You weren't charged.")
            return false
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseState = isPlus ? .idle : .failed("No Mivo Plus purchase was found for this Apple ID.")
        } catch {
            purchaseState = .failed("Couldn't reach the App Store. Try again in a moment.")
        }
    }

    func clearFailure() {
        if case .failed = purchaseState { purchaseState = .idle }
    }
}
