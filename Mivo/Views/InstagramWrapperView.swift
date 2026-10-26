import SwiftUI
import WebKit

/// What "opening Instagram" means when `FamilyControlsManager.isInstagramWrapperEnabled()`
/// is on: the ShieldAction extension intercepts the tap on the real Instagram
/// app (see `isInstagram(_:)` in the extension) and routes here instead of
/// the normal intervention flow. This screen owns a plain `WKWebView`
/// (never `SFSafariViewController`, which always shows a URL bar/toolbar
/// Apple won't let you remove) loading Instagram's own mobile site — so it
/// looks and scrolls like Instagram, because it genuinely is Instagram's
/// real page, just inside a view Mivo controls.
///
/// That control is the whole point: unlike the native Instagram app, Mivo
/// can listen for real events here (see `WrapperStatsWebView`) instead of
/// guessing — scroll bursts, actual `<video>` play events (the real proxy
/// for "reels watched"), taps, scroll distance, in-app navigations, and the
/// gaps between them. All of it becomes one `InstagramWrapperSession` and
/// shows on the Attention Receipt as measured data. What's deliberately
/// **not** tracked: the actual content on screen, anything typed, or who was
/// looked at — this measures behavior, not content. The one exception is
/// replay mode (see `ReplaySession`): it keeps the public shortcode of each
/// reel watched, on this device only and never uploaded, so it can show a
/// reel the person has already seen.
///
/// Periodically it also asks what was on screen a few real scrolls back
/// (`InstagramRecallPrompt`) — "occasional," not every scroll, never gated
/// on answering. And the whole thing is capped at a fixed session length:
/// the last stretch gets a plain warning, then it closes itself.
///
/// One small, permanent "Mivo" mark stays visible the whole time — not a
/// warning, just an honest signal of what this actually is.
struct InstagramWrapperView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// "The 5 mins" — how long a wrapper session runs before it closes
    /// itself, not an open-ended browsing session.
    private let sessionLengthSeconds = 300
    private let lastReelWarningSeconds = 20

    private let softEndPauseSeconds = 20
    private let balanceStore = ReelBalanceStore.shared

    private enum Phase: Equatable {
        case choosing
        case running
        case softEnd(SoftEndReason)
    }

    private enum SoftEndReason: Equatable {
        case reelsReached
        case balanceUsed
    }

    @ObservedObject private var plus = MivoPlusStore.shared
    @State private var showingPaywall = false
    @State private var phase: Phase = .choosing
    @State private var chosenLimit: WrapperSessionLimit = .reels
    @State private var dullMode = WrapperDullMode.isEnabled
    @State private var reelLimit = WrapperSessionLimit.reelsPerSession
    @State private var balance = ReelBalanceStore.shared.current()
    @State private var topUpWaitRemaining = 0
    @State private var unsavedBalanceSeconds = 0

    // Replay mode: swaps new reels for ones already watched. Held off while
    // the 3-day baseline is recorded so that baseline stays clean.
    @State private var observingBaseline = false
    @State private var replayActive = false
    @State private var replay = ReplaySession(log: SeenReelLog())
    @State private var replayCommand: ReplayCommand?
    @State private var isSwappingReel = false
    @State private var showingReplayNotice = false

    @State private var liveStats = WrapperLiveStats()
    @State private var secondsRemaining: Int
    @State private var sessionStartedAt = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showingLastReelWarning = false
    @State private var didFinish = false

    // "What was N reels ago?" — fires every 6–10 real scrolls, never inside
    // the last-reel warning window (that's interruption enough on its own).
    @State private var showingRecallPrompt = false
    @State private var recallScrollsAgo = 4
    @State private var recallAnswerText = ""
    @State private var scrollsSinceLastPrompt = 0
    @State private var nextPromptThreshold = Int.random(in: 6...10)
    @FocusState private var recallFieldFocused: Bool

    init() {
        _secondsRemaining = State(initialValue: 300)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if phase != .choosing {
                WrapperStatsWebView(
                    liveStats: $liveStats,
                    replayCommand: replayCommand,
                    isInteractive: !showingRecallPrompt && !isSoftEnd,
                    dullMode: dullMode,
                    onReel: handleReel
                )
                .ignoresSafeArea()

                if isSwappingReel {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(.white.opacity(0.5)))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }

            markAndCloseRow

            VStack {
                Spacer()
                if showingLastReelWarning {
                    lastReelBanner
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showingReplayNotice {
                    replayNoticeBanner
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if showingRecallPrompt {
                recallPromptOverlay
                    .transition(.opacity)
            }

            if case .softEnd(let reason) = phase {
                softEndOverlay(reason)
                    .transition(.opacity)
            }

            if phase == .choosing {
                if hasMivoPlus {
                    choiceOverlay
                        .transition(.opacity)
                } else {
                    lockedOverlay
                        .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            MivoPlusPaywallView(feature: .instagramInMivo)
                .environmentObject(appVM)
        }
        .statusBarHidden(false)
        .onAppear {
            MivoPlusStore.shared.start()
            observingBaseline = appVM.adaptiveScreenTimePlan().collecting
            #if DEBUG
            // Lets a debug build exercise replay mode inside the 3-day baseline.
            if ProcessInfo.processInfo.arguments.contains("-MivoReplayForce") { observingBaseline = false }
            #endif
        }
        .onReceive(timer) { _ in tick() }
        .onChange(of: liveStats.scrollBursts) { _, newValue in handleScrollCountChange(newValue) }
        .onChange(of: liveStats.distinctVideos) { _, newValue in handleReelCountChange(newValue) }
        .onDisappear {
            persistBalance()
            if phase != .choosing {
                SeenReelStore.shared.save(replay.log)
                recordSession()
            }
        }
    }

    private var hasMivoPlus: Bool {
        MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
    }

    /// Instagram in Mivo is a Plus feature; without it this is all that shows.
    private var lockedOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Instagram in Mivo is part of Plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Plus also unlocks replay mode and dull mode. \(MivoPlusCopy.basicPauseLine)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Button { showingPaywall = true } label: {
                    Text("See Mivo Plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }

                Button("Not now") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
        }
    }

    private var isSoftEnd: Bool {
        if case .softEnd = phase { return true }
        return false
    }

    private var markAndCloseRow: some View {
        HStack(spacing: 8) {
            if phase != .choosing {
                Text(minutesLeftText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
            }

            Text("Mivo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.35)))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }

    private var lastReelBanner: some View {
        Text("This is your last reel — closing in \(secondsRemaining)s")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.65)))
    }

    private var replayNoticeBanner: some View {
        Text(chosenLimit == .reels
             ? "That's your \(reelLimit). From here, only reels you've already seen."
             : "That's your time. From here, only reels you've already seen.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.65)))
    }

    private var minutesLeftText: String {
        let minutes = balance.remainingMinutes
        return minutes == 1 ? "1 minute left today" : "\(minutes) minutes left today"
    }

    // MARK: - Before the session

    private var choiceOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(balance.isEmpty ? "That's today's time" : "How long this time?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Text(balance.isEmpty ? "It comes back tomorrow." : minutesLeftText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                if !balance.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(WrapperSessionLimit.allCases, id: \.self) { limit in
                            Button { chosenLimit = limit } label: {
                                HStack {
                                    Text(limit.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    if chosenLimit == limit {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                }
                                .foregroundColor(chosenLimit == limit ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .frame(maxWidth: 260)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(chosenLimit == limit ? Color.white : Color.white.opacity(0.12)))
                            }
                        }
                    }

                    Toggle("Dull mode", isOn: $dullMode)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .tint(.white.opacity(0.5))
                        .frame(maxWidth: 260)
                        .onChange(of: dullMode) { _, newValue in WrapperDullMode.isEnabled = newValue }

                    Text("Dull mode: grayscale, sound off, no looping.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: 260, alignment: .leading)

                    Text(replayStatusText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: 260, alignment: .leading)

                    Button(action: startSession) {
                        Text("Open Instagram")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: 260)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    }
                }

                Button("Not now") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
        }
    }

    private var replayStatusText: String {
        guard ReplayModeSetting.isEnabled else { return "Replay mode is off. Turn it on from Home." }
        if observingBaseline { return "Replay mode starts after your first 3 days, once Mivo has seen how you scroll." }
        let used = chosenLimit == .reels ? "your \(WrapperSessionLimit.reelsPerSession) reels" : "your \(WrapperSessionLimit.minutesPerSession) minutes"
        return "Replay mode: once \(used) are used, you only see reels you've already watched."
    }

    private func startSession() {
        balance = balanceStore.current()
        guard !balance.isEmpty else { return }
        replayActive = ReplayModeSetting.isActive(enabled: ReplayModeSetting.isEnabled, observingBaseline: observingBaseline)
        replay = ReplaySession(log: SeenReelStore.shared.load())
        replayCommand = nil
        isSwappingReel = false
        showingReplayNotice = false
        reelLimit = WrapperSessionLimit.reelsPerSession
        let requested = chosenLimit == .minutes ? WrapperSessionLimit.minutesPerSession * 60 : sessionLengthSeconds
        // The hard cap stays an upper bound for either choice. Replay mode has no
        // hard stop to protect, so it lets the minutes the person chose run in full.
        let cap = replayActive && chosenLimit == .minutes ? requested : min(requested, sessionLengthSeconds)
        secondsRemaining = min(cap, balance.remainingSeconds)
        sessionStartedAt = Date()
        withAnimation(.easeOut(duration: 0.25)) { phase = .running }
    }

    // MARK: - Reel count and soft end

    private func handleReelCountChange(_ count: Int) {
        guard phase == .running, chosenLimit == .reels, count >= reelLimit else { return }
        if replayActive {
            beginReplay()
        } else {
            enterSoftEnd(.reelsReached)
        }
    }

    // MARK: - Replay mode

    /// The chosen reels or minutes are used up: from here every new reel is a
    /// repeat, until today's time runs out.
    private func beginReplay() {
        guard replayActive, !replay.isReplaying else { return }
        replay.startReplaying()
        HapticsService.impact(style: .medium)
        withAnimation(.easeOut(duration: 0.3)) {
            showingLastReelWarning = false
            showingReplayNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.easeIn(duration: 0.2)) { showingReplayNotice = false }
        }
    }

    private func handleReel(_ code: String) {
        guard phase == .running else { return }
        let hadPending = replay.pendingReplay != nil
        switch replay.observe(code, replayActive: replayActive, now: Date()) {
        case .replace(let target):
            replayCommand = ReplayCommand(code: target)
            withAnimation(.easeIn(duration: 0.15)) { isSwappingReel = true }
            let swapID = replayCommand?.id
            // Never leave the cover up if the replay fails to start.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard replayCommand?.id == swapID, isSwappingReel else { return }
                withAnimation(.easeOut(duration: 0.2)) { isSwappingReel = false }
            }
        case .none:
            if hadPending, replay.pendingReplay == nil, isSwappingReel {
                withAnimation(.easeOut(duration: 0.2)) { isSwappingReel = false }
            }
        }
        SeenReelStore.shared.save(replay.log)
    }

    private func enterSoftEnd(_ reason: SoftEndReason) {
        showingRecallPrompt = false
        showingLastReelWarning = false
        showingReplayNotice = false
        topUpWaitRemaining = softEndPauseSeconds
        HapticsService.impact(style: .light)
        withAnimation(.easeOut(duration: 0.25)) { phase = .softEnd(reason) }
    }

    private var canTopUp: Bool {
        !balance.isEmpty && secondsRemaining > 0
    }

    private func softEndOverlay(_ reason: SoftEndReason) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 14) {
                switch reason {
                case .reelsReached:
                    Text("\(reelLimit) seen.")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    if canTopUp {
                        Text("Want \(WrapperSessionLimit.extraReelsPerTopUp) more?")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Button(action: topUp) {
                            Text(topUpWaitRemaining > 0 ? "\(WrapperSessionLimit.extraReelsPerTopUp) more in \(topUpWaitRemaining)s" : "\(WrapperSessionLimit.extraReelsPerTopUp) more")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: 260)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(topUpWaitRemaining > 0 ? 0.35 : 1)))
                        }
                        .disabled(topUpWaitRemaining > 0)
                    }
                case .balanceUsed:
                    Text("That's today's time.")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    Text("It comes back tomorrow.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }

                Button("I'm done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.14)))
            }
            .padding(.horizontal, 24)
        }
    }

    private func topUp() {
        guard topUpWaitRemaining == 0, canTopUp else { return }
        reelLimit += WrapperSessionLimit.extraReelsPerTopUp
        withAnimation(.easeIn(duration: 0.2)) { phase = .running }
    }

    private func persistBalance() {
        guard unsavedBalanceSeconds > 0 else { return }
        balanceStore.save(balance)
        unsavedBalanceSeconds = 0
    }

    // MARK: - Session timer

    private func tick() {
        if case .softEnd = phase {
            if topUpWaitRemaining > 0 { topUpWaitRemaining -= 1 }
            return
        }
        guard phase == .running, !didFinish, secondsRemaining > 0 || replayActive else { return }
        if secondsRemaining > 0 { secondsRemaining -= 1 }

        balance = balance.rolled(to: Date())
        if balance.spend(seconds: 1) > 0 { unsavedBalanceSeconds += 1 }
        if unsavedBalanceSeconds >= 5 { persistBalance() }
        if balance.isEmpty {
            persistBalance()
            enterSoftEnd(.balanceUsed)
            return
        }

        if secondsRemaining == lastReelWarningSeconds, !replayActive {
            HapticsService.impact(style: .medium)
            withAnimation(.easeOut(duration: 0.3)) {
                showingLastReelWarning = true
            }
        }

        if secondsRemaining <= 0 {
            if replayActive {
                beginReplay()
                return
            }
            didFinish = true
            HapticsService.impact(style: .heavy)
            dismiss()
        }
    }

    // MARK: - "What was N reels ago?"

    private func handleScrollCountChange(_ newValue: Int) {
        guard phase == .running, !showingRecallPrompt, !didFinish else { return }
        // Don't interrupt once the last-reel warning is already up — that's
        // its own signal, stacking a recall prompt on top just feels like nagging.
        guard secondsRemaining > lastReelWarningSeconds else { return }

        scrollsSinceLastPrompt += 1
        guard scrollsSinceLastPrompt >= nextPromptThreshold else { return }

        scrollsSinceLastPrompt = 0
        nextPromptThreshold = Int.random(in: 6...10)
        recallScrollsAgo = min(newValue, Int.random(in: 3...5))
        recallAnswerText = ""
        HapticsService.impact(style: .light)
        withAnimation(.easeOut(duration: 0.25)) {
            showingRecallPrompt = true
        }
    }

    private func submitRecallAnswer() {
        recallFieldFocused = false
        appVM.recordInstagramRecallPrompt(scrollsAgo: recallScrollsAgo, answer: recallAnswerText)
        withAnimation(.easeIn(duration: 0.2)) {
            showingRecallPrompt = false
        }
    }

    private var recallPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* absorb taps — deliberate, not dismiss-on-outside-tap */ }

            VStack(spacing: 14) {
                Text("Quick one —")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text("What was on screen \(recallScrollsAgo) reels ago?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                TextField("", text: $recallAnswerText, prompt: Text("Not sure / can't remember")
                    .foregroundColor(.white.opacity(0.35)))
                    .focused($recallFieldFocused)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12)))
                    .frame(maxWidth: 260)
                    .submitLabel(.done)

                Button(action: submitRecallAnswer) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Recording

    private func recordSession() {
        appVM.recordInstagramWrapperSession(
            startedAt: sessionStartedAt,
            scrollCount: liveStats.scrollBursts,
            videoPlayCount: liveStats.videoPlays,
            videoWatchSeconds: Int(liveStats.videoSeconds.rounded()),
            tapCount: liveStats.taps,
            scrollDistancePoints: Int(liveStats.scrollDistance.rounded()),
            sectionChanges: liveStats.sectionChanges,
            longestPauseSeconds: Int((liveStats.longestPauseMs / 1000).rounded()),
            firstScrollDelaySeconds: liveStats.firstScrollDelayMs < 0 ? 0 : Int((liveStats.firstScrollDelayMs / 1000).rounded()),
            replayActive: replayActive,
            freshReelCount: replay.freshReels,
            repeatReelCount: replay.repeatsSeen,
            replacedReelCount: replay.repeatsServed
        )
    }
}

