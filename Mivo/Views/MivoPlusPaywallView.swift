import SwiftUI
import StoreKit

/// The Mivo Plus paywall. `feature` is the locked thing the person just
/// tapped, so the first line says why they're here. With Plus already active
/// it shows their plan and where to manage it.
struct MivoPlusPaywallView: View {
    var feature: PlusFeature? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var store = MivoPlusStore.shared
    @State private var selected: MivoPlusPlan = .annual
    @State private var showingManage = false

    private var hasPlus: Bool {
        MivoPlusAccess.allows(isPlus: store.isPlus, isAdmin: appVM.isAdminUser)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if hasPlus {
                        activePlanCard
                    } else {
                        benefits
                        planList
                        purchaseButton
                        restoreAndLegal
                    }
                }
                .padding(.horizontal, MivoMetrics.tabPadding)
                .padding(.top, 56)
                .padding(.bottom, 32)
                .mivoReadableWidth()
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.inkBody)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MivoColors.ink.opacity(0.08)))
            }
            .accessibilityLabel("Close")
            .padding(.top, 14)
            .padding(.trailing, 16)
        }
        .task {
            store.start()
            await store.loadProducts()
        }
        .onChange(of: store.isPlus) { _, nowPlus in
            if nowPlus && feature != nil { dismiss() }
        }
        .manageSubscriptionsSheet(isPresented: $showingManage)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mivo Plus")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text(feature?.lockedLine ?? PlusFeature.general.lockedLine)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
            Text(MivoPlusCopy.basicPauseLine)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
        }
    }

    private var benefits: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(MivoPlusCopy.benefits, id: \.text) { benefit in
                    HStack(alignment: .top, spacing: 12) {
                        MivoIconTile(systemName: benefit.icon, size: 30)
                        Text(benefit.text)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(MivoColors.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(MivoPlusPlan.allCases) { plan in
                planRow(plan)
            }
            if store.productsUnavailable {
                HStack(spacing: 8) {
                    Text("Prices aren't loading. Check your connection.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await store.loadProducts() } }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func planRow(_ plan: MivoPlusPlan) -> some View {
        let isSelected = plan == selected
        return Button {
            HapticsService.selection()
            selected = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? MivoColors.accent : MivoColors.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        if let badge = badge(for: plan) {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MivoColors.accent))
                        }
                    }
                    Text(detail(for: plan))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(priceText(for: plan))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text(plan.period)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous)
                    .fill(MivoColors.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous)
                    .stroke(isSelected ? MivoColors.accent : MivoColors.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            if store.purchaseState == .purchasing || store.purchaseState == .restoring {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: MivoMetrics.buttonHeight)
            } else {
                MivoPrimaryButton(label: purchaseLabel, disabled: store.product(for: selected) == nil) {
                    Task { await store.purchase(selected) }
                }
            }

            if let finePrint = purchaseFinePrint {
                Text(finePrint)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .multilineTextAlignment(.center)
            }

            if case .failed(let message) = store.purchaseState {
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var restoreAndLegal: some View {
        VStack(spacing: 12) {
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(MivoColors.deep)
            .disabled(store.purchaseState == .purchasing || store.purchaseState == .restoring)

            Text(MivoPlusCopy.disclosure)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                if let terms = URL(string: "https://usemivo.app/terms") {
                    Link("Terms", destination: terms)
                }
                if let privacy = URL(string: "https://usemivo.app/privacy") {
                    Link("Privacy", destination: privacy)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(MivoColors.deep)
        }
        .frame(maxWidth: .infinity)
    }

    private var activePlanCard: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundColor(MivoColors.kept)
                    Text("You have Mivo Plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                }
                Text(activePlanDetail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)

                if !store.isLifetime && store.isPlus {
                    Button("Manage subscription") { showingManage = true }
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.deep)
                }
            }
        }
    }

    // MARK: - Text

    private var activePlanDetail: String {
        switch store.entitlement {
        case .lifetime:
            return "Lifetime. It's yours for good."
        case .subscription(let until):
            return "Renews or ends on \(until.formatted(date: .abbreviated, time: .omitted)). Cancel anytime in Apple ID settings."
        case .none:
            return "This account has Plus access."
        }
    }

    private func priceText(for plan: MivoPlusPlan) -> String {
        store.product(for: plan)?.displayPrice ?? plan.fallbackPriceText
    }

    private func badge(for plan: MivoPlusPlan) -> String? {
        switch plan {
        case .annual:
            let percent = MivoPlusPricing.yearlySavingsPercent(monthly: price(.monthly), annual: price(.annual))
            return percent > 0 ? "Save \(percent)%" : "Best value"
        case .lifetime:
            return "Pay once"
        case .monthly:
            return nil
        }
    }

    private func detail(for plan: MivoPlusPlan) -> String {
        switch plan {
        case .annual:
            let perMonth = MivoPlusPricing.monthlyEquivalent(ofAnnual: price(.annual))
            let base = "About $\(MivoPlusPricing.format(perMonth)) a month"
            return store.annualHasFreeTrial ? "\(trialLength) free, then \(base.lowercased())" : base
        case .monthly:
            return "Cancel anytime"
        case .lifetime:
            return "Never pay again"
        }
    }

    private func price(_ plan: MivoPlusPlan) -> Decimal {
        store.product(for: plan)?.price ?? plan.fallbackPrice
    }

    private var trialLength: String {
        guard let offer = store.product(for: .annual)?.subscription?.introductoryOffer else { return "Free trial" }
        let value = offer.period.value
        switch offer.period.unit {
        case .day: return "\(value)-day"
        case .week: return "\(value)-week"
        case .month: return "\(value)-month"
        case .year: return "\(value)-year"
        @unknown default: return "Free trial"
        }
    }

    private var purchaseLabel: String {
        switch selected {
        case .annual:
            return store.annualHasFreeTrial ? "Start \(trialLength) free trial" : "Get Plus for \(priceText(for: .annual)) a year"
        case .monthly:
            return "Get Plus for \(priceText(for: .monthly)) a month"
        case .lifetime:
            return "Get Plus for life, \(priceText(for: .lifetime))"
        }
    }

    private var purchaseFinePrint: String? {
        switch selected {
        case .annual where store.annualHasFreeTrial:
            return "Then \(priceText(for: .annual)) a year. Cancel anytime."
        case .annual, .monthly:
            return "Renews automatically. Cancel anytime."
        case .lifetime:
            return "One payment, no subscription."
        }
    }
}
