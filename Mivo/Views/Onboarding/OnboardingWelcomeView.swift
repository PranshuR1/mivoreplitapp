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


// MARK: - Onboarding (v2 redesign)

/// One decision per screen, progress always visible, never more than four
/// options: three questions, the apps Mivo opens, then one real opening of
/// an app. No story screens and no tour; tools explain themselves when used.
///
/// Answers are written straight into `AppViewModel.onboardingProfile` so the
/// plan, the pause and the app shield all read the same values the user chose.
struct OnboardingWelcomeView: View {
    @EnvironmentObject private var appVM: AppViewModel

    let replayMode: Bool

    init(replayMode: Bool = false) {
        self.replayMode = replayMode
    }

    /// The questions, then the apps step, then the first opening.
    @State private var index = Self.initialIndex

    /// Lets `-MivoPreviewOnboardingStep <n>` open a single screen directly, in
    /// keeping with the other `-MivoPreview…` arguments RootView already reads.
    private static var initialIndex: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-MivoPreviewOnboardingStep"),
           arguments.indices.contains(flag + 1),
           let step = Int(arguments[flag + 1]) {
            return max(0, step)
        }
        #endif
        return 0
    }
    @State private var answers: [Int: String] = [:]
    @State private var isRequestingScreenTime = false
    @State private var chosenApps = AppPicksList.currentPicks()
    @State private var screenTimeAuthorized = FamilyControlsManager.shared.cachedAuthorizationStatus() == true
    @State private var showFirstOpening = false
    @State private var isFinishing = false

    private var questions: [OnboardingQuestion] { OnboardingQuestion.all }

    var body: some View {
        ZStack {
            if index == questions.count {
                appsStep.transition(.opacity)
            } else if index > questions.count {
                firstOpeningStep.transition(.opacity)
            } else {
                question(questions[max(0, index)]).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: index)
        .onAppear {
            if let problem = appVM.attentionJourney.problem { answers[0] = problem.rawValue }
        }
        .fullScreenCover(isPresented: $showFirstOpening, onDismiss: finishOnboarding) {
            InterventionFlowView(preselectedApp: firstOpeningApp) {}
                .environmentObject(appVM)
        }
        .overlay(alignment: .topTrailing) {
            if replayMode {
                Button {
                    HapticsService.impact(style: .medium)
                    appVM.cancelFounderOnboardingReplay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                        .frame(width: 42, height: 42)
                }
                .accessibilityLabel("Exit onboarding replay")
                .padding(.top, 12)
                .padding(.trailing, 14)
            }
        }
    }


    // MARK: 8.2 Question screens

    private func question(_ item: OnboardingQuestion) -> some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 56)

                Text(item.title)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(27 * -0.025)
                    .foregroundColor(MivoColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.top, 34)

                Text(item.subtitle)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(13.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 295, alignment: .leading)
                    .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 9) {
                        ForEach(item.options) { option in
                            optionRow(option, in: item)
                        }
                    }
                    .padding(.top, 28)
                }

                Spacer(minLength: 0)

                if let footnote = item.footnote {
                    Text(footnote)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 10)
                }

                if item.requestsScreenTime {
                    Button("Set this up later") {
                        guard !isRequestingScreenTime else { return }
                        index += 1
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(isRequestingScreenTime)
                }

                primaryButton(
                    title: item.ctaTitle,
                    enabled: item.requiresAnswer ? answers[index] != nil : true,
                    loading: isRequestingScreenTime,
                    action: advance
                )
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                HapticsService.selection()
                index -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go back")
            // The first question is the first screen: nothing to go back to.
            .opacity(index > 0 ? 1 : 0)
            .disabled(index == 0)
            .accessibilityHidden(index == 0)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MivoColors.ink.opacity(0.12))
                    Capsule()
                        .fill(MivoColors.accent)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .animation(.timingCurve(0.22, 0.7, 0.3, 1, duration: 0.42), value: index)

            Text("\(min(index + 1, questions.count)) / \(questions.count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.inkMuted)
                .accessibilityLabel("Question \(min(index + 1, questions.count)) of \(questions.count)")
        }
    }

    private var progress: CGFloat {
        guard !questions.isEmpty else { return 0 }
        return CGFloat(min(index + 1, questions.count)) / CGFloat(questions.count)
    }

    private func optionRow(_ option: OnboardingOption, in item: OnboardingQuestion) -> some View {
        let selected = answers[index] == option.id
        return Button {
            HapticsService.impact(style: .medium)
            answers[index] = option.id
            persist(option, for: item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(option.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let note = option.note {
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selected ? Color(hex: "#96551A") : MivoColors.inkMuted)
                        .fixedSize()
                }
            }
            .padding(18)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? MivoColors.surfaceV2 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected ? MivoColors.deep.opacity(0.5) : MivoColors.ink.opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 8.2a Your apps
    //
    // Right after Screen Time access, while the reason is fresh: each social
    // app picked here opens inside Mivo when tapped, where the person says
    // what they're there for. Choosing at least one is the way on; the
    // escape is saying none of these apps are theirs. People who joined
    // before this step get it once on their next open (`AppPicksPromptView`).
    private var appsStep: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 56)

                Text("Which apps do you use?")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(27 * -0.025)
                    .foregroundColor(MivoColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.top, 34)

                Text("Tap each one you have, then pick it in Apple's list. Tapping it later opens it inside Mivo, where you say what you're there for.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(13.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 295, alignment: .leading)
                    .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    Group {
                        if screenTimeAuthorized {
                            AppPicksList(chosen: $chosenApps)
                        } else {
                            AppPicksAccessCard(authorized: $screenTimeAuthorized)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }

                Spacer(minLength: 0)

                Button {
                    HapticsService.selection()
                    if screenTimeAuthorized {
                        AppPicksPrompt.markAnswered()
                    }
                    // Without access nothing can be picked yet; Mivo asks
                    // again on a later open instead of taking this as an answer.
                    index += 1
                } label: {
                    Text(screenTimeAuthorized ? "I don't use any of these" : "Set this up later")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)

                primaryButton(title: chosenApps.isEmpty ? "Choose at least one" : "Continue", enabled: !chosenApps.isEmpty, loading: false) {
                    AppPicksPrompt.markAnswered()
                    AppPicksList.turnOnProtection()
                    HapticsService.success()
                    index += 1
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: 8.3 First opening
    //
    // Instead of a plan summary and an app tour, the last step is the thing
    // Mivo is for: opening one app on purpose, for real. Onboarding completes
    // when that window closes, so Home, the tools and any prompts come after
    // the person has already used Mivo once.
    private var firstOpeningStep: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 56)

                Text("TRY IT ONCE")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .tracking(10 * 0.13)
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 34)

                Text(firstOpeningTitle)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(27 * -0.025)
                    .foregroundColor(MivoColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.top, 8)

                Text("This is how every app opens through Mivo. It takes about ten seconds.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(13.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 295, alignment: .leading)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 18) {
                    firstOpeningRow(1, "Say what you came for", "Messages, a search or a few videos. Mivo opens the app right there.")
                    firstOpeningRow(2, "Choose how much", "A number of videos or a few minutes. Messages stay unlimited.")
                    firstOpeningRow(3, "Mivo holds you to it", "Wander off and it reminds you why you came. Once you've had what you chose, the feed slows down.")
                }
                .padding(.top, 28)

                Spacer(minLength: 0)

                if let problem = appVM.attentionJourney.problem {
                    Text("Afterwards, your next step is waiting on Home: \u{201C}\(problem.actionTitle)\u{201D}.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                }

                Button {
                    HapticsService.selection()
                    finishOnboarding()
                } label: {
                    Text("Not now, go to Home")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)

                primaryButton(title: "Open \(firstOpeningApp?.title ?? "an app") now", enabled: true, loading: false) {
                    HapticsService.impact(style: .medium)
                    showFirstOpening = true
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
    }

    private func firstOpeningRow(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.deep)
                .frame(width: 26, height: 26)
                .background(Circle().fill(MivoColors.surfaceV2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The app named in "Which app pulls hardest?", else the first one picked
    /// in Apple's list. Nil lets the window flow ask, as it does from Home.
    private var firstOpeningApp: SocialApp? {
        if let answer = answers[1], let app = SocialApp(rawValue: answer) { return app }
        if let named = appVM.onboardingProfile.preferredApps.first,
           let app = SocialApp.allCases.first(where: { $0.title.caseInsensitiveCompare(named) == .orderedSame }) {
            return app
        }
        return SocialApp.allCases.first { chosenApps.contains($0) }
    }

    private var firstOpeningTitle: String {
        guard let app = firstOpeningApp else { return "Open one app the Mivo way" }
        return "Open \(app.title) the Mivo way"
    }

    /// Ends onboarding once, from either button. The swap is offered where it
    /// is used (the commitment screen and Settings) instead of as a prompt.
    private func finishOnboarding() {
        guard !isFinishing else { return }
        isFinishing = true
        HapticsService.success()
        if !replayMode, appVM.userSwap == nil {
            appVM.skipSwapPromptForNow()
        }
        appVM.completeOnboarding()
    }

    // MARK: Shared

    private func primaryButton(
        title: String,
        enabled: Bool,
        loading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 15.5, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(enabled ? MivoColors.accent : MivoColors.accent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(
                color: Color(red: 0.47, green: 0.27, blue: 0.08).opacity(enabled ? 0.30 : 0),
                radius: 2, y: 1
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
    }

    private func advance() {
        guard index < questions.count else { return }
        let item = questions[index]
        if item.requestsScreenTime {
            requestScreenTime()
            return
        }
        HapticsService.selection()
        index += 1
    }

    private func requestScreenTime() {
        isRequestingScreenTime = true
        FamilyControlsManager.shared.requestAuthorization { granted in
            Task { @MainActor in
                isRequestingScreenTime = false
                if granted {
                    HapticsService.success()
                    screenTimeAuthorized = true
                    adoptMeasuredBaseline()
                }
                index += 1
            }
        }
    }

    /// The spec's copy promises nothing is self-reported, so the baseline comes
    /// from Apple's own figure once access is granted. Left unset when there is
    /// no report yet — the plan text adapts rather than inventing a number.
    private func adoptMeasuredBaseline() {
        appVM.refreshScreenTimeData()
        guard let measured = appVM.screenTimeToday.minutes, measured > 0 else { return }
        var profile = appVM.onboardingProfile
        profile.scrollEstimateMinutes = measured
        appVM.saveOnboardingProfile(profile)
    }

    private func persist(_ option: OnboardingOption, for item: OnboardingQuestion) {
        var profile = appVM.onboardingProfile
        switch item.field {
        case .problem:
            if let problem = AttentionProblem(rawValue: option.id) {
                appVM.chooseAttentionProblem(problem)
            }
            if profile.pauseStyle == nil { profile.pauseStyle = .fiveSecond }
        case .tone:
            break
        case .app:
            profile.preferredApps = option.id == "other" ? [] : [option.label]
        case .timeOfDay:
            profile.primaryIntention = option.intention
            if let intention = option.intention, !profile.intentions.contains(intention) {
                profile.intentions.append(intention)
            }
        case .goal:
            profile.dailyScrollGoalMinutes = option.minutes
        case .pause:
            profile.pauseStyle = option.pauseStyle
        case .permission:
            break
        }
        appVM.saveOnboardingProfile(profile)
    }
}

// MARK: - Question content

private enum OnboardingField {
    case problem, tone, app, timeOfDay, goal, pause, permission
}

private struct OnboardingOption: Identifiable {
    let id: String
    let label: String
    var note: String? = nil
    var minutes: Int? = nil
    var pauseStyle: PauseStyle? = nil
    var intention: Intention? = nil
}

private struct OnboardingQuestion: Identifiable {
    let id: Int
    let field: OnboardingField
    let title: String
    let subtitle: String
    let options: [OnboardingOption]
    var footnote: String? = nil
    var ctaTitle: String = "Continue"
    var requiresAnswer: Bool = true
    var requestsScreenTime: Bool = false

    static let all: [OnboardingQuestion] = [
        OnboardingQuestion(
            id: 0, field: .problem,
            title: "What keeps getting in the way?",
            subtitle: "Choose one problem. Mivo will suggest a starting point.",
            options: AttentionProblem.allCases.map { OnboardingOption(id: $0.rawValue, label: $0.title) },
            footnote: "Your starting point stays on this device."
        ),
        OnboardingQuestion(
            id: 1, field: .app,
            title: "Which app pulls hardest?",
            subtitle: "We'll start with one and add more later.",
            options: [
                OnboardingOption(id: "instagram", label: "Instagram"),
                OnboardingOption(id: "tiktok", label: "TikTok"),
                OnboardingOption(id: "youtube", label: "YouTube"),
                OnboardingOption(id: "other", label: "Something else")
            ]
        ),
        OnboardingQuestion(
            id: 2, field: .permission,
            title: "Screen Time access",
            subtitle: "Connect Apple Screen Time to measure device use and protect the apps you choose. Your activity check-ins are labeled separately.",
            options: [],
            footnote: "You can revoke this in Settings at any time.",
            ctaTitle: "Allow access",
            requiresAnswer: false,
            requestsScreenTime: true
        )
    ]
}