/// One periodic snapshot from the injected script — see
/// `WrapperStatsWebView.statsScript`. Decoded fresh every ~400ms; the
/// defaults here are only ever seen before the first snapshot arrives.
private struct WrapperLiveStats: Decodable {
    var scrollBursts: Int = 0
    var scrollDistance: Double = 0
    var taps: Int = 0
    var videoPlays: Int = 0
    var distinctVideos: Int = 0
    var videoSeconds: Double = 0
    var sectionChanges: Int = 0
    var firstScrollDelayMs: Double = -1
    var longestPauseMs: Double = 0

    /// Totals across page loads. The injected script counts from zero on every
    /// full page load (replaying a reel is one), so the finished loads are
    /// carried forward and the current load's snapshot is added to them.
    func adding(_ next: WrapperLiveStats) -> WrapperLiveStats {
        var total = self
        total.scrollBursts += next.scrollBursts
        total.scrollDistance += next.scrollDistance
        total.taps += next.taps
        total.videoPlays += next.videoPlays
        total.distinctVideos += next.distinctVideos
        total.videoSeconds += next.videoSeconds
        total.sectionChanges += next.sectionChanges
        if total.firstScrollDelayMs < 0 { total.firstScrollDelayMs = next.firstScrollDelayMs }
        total.longestPauseMs = max(total.longestPauseMs, next.longestPauseMs)
        return total
    }
}

