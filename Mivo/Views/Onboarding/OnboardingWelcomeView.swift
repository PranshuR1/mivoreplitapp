import SwiftUI

private struct FirstLaunchMoment {
    let eyebrow: String
    let title: String
    let detail: String
    let icon: String
}

struct MivoFirstLaunchIntroView: View {
    let onComplete: () -> Void
    let onExit: (() -> Void)?

    init(onComplete: @escaping () -> Void, onExit: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.onExit = onExit
    }

    @State private var momentIndex = 0
    @State private var typedTitle = ""
    @State private var detailVisible = false
    @State private var readyForNext = false
    @State private var typingTask: Task<Void, Never>?
    @State private var signalPulse = false

    private let moments: [FirstLaunchMoment] = [
        .init(
            eyebrow: "THE PATTERN",
            title: "Some scrolling is chosen.",
            detail: "A message. A search. A moment you actually meant to have.",
            icon: "hand.tap.fill"
        ),
        .init(
            eyebrow: "THE GAP",
            title: "Some of it just... disappears.",
            detail: "A few repeated openings can quietly become a much longer day.",
            icon: "clock.arrow.circlepath"
        ),
        .init(
            eyebrow: "THE TRUTH",
            title: "Mivo shows where the missing time went.",
            detail: "Real device usage, intentional sessions, and the moments that pulled you back.",
            icon: "waveform.path.ecg"
        ),
        .init(
            eyebrow: "THE SHIFT",
            title: "See the pattern. Break the loop.",
            detail: "No guilt. Just one clearer choice at a time.",
            icon: "sparkles"
        )
    ]

