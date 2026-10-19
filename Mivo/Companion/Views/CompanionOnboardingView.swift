import SwiftUI

/// Four short pages, shown the first time Companion is turned on. Finishing
/// enables the companion; backing out leaves it off.
struct CompanionOnboardingView: View {
    @ObservedObject private var companion = CompanionStateManager.shared
    @EnvironmentObject private var appVM: AppViewModel

    private enum Page: Int, CaseIterable { case meet, privacy, personality, name }

    @State private var page: Page = .meet
    @State private var personality: CompanionPersonality = .gentle
    @State private var name = CompanionType.meerkat.defaultName
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 18)

                Group {
                    switch page {
                    case .meet: meetPage
                    case .privacy: privacyPage
                    case .personality: personalityPage
                    case .name: namePage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(page)

                VStack(spacing: 4) {
                    MivoPrimaryButton(label: page == .name ? "Meet \(trimmedName)" : "Continue") { advance() }
                    if page != .meet {
                        MivoTertiaryButton(label: "Back", color: MivoColors.inkMuted) { back() }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
        .animation(MivoMotion.stepEnter, value: page)
    }

    // MARK: Pages

    private var meetPage: some View {
        pageLayout(
            title: "Meet your Companion",
            body: "A small character that helps you notice when scrolling becomes automatic."
        ) {
            CompanionFigureView(state: .idle, animated: true, accessibilityName: nil)
                .frame(height: 210)
        }
    }

    private var privacyPage: some View {
        pageLayout(
            title: "It doesn't watch your screen.",
            body: "It responds only to Screen Time signals available to Mivo — like how much time has passed and how your pauses went."
        ) {
            VStack(spacing: 18) {
                CompanionFigureView(state: .watching, animated: true, accessibilityName: nil)
                    .frame(height: 170)
                VStack(alignment: .leading, spacing: 8) {
                    privacyLine("Never sees what you type, your messages or photos")
                    privacyLine("Never sees web pages, feeds or passwords")
                    privacyLine("Stores only small daily counts, on this device")
                }
            }
        }
    }

    private var personalityPage: some View {
        pageLayout(title: "Choose a personality", body: "It only changes the words. You can change it any time.") {
            VStack(spacing: 6) {
                ForEach(CompanionPersonality.allCases) { option in
                    MivoOptionRow(label: option.displayName, note: option.example, isSelected: personality == option) {
                        personality = option
                    }
                }
            }
        }
    }

    private var namePage: some View {
        pageLayout(title: "Name your companion", body: "You can rename it later in settings.") {
            VStack(spacing: 14) {
                CompanionFigureView(state: .happy, animated: true, accessibilityName: nil)
                    .frame(height: 150)
                TextField(CompanionType.meerkat.defaultName, text: $name)
                    .focused($nameFocused)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(MivoColors.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .onChange(of: name) { _, value in
                        if value.count > CompanionPreferences.maxNameLength {
                            name = String(value.prefix(CompanionPreferences.maxNameLength))
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { MivoHairline() }
                    .frame(maxWidth: 240)
            }
        }
    }

    // MARK: Pieces

    private func pageLayout<Art: View>(title: String, body: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            art()
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .frame(maxWidth: 320)
            Spacer(minLength: 12)
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.info)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= page.rawValue ? MivoColors.ink : MivoColors.barTrack)
                    .frame(width: item == page ? 22 : 7, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    private var trimmedName: String {
        CompanionPreferences.sanitizedName(name, for: .meerkat)
    }

    private func advance() {
        HapticsService.selection()
        if let next = Page(rawValue: page.rawValue + 1) {
            page = next
        } else {
            nameFocused = false
            companion.completeOnboarding(name: trimmedName, personality: personality)
            CompanionDeviceActivityAdapter.sync(with: appVM)
        }
    }

    private func back() {
        if let previous = Page(rawValue: page.rawValue - 1) { page = previous }
    }
}
