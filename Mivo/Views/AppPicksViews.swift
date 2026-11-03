import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// The social apps someone uses, each picked once in Apple's app list. The
/// shield only sees an opaque token for the app that was tapped, so this pick
/// is how it knows "that was TikTok" and opens TikTok's window in Mivo. Used in
/// onboarding (`OnboardingWelcomeView`) and in `AppPicksPromptView`; Settings
/// keeps the same picks editable.
struct AppPicksList: View {
    @Binding var chosen: Set<SocialApp>

    #if canImport(FamilyControls)
    @State private var selection = FamilyActivitySelection()
    #endif
    @State private var appBeingPicked: SocialApp?
    @State private var showPicker = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 9) {
            ForEach(SocialApp.allCases) { app in
                row(app)
            }
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: showPicker) { _, isPresented in
            guard !isPresented, let app = appBeingPicked else { return }
            appBeingPicked = nil
            // Closing Apple's list without choosing keeps whatever was there.
            guard !selection.applicationTokens.isEmpty else { return }
            do {
                try FamilyControlsManager.shared.saveAppMapping(selection, for: app)
                chosen.insert(app)
                HapticsService.success()
            } catch let error as AppMappingError {
                errorText = error == .selectOneApp ? "Pick only \(app.title), one app." : error.localizedDescription
            } catch {
                errorText = "Pick only \(app.title), one app."
            }
        }
        #endif
        .alert("Couldn't save that app", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func row(_ app: SocialApp) -> some View {
        let isChosen = chosen.contains(app)
        return Button {
            HapticsService.selection()
            #if canImport(FamilyControls)
            appBeingPicked = app
            selection = FamilyActivitySelection()
            showPicker = true
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .frame(width: 22)
                Text(app.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Spacer(minLength: 8)
                if isChosen {
                    Label("Chosen", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.keptInk)
                } else {
                    Text("Choose")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.deep)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isChosen ? MivoColors.surfaceV2 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isChosen ? MivoColors.deep.opacity(0.5) : MivoColors.ink.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChosen ? "\(app.title), chosen" : "Choose \(app.title)")
    }
}

/// Picks need Screen Time access first; until then Apple's list is empty.
struct AppPicksAccessCard: View {
    @Binding var authorized: Bool
    @State private var requesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mivo needs Screen Time access to see your apps. Apple never shows Mivo what you do in them.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
            MivoPrimaryButton(label: requesting ? "Waiting for Screen Time…" : "Allow Screen Time", disabled: requesting) {
                requesting = true
                FamilyControlsManager.shared.requestAuthorization { granted in
                    Task { @MainActor in
                        requesting = false
                        if granted {
                            HapticsService.success()
                            authorized = true
                        }
                    }
                }
            }
        }
    }
}

extension AppPicksList {
    /// The apps already picked on this device.
    static func currentPicks() -> Set<SocialApp> {
        Set(SocialApp.allCases.filter { FamilyControlsManager.shared.hasAppMapping(for: $0) })
    }

    /// Picked apps only open in Mivo while the switch is on and protection is
    /// running, so choosing them turns both on.
    static func turnOnProtection() {
        FamilyControlsManager.shared.setInstagramWrapperEnabled(true)
        FamilyControlsManager.shared.setImpulseProtectionEnabled(FamilyControlsManager.shared.hasImpulseSelection())
    }
}

/// "Which apps do you use?" once, for people who finished onboarding before
/// it asked. Shown by `MainTabView` from `AppViewModel.evaluateAppPicksPrompt()`
/// until they choose at least one app or say they use none of them.
struct AppPicksPromptView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var chosen = AppPicksList.currentPicks()
    @State private var authorized = FamilyControlsManager.shared.cachedAuthorizationStatus() == true

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Which apps do you use?")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(27 * -0.025)
                    .foregroundColor(MivoColors.ink)
                    .padding(.top, 64)

                Text("Tap each one you have, then pick it in Apple's list. From then on, tapping it opens it inside Mivo, where you say what you're there for.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(13.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    Group {
                        if authorized {
                            AppPicksList(chosen: $chosen)
                        } else {
                            AppPicksAccessCard(authorized: $authorized)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }

                Button("I don't use any of these") {
                    HapticsService.selection()
                    appVM.answerAppPicksPrompt()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)

                MivoPrimaryButton(label: chosen.isEmpty ? "Choose at least one" : "Done", disabled: chosen.isEmpty) {
                    AppPicksList.turnOnProtection()
                    HapticsService.success()
                    appVM.answerAppPicksPrompt()
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled()
    }
}
