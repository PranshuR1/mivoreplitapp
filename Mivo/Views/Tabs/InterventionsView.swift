import SwiftUI

struct InterventionsView: View {
    @EnvironmentObject var appVM: AppViewModel
    var onSessionFinished: (() -> Void)? = nil

    @ObservedObject private var expansion = ProductExpansionStore.shared
    @ObservedObject private var mivoLock = MivoLockManager.shared
    @State private var showFlow = false

    var body: some View {
        let attempts = weekAttempts
        let sessions = weekSessions
        let protectionOn = FamilyControlsManager.shared.isImpulseProtectionEnabled()

        return ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    MivoScreenHeader(
                        eyebrow: protectionOn ? "Protection on" : "Protection off",
                        title: "Protect",
                        eyebrowColor: protectionOn ? MivoColors.keptInk : MivoColors.inkBody,
                        showsStatusDot: true
                    )
                    .padding(.top, 6)

                    heroCard
                    weekStatsCard(attempts: attempts, sessions: sessions)
                    todaysSessionsSection
                    protectionSetupSection
                }
                .padding(.horizontal, MivoMetrics.tabPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showFlow) {
            InterventionFlowView { onSessionFinished?() }
                .environmentObject(appVM)
        }
        .onAppear {
            // The flow's own duration step reads this fresh; a stale value here
            // only matters for the moment before the flow opens.
            appVM.refreshWeeklyExperimentLifecycle()
        }
    }

    // MARK: - Hero
    //
    // The one action on this screen, on the one dark card, so it is the first
    // thing the eye lands on.

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Pause before you scroll", color: MivoColors.heroText.opacity(0.78))

            Text("Open an app on purpose")
                .font(.system(size: 25, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 25))
                .foregroundColor(MivoColors.heroText)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(.top, 8)

            Text("Pick the app and what it's for. Social apps open inside Mivo, which keeps you to it; others open for a timed window.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.heroText.opacity(0.88))
                .lineSpacing(0.5 * 13.5)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, 10)

            MivoOnHeroButton(label: "Start a window") {
                HapticsService.selection()
                showFlow = true
            }
            .padding(.top, 20)
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 20, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .mivoCardBackground(fill: MivoColors.heroBg, bordered: false)
    }

    // MARK: - This week

    private func weekStatsCard(attempts: [InterventionAttemptRecord], sessions: [Session]) -> some View {
        let average = sessions.isEmpty ? "—" : "\(max(1, sessions.reduce(0) { $0 + $1.actualDuration } / sessions.count))m"
        return MivoCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("This week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkBody)
                    .padding(.horizontal, MivoMetrics.cardPadding)
                    .padding(.top, 16)

                MivoStatColumns(items: [
                    .init(value: "\(attempts.count)", label: "paused"),
                    .init(value: "\(attempts.filter { $0.continued == false }.count)", label: "walked away"),
                    .init(value: average, label: "avg session")
                ])
                .padding(.top, -4)
            }
        }
    }

    // MARK: - Today's sessions

    private var todaysSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Today")

            if todaysSessions.isEmpty {
                MivoCard(padding: 16) {
                    Text("Nothing yet today")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
            } else {
                MivoListGroup {
                    ForEach(Array(todaysSessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            MivoListDivider(inset: 16)
                        }
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.intention.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .lineLimit(1)
                Text(sessionMeta(session))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }
            Spacer(minLength: 8)
            MivoOutcomeBadge(outcome: outcome(for: session))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Protection setup
    //
    // Everything that configures the pause lives here, beside the pause itself,
    // instead of being spread across Settings.

    private var protectionSetupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Protection setup")

            MivoListGroup {
                setupLink(
                    icon: mivoLock.isLocked ? "lock.fill" : "lock.open",
                    label: "Keep Mivo on",
                    value: mivoLock.isLocked ? "Locked" : "Off",
                    tone: mivoLock.isLocked ? .positive : .muted
                ) {
                    MivoLockView()
                }

                MivoListDivider()
                setupLink(
                    icon: "checkmark.shield",
                    label: "Apps & Screen Time",
                    value: protectionStateText,
                    tone: FamilyControlsManager.shared.isImpulseProtectionEnabled() ? .positive : .muted
                ) {
                    SettingsView(page: .protection)
                }

                MivoListDivider()
                setupLink(
                    icon: "moon",
                    label: "Late-night protection",
                    value: appVM.lateNightProtectionEnabled ? "On" : "Off",
                    tone: appVM.lateNightProtectionEnabled ? .positive : .muted
                ) {
                    SettingsView(page: .lateNight)
                }

                if expansion.isEnabled(.appPersonalities) {
                    MivoListDivider()
                    setupLink(icon: "face.smiling", label: "App personalities", value: nil) {
                        AppPersonalitiesView().environmentObject(appVM)
                    }
                }

                MivoListDivider()
                setupLink(icon: "arrow.left.arrow.right", label: "Your swap", value: appVM.userSwap == nil ? "Not set" : "Set") {
                    SwapSettingsView()
                }

                MivoListDivider()
                setupLink(icon: "play.circle", label: "Practice the pause", value: nil) {
                    InterventionView(intention: nil, duration: nil)
                }
            }
        }
    }

    private func setupLink<Destination: View>(
        icon: String,
        label: String,
        value: String?,
        tone: MivoListRow.ValueTone = .muted,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            MivoListRow(icon: icon, title: label, value: value, valueTone: tone)
        }
        .buttonStyle(MivoRowPressStyle())
    }

    private var protectionStateText: String {
        FamilyControlsManager.shared.isImpulseProtectionEnabled() ? "On" : "Off"
    }

    // MARK: - Derived data

    private var weekAttempts: [InterventionAttemptRecord] {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        let formatter = ISO8601DateFormatter()
        return appVM.interventionAttempts.filter { attempt in
            guard let date = formatter.date(from: attempt.occurredAt) else { return false }
            return date >= weekStart
        }
    }

    private var weekSessions: [Session] {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        let formatter = MivoDay.formatter
        return appVM.sessions.filter { session in
            guard let date = formatter.date(from: session.date) else { return false }
            return date >= weekStart
        }
    }

    private var todaysSessions: [Session] {
        let today = MivoDay.key(Date())
        return appVM.sessions.filter { $0.date == today }
    }

    /// The design shows a per-app label ("Instagram · 12:31 PM · 20m"), but
    /// `Session` does not record which app a scroll session was in — that
    /// belongs to Apple's Screen Time report, not Mivo's own tracking. Rather
    /// than invent an app name, this shows what the record actually has: when
    /// the session happened and how long it ran.
    private func sessionMeta(_ session: Session) -> String {
        [displayTime(session.startTime), formatDuration(session.actualDuration)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func displayTime(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "Not worth it" and "no reflection given" both land on the neutral
    /// CLOSED badge — the handoff is explicit that "not worth it" is not a
    /// failure state, so it gets the same quiet treatment as a skipped
    /// reflection rather than a badge of its own.
    private func outcome(for session: Session) -> MivoOutcome {
        switch session.outcomeScore {
        case .worthIt: return .worthIt
        case .mixed: return .mixed
        case .notWorthIt, nil: return .closed
        }
    }
}