    private var moment: FirstLaunchMoment { moments[momentIndex] }
    private var isLastMoment: Bool { momentIndex == moments.count - 1 }

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                HStack {
                    OnboardingBrandMark()
                    Spacer()
                    if let onExit {
                        Text("FOUNDER PREVIEW")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(OnboardingTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(OnboardingTheme.surfaceStrong)
                            .clipShape(Capsule())

                        Button(action: onExit) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(OnboardingTheme.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(OnboardingTheme.surfaceStrong)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close founder preview")
                    } else {
                        Button("Skip") { finishIntro() }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(OnboardingTheme.textSecondary)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(OnboardingTheme.signal.opacity(0.16), lineWidth: 1)
                            .frame(width: 82, height: 82)
                            .scaleEffect(signalPulse ? 1.14 : 0.9)
                        Circle()
                            .fill(OnboardingTheme.surfaceStrong)
                            .frame(width: 58, height: 58)
                        Image(systemName: moment.icon)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundColor(OnboardingTheme.accent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: signalPulse)

                    Text(moment.eyebrow)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(OnboardingTheme.accent)

                    Text(typedTitle + (readyForNext ? "" : "▍"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(OnboardingTheme.textPrimary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .accessibilityLabel(moment.title)

                    Text(moment.detail)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(OnboardingTheme.textSecondary)
                        .lineSpacing(5)
                        .opacity(detailVisible ? 1 : 0)
                        .offset(y: detailVisible ? 0 : 10)
                        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: detailVisible)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(moments.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == momentIndex ? OnboardingTheme.accent : OnboardingTheme.border)
                                .frame(width: index == momentIndex ? 28 : 7, height: 7)
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.8), value: momentIndex)

                    Button {
                        advance()
                    } label: {
                        HStack(spacing: 10) {
                            Text(isLastMoment ? "Continue to Mivo" : (readyForNext ? "Continue" : "Show full line"))
                                .font(.system(size: 16, weight: .bold))
                            Image(systemName: isLastMoment ? "arrow.right.circle.fill" : "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OnboardingTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(OnboardingPressStyle())

                    Text(readyForNext ? "A short introduction before account setup" : "Text is appearing now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(OnboardingTheme.textSecondary.opacity(0.76))
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            signalPulse = true
            typeCurrentMoment()
        }
        .onDisappear { typingTask?.cancel() }
    }

    private func typeCurrentMoment() {
        typingTask?.cancel()
        typedTitle = ""
        detailVisible = false
        readyForNext = false
        let fullTitle = moment.title
        typingTask = Task { @MainActor in
            HapticsService.firstLaunchEmphasis()
            var visibleCharacterCount = 0
            for character in fullTitle {
                guard !Task.isCancelled else { return }
                typedTitle.append(character)
                if !character.isWhitespace {
                    visibleCharacterCount += 1
                    if visibleCharacterCount == 1 || visibleCharacterCount.isMultiple(of: 4) {
                        HapticsService.firstLaunchTypingBeat()
                    }
                }
                try? await Task.sleep(nanoseconds: character == " " ? 22_000_000 : 36_000_000)
            }
            guard !Task.isCancelled else { return }
            readyForNext = true
            detailVisible = true
            HapticsService.firstLaunchEmphasis()
        }
    }

    private func advance() {
        if !readyForNext {
            typingTask?.cancel()
            typedTitle = moment.title
            readyForNext = true
            detailVisible = true
            HapticsService.firstLaunchEmphasis()
            return
        }
        if isLastMoment {
            finishIntro()
            return
        }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
            momentIndex += 1
        }
        typeCurrentMoment()
    }

    private func finishIntro() {
        typingTask?.cancel()
        HapticsService.success()
        onComplete()
    }
}

struct OnboardingWelcomeView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var goToWhy = false
    @State private var appear = false
    let replayMode: Bool

    init(replayMode: Bool = false) {
        self.replayMode = replayMode
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackdrop()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 26) {
                            VStack(spacing: 12) {
                                Text("Build a quieter phone")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .multilineTextAlignment(.center)

                                Text("Mivo learns where your attention leaks, then helps you pause before the loop starts.")
                                    .font(.system(size: 16))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(6)
                                    .padding(.horizontal, 10)
                            }
                            .padding(.top, 22)
                            .onboardingEntrance(appear, delay: 0.05)

                            focusHero
                                .onboardingEntrance(appear, delay: 0.16)

                            VStack(spacing: 12) {
                                ForEach(Array(pillarItems().enumerated()), id: \.offset) { index, item in
                                    PillarCard(item: item)
                                        .onboardingEntrance(appear, delay: 0.26 + Double(index) * 0.08)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 48)
                        .padding(.bottom, 120)
                    }

                    OnboardingBottomBar {
                        OnboardingPrimaryButton("Begin setup") {
                            Image(systemName: "arrow.right")
                        } action: {
                            goToWhy = true
                        }
                        .onboardingEntrance(appear, delay: 0.42)
                    }
                }
            }
            .navigationDestination(isPresented: $goToWhy) {
                OnboardingReferralCodeView()
            }
            .overlay(alignment: .topTrailing) {
                if replayMode {
                    Button {
                        HapticsService.impact(style: .medium)
                        appVM.cancelFounderOnboardingReplay()
                    } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(OnboardingPressStyle())
                    .accessibilityLabel("Exit onboarding replay")
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                }
            }
            .onboardingNavigationChromeHidden(showsBackButton: false)
            .onAppear { appear = true }
        }
    }

    private var focusHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MivoColors.heroBg, MivoColors.heroBg.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 226)

            Circle()
                .stroke(MivoColors.heroText.opacity(0.18), lineWidth: 18)
                .frame(width: 166, height: 166)

            Circle()
                .trim(from: 0.12, to: 0.86)
                .stroke(MivoColors.heroArc, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 144, height: 144)
                .rotationEffect(.degrees(-12))

            VStack(spacing: 10) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(MivoColors.heroText.opacity(0.16))
                    .clipShape(Circle())
                Text("A pause before autopilot")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.heroText)
                Text("Reflect first. Scroll only when you mean it.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.heroText.opacity(0.68))
            }

            VStack {
                HStack {
                    Text("Private by design")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.heroText.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(MivoColors.heroText.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
        }
    }

    private func pillarItems() -> [PillarCard.Item] {
        [
            .init(systemImage: "eye", title: "See the pattern", description: "Spot the moments your phone becomes automatic."),
            .init(systemImage: "pause.circle", title: "Add friction", description: "A short pause helps you choose before you scroll."),
            .init(systemImage: "chart.line.uptrend.xyaxis", title: "Improve gently", description: "Clear reports make progress feel visible.")
        ]
    }
}

private struct PillarCard: View {
    struct Item {
        let systemImage: String
        let title: String
        let description: String
    }

    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(MivoColors.surface)
                .foregroundColor(MivoColors.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(item.description)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(15)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 12, y: 6)
    }
}
