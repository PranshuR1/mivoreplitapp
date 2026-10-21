import SwiftUI

/// The companion's presence inside Mivo's *existing* pause screens. It adds a
/// character and, when the companion is allowed to speak, one observational
/// line — it never adds actions, buttons or a second flow. Renders nothing at
/// all when Companion is off.
struct CompanionPauseAccessory: View {
    /// Smaller layout for pauses that already carry extra panels.
    var compact = false
    /// Pass `true` on screens that don't already report pause start/end
    /// through `AppViewModel` (the mid-session check-in).
    var beginsPause = false
    /// Space above the accessory. Applied only while Companion is on, so a
    /// screen that hosts this view lays out exactly as before when it's off.
    var topPadding: CGFloat = 0
    var bottomPadding: CGFloat = 0

    @ObservedObject private var companion = CompanionStateManager.shared
    @State private var line: String?
    @State private var didClaim = false

    private let cream = Color(red: 250 / 255, green: 243 / 255, blue: 232 / 255)

    var body: some View {
        if companion.isActive {
            HStack(alignment: .center, spacing: 12) {
                CompanionFigureView(
                    type: companion.preferences.companionType,
                    state: figureState,
                    animated: companion.preferences.animationsEnabled,
                    stretchUnlocked: companion.progress.isUnlocked(.stretching),
                    accessibilityName: companion.preferences.name
                )
                .frame(width: compact ? 42 : 62, height: compact ? 55 : 80)

                if let line {
                    Text(line)
                        .font(.system(size: compact ? 13 : 14.5, weight: .medium))
                        .foregroundColor(cream.opacity(0.78))
                        .multilineTextAlignment(.leading)
                        .lineLimit(compact ? 2 : 3)
                        .frame(maxWidth: 220, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .animation(MivoMotion.standard(0.3), value: line)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .onAppear {
                guard !didClaim else { return }
                didClaim = true
                if beginsPause { CompanionStateManager.shared.interventionBegan() }
                line = companion.claimSpeech()
            }
        }
    }

    /// Asleep stays asleep (quiet hours); otherwise the companion is "with you".
    private var figureState: CompanionState {
        companion.presentation.state == .sleeping ? .sleeping : .intervening
    }

    private var accessibilitySummary: String {
        let name = companion.preferences.name
        if let line { return "\(name) says: \(line)" }
        return "\(name) is here with you"
    }
}

/// The Home entry point: a tile in the Explore grid. The caller places it while
/// Companion is active, or on but not yet introduced, when it reads "Meet Milo"
/// and opens the onboarding. One view covers both so finishing onboarding
/// doesn't tear down the sheet that is showing it.
struct CompanionHomeRow: View {
    @ObservedObject private var companion = CompanionStateManager.shared
    @EnvironmentObject private var appVM: AppViewModel
    @State private var showCompanion = false

    var body: some View {
        MivoToolTile(
            title: companion.isActive ? companion.preferences.name : "Meet \(companion.preferences.name)",
            subtitle: companion.isActive
                ? (companion.presentation.message ?? companion.todaySummary)
                : "A small companion for your pauses."
        ) {
            showCompanion = true
        } leading: {
            CompanionFigureView(
                type: companion.preferences.companionType,
                state: companion.presentation.state,
                animated: companion.preferences.animationsEnabled,
                stretchUnlocked: companion.progress.isUnlocked(.stretching),
                accessibilityName: companion.preferences.name
            )
            .frame(width: 30, height: 39)
        }
        .sheet(isPresented: $showCompanion) {
            NavigationStack {
                CompanionEntryView()
                    .environmentObject(appVM)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showCompanion = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Presents the Companion screen when the widget (or any `mivo://companion`
/// link) asks for it.
private struct CompanionDeepLinkModifier: ViewModifier {
    @ObservedObject private var companion = CompanionStateManager.shared
    @EnvironmentObject private var appVM: AppViewModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: $companion.openRequested) {
            NavigationStack {
                CompanionEntryView()
                    .environmentObject(appVM)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { companion.openRequested = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    func companionDeepLinkSheet() -> some View { modifier(CompanionDeepLinkModifier()) }
}