/// One instruction to load a reel the person has already watched. The id
/// makes it one-shot: the web view acts on each id once.
private struct ReplayCommand: Equatable {
    let id = UUID()
    let code: String
}

/// Bare `WKWebView` — deliberately not `SFSafariViewController`, which
/// always renders a URL bar and "Done"/share chrome Apple doesn't let you
/// strip. A plain `WKWebView` has none of that by default, so "feels like
/// an app, not a browser" is mostly a matter of not adding any ourselves.
private struct WrapperStatsWebView: UIViewRepresentable {
    @Binding var liveStats: WrapperLiveStats
    /// The latest reel to load for replay mode; each command is acted on once.
    var replayCommand: ReplayCommand?
    /// False while the recall prompt overlay is up, so scrolling behind it
    /// can't keep incrementing stats (or keep advancing reels) while the
    /// person is meant to be answering, not scrolling.
    var isInteractive: Bool
    var dullMode: Bool
    /// Called with the shortcode of each reel the page starts playing.
    var onReel: (String) -> Void

    /// Reports which reel is playing, and nothing else about it: the public
    /// shortcode from the nearest link to the playing video, or, when that
    /// finds nothing, from the page address if the video is the page's main
    /// one. A container that links to more than one reel is ambiguous and
    /// reports nothing, so a wrong reel is never recorded.
    private static let reelScript = """
    (function() {
        if (window.__mivoReelCapture) return;
        window.__mivoReelCapture = true;
        var CODE = /\\/(?:reels?)\\/([A-Za-z0-9_-]{8,16})(?:[\\/?#]|$)/;
        function codeOf(href) { var m = CODE.exec(href || ''); return m ? m[1] : null; }

        function codeNear(video) {
            var node = video.parentElement;
            for (var depth = 0; node && node !== document.body && depth < 12; depth++, node = node.parentElement) {
                var links = node.querySelectorAll('a[href]');
                var found = null;
                for (var i = 0; i < links.length; i++) {
                    var c = codeOf(links[i].getAttribute('href'));
                    if (!c) continue;
                    if (found && found !== c) return null;
                    found = c;
                }
                if (found) return found;
            }
            return null;
        }

        var last = null;
        function report(video) {
            var code = codeNear(video);
            if (!code) {
                var videos = document.getElementsByTagName('video');
                if (videos.length === 1 || videos[0] === video) code = codeOf(location.pathname);
            }
            if (!code || code === last) return;
            last = code;
            window.webkit.messageHandlers.mivoReel.postMessage(code);
        }

        document.addEventListener('playing', function(e) {
            if (e.target && e.target.tagName === 'VIDEO') report(e.target);
        }, true);
    })();
    """

