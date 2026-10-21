import Combine
import SwiftUI

/// The one seam between Mivo Spots and the tab shell. `MainTabView` applies this
/// modifier once; everything a running Spot needs from the UI — binding to the
/// signed-in account, the tap confirmation, first-scan setup of a new Mivo Spot,
/// shield-triggered prompts, the summary, and keeping time honest on foreground —
/// lives here.
struct SpotsPresenter: ViewModifier {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var manager = SpotManager.shared

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                SpotNoticeOverlay()
            }
            .fullScreenCover(item: $manager.shieldPrompt) { prompt in
                SpotShieldPromptView(prompt: prompt)
            }
            // First scan of an official Mivo Spot: "Meet your new Mivo Spot".
            .fullScreenCover(item: $manager.claimRequest) { request in
                SpotSetupFlowView(editing: nil, claim: request)
            }
            .sheet(item: summaryBinding) { summary in
                SpotSummaryView(summary: summary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $manager.showActiveSpotRequested) {
                SpotActiveView()
            }
            .onAppear { bindAccount() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                bindAccount()
            }
            .onChange(of: appVM.user?.email) { _, _ in bindAccount() }
            .onReceive(ticker) { _ in manager.reconcile() }
            // Posted by the notification handler when a Spot notification is tapped
            // (or arrives while Mivo is open).
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name(SpotKeys.routeChangedNotification))) { _ in
                bindAccount()
            }
    }

    /// Binding to the signed-in account also reconciles: a Spot whose time ran
    /// out while Mivo was closed is finished here, and a shielded-app tap that
    /// opened Mivo is picked up.
    private func bindAccount() {
        manager.setAccount(appVM.user?.email ?? StorageService.activeUserEmail)
        // Hands the manager a way to refresh the sign-in before it asks the Mivo
        // backend about a Spot, and picks up a Mivo Spot scanned while logged out.
        manager.attachUI { [appVM] in try await appVM.prepareAuthenticatedSession() }
    }

    private var summaryBinding: Binding<SpotSessionSummary?> {
        Binding(
            get: { manager.summaryToShow },
            set: { newValue in
                if newValue == nil { manager.dismissSummary() }
            }
        )
    }
}

extension View {
    /// Mivo Spots' presentation layer. Apply once, at the root of the signed-in UI.
    func spotsPresentation() -> some View {
        modifier(SpotsPresenter())
    }
}
