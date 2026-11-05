import SwiftUI
import StoreKit

/// The Mivo Plus paywall. `feature` is the locked thing the person just
/// tapped, so the first line says why they're here. With Plus already active
/// it shows their plan and where to manage it.
///
/// The first time someone closes it, the paywall doesn't leave: it turns into
/// a five-minute discount (confetti, countdown, lower prices). Closing it
/// again, or after the timer runs out, just closes it.
struct MivoPlusPaywallView: View {
    var feature: PlusFeature? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var store = MivoPlusStore.shared
    @ObservedObject private var offer = MivoPlusOffer.shared
    @State private var selected: MivoPlusPlan = .annual
    @State private var showingManage = false
    /// True while the discount is running. Drives every price on screen.
    @State private var offerLive: Bool
    @State private var showConfetti = false

    private static let topID = "paywall.top"
    private static let gold = Color(hex: "#F2C46D")

    init(feature: PlusFeature? = nil) {
        self.feature = feature
        if case .running = MivoPlusOffer.shared.phase() {
            _offerLive = State(initialValue: true)
        } else {
            _offerLive = State(initialValue: false)
        }
    }

    private var hasPlus: Bool {
        MivoPlusAccess.allows(isPlus: store.isPlus, isAdmin: appVM.isAdminUser)
    }

    private var isBusy: Bool {
        store.purchaseState == .purchasing || store.purchaseState == .restoring
    }

