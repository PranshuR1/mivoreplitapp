import SwiftUI

/// Settings → Lock-in, the Home tile and `mivo://lockin` land here. A running lock
/// shows its status; otherwise the person can start one.
struct LockInEntryView: View {
    @ObservedObject private var manager = LockInManager.shared

    var body: some View {
        Group {
            if manager.current != nil {
                LockInActiveView()
            } else {
                LockInHomeView()
            }
        }
        .animation(MivoMotion.stepEnter, value: manager.current != nil)
    }
}

struct LockInHomeView: View {
    @ObservedObject private var manager = LockInManager.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @State private var showSetup = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    hero
                    howItEnds
                    setupGroup
                    if !manager.history.isEmpty { historySection }
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Lock in")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRoamingCompanion()
        .fullScreenCover(isPresented: $showSetup) {
            LockInSetupFlowView()
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            LockInMiloFigure(state: .focused, height: 150)
                .padding(.top, 18)

            Text("Lock in")
                .font(.system(size: 28, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 28))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 6)

            Text("Name one thing. Mivo locks your distracting apps until you've done it and shown \(companion.miloName).")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 6)

            MivoPrimaryButton(label: "Start a lock") {
                HapticsService.selection()
                showSetup = true
            }
            .padding(.top, 22)
        }
    }

    // MARK: How it ends

    private var howItEnds: some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoSectionTitle(text: "How a lock ends")
            MivoCard {
                VStack(alignment: .leading, spacing: 16) {
                    LockInStepRow(
                        number: 1,
                        title: "You do the thing",
                        detail: "Your chosen apps stay locked while you work."
                    )
                    LockInStepRow(
                        number: 2,
                        title: "You show \(companion.miloName)",
                        detail: "Explain what you did, and add a photo or screenshot if you can."
                    )
                    LockInStepRow(
                        number: 3,
                        title: "A friend can have the last word",
                        detail: "Pick a keyholder and they approve the unlock. Without one, \(companion.miloName) decides."
                    )
                }
            }
            LockInFootnote("Every lock has a check-in time, at most \(LockInKeys.hardCapHours) hours away. If it passes without proof, your apps open and the lock is recorded as not done.")
                .padding(.horizontal, 4)
        }
    }

    // MARK: Set up

    private var setupGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoSectionTitle(text: "Set up")
            MivoListGroup {
                NavigationLink {
                    LockInKeyholderView()
                } label: {
                    MivoListRow(
                        icon: "person.badge.key",
                        title: "Keyholder",
                        subtitle: keyholderSubtitle,
                        value: manager.keyholder.map { $0.status == .active ? "Active" : "Invited" }
                    )
                }
                .buttonStyle(MivoRowPressStyle())

                MivoListDivider()

                NavigationLink {
                    LockInScreenTimeGuideView()
                } label: {
                    MivoListRow(
                        icon: "lock.shield",
                        title: "Make it hard to undo",
                        subtitle: "Lock Screen Time behind a friend's code"
                    )
                }
                .buttonStyle(MivoRowPressStyle())
            }
        }
    }

    private var keyholderSubtitle: String {
        guard let keyholder = manager.keyholder else { return "A friend who approves your unlocks" }
        return keyholder.status == .active
            ? "\(keyholder.name) approves your unlocks"
            : "Waiting for \(keyholder.name) to agree"
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoSectionTitle(text: "Recent locks")
            MivoListGroup {
                let recent = Array(manager.history.prefix(5))
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, lock in
                    if index > 0 { MivoListDivider(inset: 16) }
                    LockInHistoryRow(lock: lock)
                }
            }
        }
    }
}

struct LockInHistoryRow: View {
    let lock: LockIn

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lock.task)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }
            Spacer(minLength: 8)
            if let reason = lock.releaseReason {
                LockInStatusPill(text: LockInFormat.outcome(reason), tone: reason.wasCompleted ? .good : .neutral)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let when = lock.startedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let length = lock.releasedAt.map { LockInFormat.remaining($0.timeIntervalSince(lock.startedAt)) }
        return [when, length].compactMap { $0 }.joined(separator: " · ")
    }
}
