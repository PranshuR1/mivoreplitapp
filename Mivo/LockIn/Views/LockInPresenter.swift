import Combine
import SwiftUI

/// The one seam between Lock-in and the tab shell. `MainTabView` applies this
/// modifier once; everything a lock needs from the UI — binding to the signed-in
/// account, keeping time honest on foreground, opening the Lock-in screen when a
/// shield or link asks, and the wrap-up when a lock ends — lives here.
struct LockInPresenter: ViewModifier {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var manager = LockInManager.shared
    @State private var wrapUp: LockIn?

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $manager.showRequested) {
                NavigationStack {
                    LockInEntryView()
                        .environmentObject(appVM)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { manager.showRequested = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $wrapUp, onDismiss: { manager.dismissWrapUp() }) { lock in
                LockInWrapUpView(lock: lock)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear { bind() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                bind()
                Task {
                    await manager.refreshKeyholder()
                    await manager.pollKeyholderRequest()
                }
            }
            .onChange(of: appVM.user?.email) { _, _ in bind() }
            .onChange(of: manager.history) { _, _ in syncCommitments() }
            .onChange(of: manager.current) { _, _ in syncCommitments() }
            .onReceive(ticker) { _ in manager.reconcile() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name(LockInKeys.routeChangedNotification))) { _ in
                manager.reconcile()
                manager.showRequested = true
            }
            .onChange(of: manager.justReleased) { _, released in
                guard let released else { return }
                // A sheet that is already showing has to finish closing before the
                // wrap-up can appear on top of the tab shell.
                if manager.showRequested {
                    manager.showRequested = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { wrapUp = released }
                } else {
                    wrapUp = released
                }
            }
    }

    private func bind() {
        manager.ownerName = appVM.user?.name.split(separator: " ").first.map(String.init) ?? ""
        manager.setAccount(appVM.user?.email ?? StorageService.activeUserEmail)
        syncCommitments()
    }

    private func syncCommitments() {
        appVM.syncAttentionCommitments(current: manager.current, history: manager.history)
    }
}

extension View {
    /// Lock-in's presentation layer. Apply once, at the root of the signed-in UI.
    func lockInPresentation() -> some View {
        modifier(LockInPresenter())
    }
}

// MARK: - Home tile

/// The Home entry point: a row in the Tools list.
struct LockInHomeRow: View {
    @ObservedObject private var manager = LockInManager.shared

    var body: some View {
        MivoToolTile(
            icon: manager.isLocked ? "lock.fill" : "lock",
            title: manager.isLocked ? "Apps locked for a task" : "Task lock",
            subtitle: manager.current?.task ?? "Lock apps until a task is done."
        ) {
            manager.showRequested = true
        }
    }
}

// MARK: - Wrap-up

/// Shown once when a lock ends: what happened, and a way to go again.
struct LockInWrapUpView: View {
    let lock: LockIn

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var companion = CompanionStateManager.shared

    private var reason: LockInReleaseReason { lock.releaseReason ?? .timeRanOut }
    private var miloName: String { companion.miloName }

    var body: some View {
        VStack(spacing: 0) {
            LockInMiloFigure(state: reason.wasCompleted ? .celebrating : .resting, height: 130)
                .padding(.top, 26)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 26))
                .foregroundColor(MivoColors.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(detail)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 8)

            Text("“\(lock.task)” · \(LockInFormat.remaining((lock.releasedAt ?? lock.endsAt).timeIntervalSince(lock.startedAt)))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Spacer(minLength: 16)

            MivoPrimaryButton(label: "Done") { dismiss() }
            if !reason.wasCompleted {
                MivoTertiaryButton(label: "Start another task lock") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        LockInManager.shared.showRequested = true
                    }
                }
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 16)
        .background(MivoColors.background.ignoresSafeArea())
    }

    private var title: String {
        switch reason {
        case .miloConvinced, .keyholderApproved: return "Unlocked. Nice work."
        case .timeRanOut: return "Time ran out"
        case .cancelledEarly: return "Lock undone"
        }
    }

    private var detail: String {
        switch reason {
        case .miloConvinced:
            return "\(miloName) is convinced. Your apps are open again."
        case .keyholderApproved:
            return "\(lock.keyholder?.name ?? "Your keyholder") approved it. Your apps are open again."
        case .timeRanOut:
            return "The check-in time passed before you showed \(miloName). Your apps are open again, and this one is recorded as not done."
        case .cancelledEarly:
            return "Your apps are open again."
        }
    }
}