    var body: some View {
        GeometryReader { geometry in
            content(topInset: geometry.safeAreaInsets.top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hasPlus { purchaseBar }
        }
        .task {
            store.start()
            // Any paywall on screen restarts the wait before it opens by itself.
            if !hasPlus { PlusPromptStore().markShown(account: appVM.user?.email) }
            await store.loadProducts()
        }
        .task(id: offerLive) {
            await endOfferWhenTimeRunsOut()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            syncOfferState()
        }
        .onChange(of: store.isPlus) { _, nowPlus in
            if nowPlus && feature != nil { dismiss() }
        }
        .manageSubscriptionsSheet(isPresented: $showingManage)
    }

    private func content(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            MivoColors.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero(topInset: topInset).id(Self.topID)

                        VStack(alignment: .leading, spacing: 20) {
                            if hasPlus {
                                activePlanCard
                            } else {
                                planList
                                benefits
                                restoreAndLegal
                            }
                        }
                        .padding(.horizontal, MivoMetrics.tabPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                        .mivoReadableWidth()
                    }
                }
                // The hero paints under the status bar; it pads itself down.
                .ignoresSafeArea(edges: .top)
                .onChange(of: offerLive) { _, live in
                    guard live else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(Self.topID, anchor: .top)
                    }
                }
            }

            closeButton

            if showConfetti {
                MivoConfettiView()
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Close and offer

    private var closeButton: some View {
        Button {
            closeTapped()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.28)))
        }
        .disabled(isBusy)
        .accessibilityLabel("Close")
        .padding(.top, 14)
        .padding(.trailing, 16)
    }

    /// First close turns the paywall into the discount. Every close after
    /// that, or one made with Plus already on, leaves.
    private func closeTapped() {
        if !hasPlus, offer.startIfNeeded() {
            HapticsService.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                offerLive = true
            }
            celebrate()
        } else {
            dismiss()
        }
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        showConfetti = true
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            showConfetti = false
        }
    }

    private func syncOfferState() {
        var live = false
        if case .running = offer.phase() { live = true }
        guard live != offerLive else { return }
        withAnimation(.easeInOut(duration: 0.3)) { offerLive = live }
    }

    /// Sleeps until the deadline, then puts the regular prices back.
    private func endOfferWhenTimeRunsOut() async {
        guard offerLive, let deadline = offer.deadline else { return }
        let wait = deadline.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.3)) { offerLive = false }
    }

    // MARK: - Hero

    private func hero(topInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: offerLive ? "gift.fill" : "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 2)

            Text(offerLive && !hasPlus ? "LIMITED-TIME OFFER" : "MIVO PLUS")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.4)
                .foregroundColor(Self.gold)

            Text(heroTitle)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if offerLive, !hasPlus, let deadline = offer.deadline {
                countdown(until: deadline)
                    .padding(.top, 8)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, topInset + 44)
        .padding(.bottom, 26)
        .mivoReadableWidth()
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { heroBackground }
    }

    private var heroBackground: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28), style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(
                colors: [Color(hex: "#2E1A0E"), Color(hex: "#7A4424")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            shape.fill(LinearGradient(
                colors: [Color(hex: "#5C3317"), Color(hex: "#C06F22")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .opacity(offerLive && !hasPlus ? 1 : 0)
            shape.fill(RadialGradient(
                colors: [Color.white.opacity(0.16), Color.clear],
                center: .top, startRadius: 4, endRadius: 280
            ))
        }
    }

    private var heroTitle: String {
        if hasPlus { return "Mivo Plus" }
        return offerLive ? "Discount just for you" : "Scroll on your terms."
    }

    private var heroSubtitle: String {
        if hasPlus { return "Clear, quiet time, and weekly experiments are yours." }
        if offerLive {
            return "Up to \(bestPercentOff)% off Mivo Plus, only while the timer runs."
        }
        return feature?.lockedLine ?? PlusFeature.general.lockedLine
    }

    private func countdown(until deadline: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let label = MivoPlusOfferClock.format(remaining)
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Ends in")
                        .font(.system(size: 14, weight: .semibold))
                    Text(label)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.white)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Self.gold)
                            .frame(width: proxy.size.width * CGFloat(remaining / MivoPlusOfferClock.duration))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(width: 230)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.22)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Offer ends in \(label)")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Plans

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

    private struct PlanBadge {
        let text: String
        let color: Color
    }

    private func planRow(_ plan: MivoPlusPlan) -> some View {
        let isSelected = plan == selected
        let shape = RoundedRectangle(cornerRadius: MivoMetrics.cardRadius, style: .continuous)
        return Button {
            HapticsService.selection()
            withAnimation(.easeOut(duration: 0.15)) { selected = plan }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? MivoColors.accent : MivoColors.inkMuted)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        if let badge = badge(for: plan) {
                            Text(badge.text)
                                .font(.system(size: 10.5, weight: .heavy))
                                .tracking(0.4)
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(badge.color))
                        }
                    }
                    Text(detail(for: plan))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    if let was = struckPrice(for: plan) {
                        Text(was)
                            .font(.system(size: 12.5, weight: .medium))
                            .strikethrough()
                            .foregroundColor(MivoColors.inkMuted)
                    }
                    Text(livePriceText(plan))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                        .contentTransition(.numericText())
                    Text(plan.period)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? MivoColors.accent.opacity(0.10) : MivoColors.surfaceRaised))
            .overlay(shape.stroke(isSelected ? MivoColors.accent : MivoColors.hairline, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var benefits: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Everything in Plus")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(MivoColors.inkMuted)
                    .textCase(.uppercase)

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

                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 12, weight: .semibold))
                    Text(MivoPlusCopy.basicPauseLine)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(MivoColors.keptInk)
            }
        }
    }

    // MARK: - Purchase

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: MivoMetrics.buttonHeight)
            } else {
                MivoPrimaryButton(label: purchaseLabel, disabled: store.product(for: selected, offer: offerLive) == nil) {
                    Task { await store.purchase(selected, offer: offerLive) }
                }
            }

            Text(purchaseFinePrint)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)

            if case .failed(let message) = store.purchaseState {
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, MivoMetrics.tabPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .mivoReadableWidth()
        .frame(maxWidth: .infinity)
        .background(
            MivoColors.background
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var restoreAndLegal: some View {
        VStack(spacing: 12) {
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(MivoColors.deep)
            .disabled(isBusy)

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
        VStack(spacing: 16) {
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
            MivoPrimaryButton(label: "Continue") { dismiss() }
        }
    }

    // MARK: - Prices

    private func regularPrice(_ plan: MivoPlusPlan) -> Decimal {
        store.product(for: plan)?.price ?? plan.fallbackPrice
    }

    private func livePrice(_ plan: MivoPlusPlan) -> Decimal {
        if let product = store.product(for: plan, offer: offerLive) { return product.price }
        return offerLive ? plan.fallbackOfferPrice : plan.fallbackPrice
    }

    private func regularPriceText(_ plan: MivoPlusPlan) -> String {
        store.product(for: plan)?.displayPrice ?? plan.fallbackPriceText
    }

    private func livePriceText(_ plan: MivoPlusPlan) -> String {
        if let product = store.product(for: plan, offer: offerLive) { return product.displayPrice }
        return offerLive ? plan.fallbackOfferPriceText : plan.fallbackPriceText
    }

    /// An amount in the plan's own currency, e.g. the yearly price per month.
    private func formatted(_ value: Decimal, plan: MivoPlusPlan) -> String {
        if let product = store.product(for: plan, offer: offerLive) ?? store.product(for: plan) {
            return value.formatted(product.priceFormatStyle)
        }
        return "$\(MivoPlusPricing.format(value))"
    }

    /// Percent off the regular price, 0 outside the discount.
    private func percentOff(_ plan: MivoPlusPlan) -> Int {
        guard offerLive else { return 0 }
        return MivoPlusPricing.percentOff(regular: regularPrice(plan), offer: livePrice(plan))
    }

    private var bestPercentOff: Int {
        MivoPlusPlan.allCases.map(percentOff).max() ?? 0
    }

    private var yearlySavingsPercent: Int {
        MivoPlusPricing.yearlySavingsPercent(monthly: livePrice(.monthly), annual: livePrice(.annual))
    }

    /// The price being replaced: the regular price during the discount, or a
    /// year of monthly payments next to the yearly plan.
    private func struckPrice(for plan: MivoPlusPlan) -> String? {
        if offerLive {
            return percentOff(plan) > 0 ? regularPriceText(plan) : nil
        }
        guard plan == .annual, yearlySavingsPercent > 0 else { return nil }
        return formatted(livePrice(.monthly) * 12, plan: .monthly)
    }

    private func badge(for plan: MivoPlusPlan) -> PlanBadge? {
        if offerLive {
            let percent = percentOff(plan)
            return percent > 0 ? PlanBadge(text: "\(percent)% OFF", color: MivoColors.kept) : nil
        }
        switch plan {
        case .annual:
            let percent = yearlySavingsPercent
            return PlanBadge(text: percent > 0 ? "SAVE \(percent)%" : "BEST VALUE", color: MivoColors.accent)
        case .lifetime:
            return PlanBadge(text: "PAY ONCE", color: MivoColors.blue)
        case .monthly:
            return nil
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

    private var hasTrial: Bool { store.hasFreeTrial(offer: offerLive) }

    private func detail(for plan: MivoPlusPlan) -> String {
        switch plan {
        case .annual:
            let perMonth = formatted(MivoPlusPricing.monthlyEquivalent(ofAnnual: livePrice(.annual)), plan: .annual)
            return hasTrial ? "\(trialLength) free, then \(perMonth) a month" : "Just \(perMonth) a month"
        case .monthly:
            return "Cancel anytime"
        case .lifetime:
            return "Never pay again"
        }
    }

    private var trialLength: String {
        guard let offer = store.product(for: .annual, offer: offerLive)?.subscription?.introductoryOffer else { return "Free trial" }
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
        let price = livePriceText(selected)
        let percent = percentOff(selected)
        switch selected {
        case .annual:
            if hasTrial { return "Start \(trialLength) free trial" }
            return percent > 0 ? "Claim \(percent)% off, \(price) a year" : "Get Plus for \(price) a year"
        case .monthly:
            return percent > 0 ? "Claim \(percent)% off, \(price) a month" : "Get Plus for \(price) a month"
        case .lifetime:
            return percent > 0 ? "Claim \(percent)% off, \(price) once" : "Get Plus for life, \(price)"
        }
    }

    private var purchaseFinePrint: String {
        let price = livePriceText(selected)
        switch selected {
        case .annual where hasTrial:
            return "Then \(price) a year. Cancel anytime."
        case .annual:
            return offerLive ? "Renews at \(price) a year. Cancel anytime." : "Renews automatically. Cancel anytime."
        case .monthly:
            return offerLive ? "Renews at \(price) a month. Cancel anytime." : "Renews automatically. Cancel anytime."
        case .lifetime:
            return "One payment, no subscription."
        }
    }
}

/// The Plus card at the top of Home for anyone without Plus. While the
/// five-minute discount runs it shows the countdown instead.
struct MivoPlusHomeBanner: View {
    let action: () -> Void

    @ObservedObject private var offer = MivoPlusOffer.shared
    @ObservedObject private var store = MivoPlusStore.shared

    private static let gold = Color(hex: "#F2C46D")

    var body: some View {
        Button {
            HapticsService.selection()
            action()
        } label: {
            if case .running = offer.phase(), let deadline = offer.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, deadline.timeIntervalSince(context.date))
                    card(
                        eyebrow: "LIMITED-TIME OFFER",
                        title: "Your discount is still on",
                        detail: "Ends in \(MivoPlusOfferClock.format(remaining))",
                        cta: "Claim it",
                        offerLive: remaining > 0
                    )
                }
            } else {
                card(
                    eyebrow: "MIVO PLUS",
                    title: "Get more from Mivo",
                    detail: "Earn scroll time from studying, Replay, Still and more.",
                    cta: store.hasFreeTrial(offer: false) ? "Try free" : "See plans",
                    offerLive: false
                )
            }
        }
        .buttonStyle(MivoPressStyle())
        .accessibilityHint("Opens Mivo Plus")
    }

    private func card(eyebrow: String, title: String, detail: String, cta: String, offerLive: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: offerLive ? "gift.fill" : "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Self.gold)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.82))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Text(cta)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(Color(hex: "#2E1A0E"))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Self.gold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MivoMetrics.cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: offerLive
                        ? [Color(hex: "#5C3317"), Color(hex: "#C06F22")]
                        : [Color(hex: "#2E1A0E"), Color(hex: "#7A4424")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .contentShape(Rectangle())
    }
}