    /// Dull mode: a separate script from the stats one, and it never reads
    /// the page — it only styles it and sets media properties. Grayscale via
    /// CSS, videos muted once when first seen (so the person can still
    /// unmute), looping switched off, including for videos added later.
    private static let dullScript = """
    (function() {
        var style = document.createElement('style');
        style.textContent = 'html { filter: grayscale(1) !important; }';
        (document.head || document.documentElement).appendChild(style);

        function dull(video) {
            if (!video.__mivoDulled) {
                video.__mivoDulled = true;
                video.muted = true;
                video.addEventListener('loadstart', function() { video.muted = true; });
            }
            video.loop = false;
            video.removeAttribute('loop');
        }
        function dullAll(root) {
            if (root.tagName === 'VIDEO') dull(root);
            if (root.querySelectorAll) root.querySelectorAll('video').forEach(dull);
        }
        dullAll(document);
        new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                if (m.type === 'attributes') { if (m.target.tagName === 'VIDEO') dull(m.target); return; }
                m.addedNodes.forEach(function(node) { dullAll(node); });
            });
        }).observe(document.documentElement, {
            childList: true, subtree: true, attributes: true, attributeFilter: ['loop']
        });
    })();
    """

    /// Everything measurable, kept as one running object and flushed as a
    /// single JSON snapshot every 400ms, rather than one `postMessage` per
    /// raw event — scroll/video events fire far too often for that to be
    /// cheap. Real DOM/media events only: no page content, no typed text,
    /// no identifiers — behavior, not content.
    private static let statsScript = """
    (function() {
        var stats = {
            scrollBursts: 0,
            scrollDistance: 0,
            taps: 0,
            videoPlays: 0,
            distinctVideos: 0,
            videoSeconds: 0,
            sectionChanges: 0,
            firstScrollDelayMs: -1,
            longestPauseMs: 0
        };
        var pageLoadAt = Date.now();
        var lastScrollY = window.scrollY || 0;
        var lastScrollAt = null;
        var pendingBurst = false;

        document.addEventListener('scroll', function() {
            var y = window.scrollY || document.documentElement.scrollTop || 0;
            stats.scrollDistance += Math.abs(y - lastScrollY);
            lastScrollY = y;
            pendingBurst = true;

            var now = Date.now();
            if (stats.firstScrollDelayMs === -1) {
                stats.firstScrollDelayMs = now - pageLoadAt;
            }
            if (lastScrollAt !== null) {
                var gap = now - lastScrollAt;
                if (gap > stats.longestPauseMs) stats.longestPauseMs = gap;
            }
            lastScrollAt = now;
        }, true);

        document.addEventListener('click', function() { stats.taps += 1; }, true);

        var playingSince = new WeakMap();
        function trackVideo(video) {
            if (video.__mivoTracked) return;
            video.__mivoTracked = true;
            video.addEventListener('play', function() {
                stats.videoPlays += 1;
                if (!video.__mivoCounted) {
                    video.__mivoCounted = true;
                    stats.distinctVideos += 1;
                }
                playingSince.set(video, Date.now());
            });
            function flush() {
                var since = playingSince.get(video);
                if (since) {
                    stats.videoSeconds += (Date.now() - since) / 1000;
                    playingSince.delete(video);
                }
            }
            video.addEventListener('pause', flush);
            video.addEventListener('ended', flush);
        }
        document.querySelectorAll('video').forEach(trackVideo);
        new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                m.addedNodes.forEach(function(node) {
                    if (!node.querySelectorAll) return;
                    if (node.tagName === 'VIDEO') trackVideo(node);
                    node.querySelectorAll('video').forEach(trackVideo);
                });
            });
        }).observe(document.documentElement, { childList: true, subtree: true });

        var originalPushState = history.pushState;
        history.pushState = function() {
            stats.sectionChanges += 1;
            return originalPushState.apply(this, arguments);
        };
        window.addEventListener('popstate', function() { stats.sectionChanges += 1; });

        setInterval(function() {
            if (pendingBurst) {
                pendingBurst = false;
                stats.scrollBursts += 1;
            }
            window.webkit.messageHandlers.mivoStats.postMessage(JSON.stringify(stats));
        }, 400);
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(liveStats: $liveStats, onReel: onReel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Mivo's Info.plist lists Instagram under `WKAppBoundDomains`. iOS only
        // lets scripts run in a web view that opts in, so without this the
        // stats, dull mode and reel scripts never ran on Instagram at all.
        configuration.limitsNavigationsToAppBoundDomains = true
        let userScript = WKUserScript(
            source: Self.statsScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)
        if dullMode {
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.dullScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.reelScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: "mivoStats")
        configuration.userContentController.add(context.coordinator, name: "mivoReel")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // A mobile Safari UA so Instagram serves its mobile web layout
        // (feed/reels/profile) instead of the desktop site.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = isInteractive
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.isUserInteractionEnabled = isInteractive
        context.coordinator.onReel = onReel
        if let command = replayCommand, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            if let url = ReelCode.url(for: command.code) {
                uiView.load(URLRequest(url: url))
            }
        }
    }

    /// `WKUserContentController.add(_:name:)` retains the handler — without
    /// removing it here, the controller (and everything it retains) can
    /// outlive the view being torn down, and the injected script's
    /// `setInterval` keeps running against a screen nobody can see. This is
    /// the documented `UIViewRepresentable` teardown hook for exactly that.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mivoStats")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mivoReel")
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let liveStats: Binding<WrapperLiveStats>
        private let decoder = JSONDecoder()
        var onReel: (String) -> Void
        var lastCommandID: UUID?

        /// Totals from page loads that already finished, and the latest
        /// snapshot from the current one. A full page load restarts the
        /// injected script's counters, so they are added up here instead.
        private var carried = WrapperLiveStats()
        private var latest = WrapperLiveStats()

        init(liveStats: Binding<WrapperLiveStats>, onReel: @escaping (String) -> Void) {
            self.liveStats = liveStats
            self.onReel = onReel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            carried = carried.adding(latest)
            latest = WrapperLiveStats()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? String else { return }
            switch message.name {
            case "mivoStats":
                guard let data = body.data(using: .utf8),
                      let decoded = try? decoder.decode(WrapperLiveStats.self, from: data) else { return }
                latest = decoded
                let total = carried.adding(decoded)
                DispatchQueue.main.async { [liveStats] in
                    liveStats.wrappedValue = total
                }
            case "mivoReel":
                guard ReelCode.isValid(body) else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onReel(body)
                }
            default:
                break
            }
        }
    }
}

/// The one stored preference for the wrapper: dull mode, on unless turned off.
enum WrapperDullMode {
    private static let key = "mivo.wrapper.dullMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
