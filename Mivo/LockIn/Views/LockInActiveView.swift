import SwiftUI

/// What a running lock looks like: the task, how long until the check-in, and the
/// way out (show Milo, or wait for the keyholder).
struct LockInActiveView: View {
    @ObservedObject private var manager = LockInManager.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @State private var showChat = false
    @State private var confirmUndo = false
    @State private var isChecking = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            if let lock = manager.current {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                        heroCard(lock)
                        if let notice = manager.notice {
                            noticeCard(notice)
                        }
                        actions(lock)
                        details(lock)
                    }
                    .padding(.horizontal, MivoMetrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, MivoMetrics.scrollBottomPadding)
                }
            }
        }
        .navigationTitle("Locked in")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRoamingCompanion()
        .navigationDestination(isPresented: $showChat) {
            MiloProofChatView()
        }
        .confirmationDialog(
            "Undo this lock?",
            isPresented: $confirmUndo,
            titleVisibility: .visible
        ) {
            Button("Undo the lock", role: .destructive) {
                manager.cancelFreely()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your apps open again. This is only possible for the first couple of minutes.")
        }
        // While a request is out, ask for the keyholder's answer every few seconds.
        .task(id: manager.current?.pendingRequest?.id) {
            guard manager.current?.pendingRequest != nil else { return }
            while !Task.isCancelled, manager.current?.pendingRequest != nil {
                await manager.pollKeyholderRequest()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    // MARK: Hero

    private func heroCard(_ lock: LockIn) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                MivoEyebrow(text: "Locked in", color: MivoColors.heroText.opacity(0.7))
                Text(lock.task)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 24))
                    .foregroundColor(MivoColors.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(LockInFormat.remaining(lock.remaining(now: context.date))) left")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(MivoColors.heroText)
                        Text("Check in by \(LockInFormat.clock(lock.endsAt))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.heroText.opacity(0.75))
                    }
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
            LockInMiloFigure(state: lock.phase == .waitingOnKeyholder ? .watching : .focused, height: 92)
                .frame(width: 72)
        }
        .padding(MivoMetrics.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.heroBg)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.cardRadius, style: .continuous))
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.timerRed)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MivoColors.timerRed.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ lock: LockIn) -> some View {
        VStack(spacing: 6) {
            if let pending = lock.pendingRequest {
                waitingCard(lock, pending)
            } else if let declined = lock.requests.last, declined.status == .declined {
                declinedCard(lock, declined)
            }

            MivoPrimaryButton(label: "Show \(companion.miloName) what you did") {
                HapticsService.selection()
                showChat = true
            }

            if lock.canCancelFreely() {
                MivoTertiaryButton(label: "Undo — I started this by mistake", color: MivoColors.inkBody) {
                    confirmUndo = true
                }
            }
        }
    }

    private func waitingCard(_ lock: LockIn, _ request: LockInUnlockRequest) -> some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Waiting for \(lock.keyholder?.name ?? "your keyholder")")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Spacer()
                    LockInStatusPill(text: "Sent \(LockInFormat.clock(request.sentAt))", tone: .warning)
                }
                Text("They've been emailed what \(companion.miloName) saw. Your apps open the moment they approve.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                MivoTertiaryButton(label: isChecking ? "Checking…" : "Check now", height: 34) {
                    guard !isChecking else { return }
                    isChecking = true
                    Task {
                        await manager.pollKeyholderRequest()
                        isChecking = false
                    }
                }
            }
        }
    }

    private func declinedCard(_ lock: LockIn, _ request: LockInUnlockRequest) -> some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(lock.keyholder?.name ?? "Your keyholder") said not yet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                if let note = request.keyholderNote, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LockInFootnote(lock.requests.count < LockInRules.maxUnlockRequests
                    ? "Keep going, then show \(companion.miloName) again."
                    : "That was the last request for this lock. It ends at the check-in time.")
            }
        }
    }

    // MARK: Details

    private func details(_ lock: LockIn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoSectionTitle(text: "This lock")
            MivoListGroup {
                detailRow(icon: "app.badge", title: "Locked", value: lock.apps.summary)
                MivoListDivider()
                detailRow(
                    icon: "person.badge.key",
                    title: "Keyholder",
                    value: keyholderValue(lock)
                )
                MivoListDivider()
                detailRow(icon: "flag.checkered", title: "Ends", value: endsValue(lock))
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        MivoListRow(icon: icon, title: title, subtitle: value, showsChevron: false)
    }

    private func keyholderValue(_ lock: LockIn) -> String {
        guard let keyholder = lock.keyholder else { return "None. \(companion.miloName) decides." }
        return keyholder.status == .active
            ? "\(keyholder.name) has the last word"
            : "\(keyholder.name) hasn't agreed yet"
    }

    private func endsValue(_ lock: LockIn) -> String {
        "When you've shown \(companion.miloName)\(lock.keyholder?.status == .active ? " and \(lock.keyholder?.name ?? "they") approves" : ""), or at \(LockInFormat.clock(lock.endsAt))."
    }
}
