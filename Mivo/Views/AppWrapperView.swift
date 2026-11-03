import OSLog
import SwiftUI
import WebKit

private let wrapperLog = Logger(subsystem: "app.mivo.com", category: "AppWrapper")

/// How every social app opens now: the shield on the real app routes into Mivo,
/// the window flow (`InterventionFlowView`) asks which app, what for and how
/// much, and this screen opens that app's own mobile website in a plain
/// `WKWebView` (never `SFSafariViewController`, which always shows a URL bar
/// Apple won't let you remove). It looks and scrolls like the app because it
/// genuinely is the app's own page, just inside a view Mivo controls.
///
/// That control is the point. Mivo listens for real events (see
/// `WrapperStatsWebView`): scrolls, `<video>` plays, taps, navigations, and
/// which part of the app each page is (`SocialApp.section(for:)`). What's
/// deliberately **not** tracked: what's on screen, anything typed, or who was
/// looked at. This measures behaviour, not content. The one exception is
/// Instagram's replay mode (see `ReplaySession`), which keeps the public
/// shortcode of each reel watched, on this device only.
///
/// What was picked decides the rest:
/// - Short videos (Reels, Shorts, For You, Spotlight) are counted. Only the
///   video feed is reachable, and each video's time on screen is recorded for
///   `ReelAttentionReport`.
/// - Minutes open the whole app. Time spent somewhere other than what they
///   said they came for gets a reminder ("You came to watch long videos. This
///   is Shorts.") and is recorded.
/// - Messages are unlimited and free, and nothing but messages is reachable.
///
/// Once the pick (or today's balance) is used nothing closes; it slows down.
/// Short videos go grey and quiet and each opens in the iPhone's full-screen
/// player behind a short pause; the whole app goes grey, quiet and laggy.
/// Slowing down rather than stopping is the point: a hard stop is the thing
/// people switch off. Once slowed down it also asks, now and then, what was on
/// screen a few scrolls back (`InstagramRecallPrompt`).
struct AppWrapperView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let config: AppWindowConfig

    /// The beat between one video and the next once short videos have slowed down.
    private let betweenReelsPauseSeconds = 3
    /// Seconds somewhere else before the first reminder, then between reminders
    /// if they choose to keep going.
    static let firstReminderSeconds = 20
    static let repeatReminderSeconds = 90
    private let balanceStore = ReelBalanceStore.shared

    /// What was used up, which decides what the slow-down notice says.
    private enum SlowDownReason: Equatable {
        case pickUsed
        case todayUsed
        case outsideWindow

        var storedCause: String {
            switch self {
            case .pickUsed: return "pick"
            case .todayUsed: return "today"
            case .outsideWindow: return "window"
            }
        }
    }

    @ObservedObject private var plus = MivoPlusStore.shared
    @State private var started = false
    @State private var balance = ReelBalanceStore.shared.current()
    @State private var betweenReelsRemaining = 0
    @State private var unsavedBalanceSeconds = 0
    @State private var slowDownReason: SlowDownReason?
    @State private var showingSlowDownNotice = false

    // Replay mode (Instagram Reels only): swaps new reels for ones already
    // watched. Held off while the 3-day baseline is recorded.
    @State private var observingBaseline = false
    @State private var replayActive = false
    @State private var replay = ReplaySession(log: SeenReelLog())
    @State private var isSwappingReel = false
    @State private var loadCommand: WrapperLoadCommand?

    @State private var liveStats = WrapperLiveStats()
    /// Normal-speed seconds left on a minutes pick.
    @State private var secondsRemaining = 0
    @State private var sessionStartedAt = Date()

    // How long each short video stayed on screen at normal speed, and where
    // the session was when it slowed down.
    @State private var reelStartedAt: Date?
    @State private var reelSeconds: [Double] = []
    @State private var reelsAtSlowdown: Int?
    @State private var slowedAt: Date?
    private let maxTimedReels = 300

    // Where they are, and whether that's what they came for.
    @State private var section: AppSection = .other
    @State private var sectionSeconds: [AppSection: Int] = [:]
    @State private var offPurposeSeconds = 0
    @State private var offPurposeStreak = 0
    @State private var nextReminderAt = AppWrapperView.firstReminderSeconds
    @State private var reminderSection: AppSection?
    @State private var reminderCount = 0
    @State private var returnedCount = 0
    @State private var blockedCount = 0
    /// The page couldn't load even after one automatic retry.
    @State private var loadFailed = false

    // Studying left for this app: named on opening, the way back on closing.
    @State private var escape: StudyEscape?
    @State private var showingEscapeNotice = false
    @State private var returnedToStudy = false
    // One tap on the way out: how the session left them.
    @State private var showingEndCard = false
    @State private var feeling: SessionFeeling?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // "What was N videos ago?", every 6–10 real scrolls once slowed down.
    @State private var showingRecallPrompt = false
    @State private var recallScrollsAgo = 4
    @State private var recallAnswerText = ""
    @State private var scrollsSinceLastPrompt = 0
    @State private var nextPromptThreshold = Int.random(in: 6...10)
    @FocusState private var recallFieldFocused: Bool

    private var app: SocialApp { config.app }
    private var purpose: AppPurpose { config.purpose }
    private var isMessages: Bool { purpose.kind == .messages }
    private var isCount: Bool { purpose.kind == .count }

    var body: some View {
        ZStack {
            // The system background, so the status bar stays readable in light and dark mode.
            Color(.systemBackground).ignoresSafeArea()

            // Mivo's own strip sits above the page, never over it: every site
            // keeps its header buttons in the top corners.
            VStack(spacing: 0) {
                markAndCloseRow
                if started {
                    webView
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Spacer()
                }
            }

            if started {
                if loadFailed {
                    loadFailedOverlay
                        .transition(.opacity)
                }

                if isSwappingReel {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(.white.opacity(0.5)))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if betweenReelsRemaining > 0 {
                    betweenReelsOverlay
                        .transition(.opacity)
                }
            }

            VStack {
                Spacer()
                if showingSlowDownNotice, let slowDownReason {
                    slowDownNotice(slowDownReason)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if let reminderSection {
                reminderOverlay(reminderSection)
                    .transition(.opacity)
            }

            if showingRecallPrompt {
                recallPromptOverlay
                    .transition(.opacity)
            }

            if showingEscapeNotice, let escape {
                escapeNotice(escape)
                    .transition(.opacity)
            }

            if showingEndCard {
                endCard
                    .transition(.opacity)
            }
        }
        .statusBarHidden(false)
        .onAppear {
            guard !started else { return }
            MivoPlusStore.shared.start()
            observingBaseline = appVM.adaptiveScreenTimePlan().collecting
            #if DEBUG
            // Lets a debug build exercise replay mode inside the 3-day baseline.
            if ProcessInfo.processInfo.arguments.contains("-MivoReplayForce") { observingBaseline = false }
            #endif
            // Messages are allowed any time; everything else opened straight
            // from studying gets named.
            if !isMessages, let detected = StudyService.shared.currentEscape() {
                escape = detected
                showingEscapeNotice = true
            }
            startSession()
        }
        .onReceive(timer) { _ in tick() }
        .onChange(of: liveStats.scrollBursts) { _, newValue in handleScrollCountChange(newValue) }
        .onChange(of: liveStats.distinctVideos) { oldValue, newValue in
            timeReels(from: oldValue, to: newValue)
            handleReelCountChange(newValue)
        }
        .onChange(of: section) { oldValue, newValue in
            // A video left by moving to another part of the app was watched until now.
            if oldValue == .shortVideo, newValue != .shortVideo { closeCurrentReel(at: Date()) }
        }
        .onDisappear {
            persistBalance()
            guard started else { return }
            // The video on screen when they left counts: they watched it until then.
            if slowDownReason == nil { closeCurrentReel(at: Date()) }
            if ShortVideoID.supportsReplay(app) { SeenReelStore.forApp(app).save(replay.log) }
            recordSession()
            if returnedToStudy { reopenStudy() }
        }
    }

    private var webView: some View {
        WrapperStatsWebView(
            liveStats: $liveStats,
            app: app,
            purpose: purpose,
            loadCommand: loadCommand,
            slowdown: slowdown,
            isInteractive: !showingRecallPrompt && betweenReelsRemaining == 0 && reminderSection == nil
                && !showingEscapeNotice && !showingEndCard,
            reportsReels: app == .instagram && !isMessages,
            onReel: handleReel,
            onLocation: locationChanged,
            onBlocked: { blockedCount += 1 },
            onLoadFailed: { withAnimation(.easeOut(duration: 0.2)) { loadFailed = true } }
        )
    }

    private var loadFailedOverlay: some View {
        VStack(spacing: 10) {
            Text("\(app.title) didn't load.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            Text("Check your connection, then try again.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(.secondary)
            Button {
                withAnimation(.easeIn(duration: 0.15)) { loadFailed = false }
                if let url = app.startURL(for: purpose) { loadCommand = WrapperLoadCommand(url: url) }
            } label: {
                Text("Try again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.systemBackground))
                    .frame(maxWidth: 220)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary))
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
        .padding(.top, 36)
    }

    private var hasMivoPlus: Bool {
        MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
    }

    private var slowdown: WrapperSlowdown {
        guard slowDownReason != nil else { return .none }
        return isCount ? .reels : .site
    }

    private var markAndCloseRow: some View {
        HStack(spacing: 8) {
            Text("Mivo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            if started {
                Text(progressText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .accessibilityLabel("Close \(app.title)")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var progressText: String {
        if isMessages { return "Messages only" }
        if slowDownReason != nil { return "Slowed down" }
        switch purpose.kind {
        case .count:
            return "\(min(liveStats.distinctVideos, config.amount)) of \(app.shortVideoCount(config.amount))"
        case .minutes:
            let minutes = (secondsRemaining + 59) / 60
            return minutes == 1 ? "1 minute left" : "\(minutes) minutes left"
        case .messages, .nativeApp:
            return app.title
        }
    }

    private func slowDownNotice(_ reason: SlowDownReason) -> some View {
        VStack(spacing: 4) {
            Text(slowDownTitle(reason))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("\(CompanionStateManager.shared.miloName): \(slowDownMiloLine(reason))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.7)))
        .padding(.horizontal, 24)
    }

    private func slowDownTitle(_ reason: SlowDownReason) -> String {
        let used: String
        switch reason {
        case .pickUsed: used = "That's your \(pickTitle)."
        case .todayUsed: used = "That's today's time."
        case .outsideWindow: used = "You're outside your scroll windows."
        }
        return used + (replay.isReplaying ? " From here it's slower, and only \(app.shortVideoName.many) you've seen." : " From here it's slower.")
    }

    private func slowDownMiloLine(_ reason: SlowDownReason) -> String {
        switch reason {
        case .pickUsed: return isCount ? MiloBreakVoice.reelsSeen : MiloBreakVoice.minutesUsed
        case .todayUsed: return MiloBreakVoice.timeUsed
        case .outsideWindow: return MiloBreakVoice.outsideWindow
        }
    }

    private var pickTitle: String {
        isCount ? app.shortVideoCount(config.amount) : WrapperSessionLimit.minutes.title(amount: config.amount)
    }

    // MARK: - Starting

    private func startSession() {
        balance = balanceStore.current()
        replayActive = ShortVideoID.supportsReplay(app) && isCount && hasMivoPlus
            && ReplayModeSetting.isActive(enabled: ReplayModeSetting.isEnabled, observingBaseline: observingBaseline)
        replay = ReplaySession(log: ShortVideoID.supportsReplay(app) ? SeenReelStore.forApp(app).load() : SeenReelLog())
        secondsRemaining = config.amount * 60
        sessionStartedAt = Date()
        started = true
        // Messages are free and never slow down. Everything else opens already
        // slowed outside a scroll window, or with nothing left today.
        guard !isMessages else { return }
        if config.startsSlowed {
            slowDown(.outsideWindow)
        } else if balance.isEmpty {
            slowDown(.todayUsed)
        }
    }

    // MARK: - Counting and slowing down

    private func handleReelCountChange(_ count: Int) {
        guard started, isCount else { return }
        guard slowDownReason != nil else {
            if count >= config.amount { slowDown(.pickUsed) }
            return
        }
        // Once slowed down, every new video starts behind a short pause.
        guard !replay.isReplaying else { return }
        withAnimation(.easeIn(duration: 0.15)) { betweenReelsRemaining = betweenReelsPauseSeconds }
    }

    private var betweenReelsOverlay: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Next one in \(betweenReelsRemaining)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text("Did you want that one?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    /// The pick (or today's balance) is used. Nothing closes: from here the
    /// web view slows down, and with replay mode on only repeats are served.
    private func slowDown(_ reason: SlowDownReason) {
        guard slowDownReason == nil, !isMessages else { return }
        reelsAtSlowdown = liveStats.distinctVideos
        slowedAt = Date()
        // Timing stops here: slowed-down viewing is distorted on purpose.
        closeCurrentReel(at: Date())
        persistBalance()
        if replayActive, !replay.isReplaying { replay.startReplaying() }
        HapticsService.impact(style: .medium)
        withAnimation(.easeOut(duration: 0.3)) {
            slowDownReason = reason
            showingSlowDownNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation(.easeIn(duration: 0.2)) { showingSlowDownNotice = false }
        }
    }

    // MARK: - Timing each short video

    /// A new video started: the one before it was on screen until now. Only
    /// short videos are timed, at normal speed; several starting inside one
    /// stats tick were each left almost at once, so they count as near-zero.
    private func timeReels(from old: Int, to new: Int) {
        guard started, new > old, slowDownReason == nil, section == .shortVideo else {
            reelStartedAt = nil
            return
        }
        let now = Date()
        if reelStartedAt != nil {
            closeCurrentReel(at: now)
            for _ in 0..<(new - old - 1) where reelSeconds.count < maxTimedReels {
                reelSeconds.append(0.4)
            }
        }
        reelStartedAt = now
    }

    private func closeCurrentReel(at now: Date) {
        guard let started = reelStartedAt else { return }
        reelStartedAt = nil
        guard reelSeconds.count < maxTimedReels else { return }
        reelSeconds.append(now.timeIntervalSince(started))
    }

    // MARK: - Replay mode

    /// Every reel seen goes in the log, replay mode on or not, so there are
    /// repeats to serve once it is on.
    private func handleReel(_ code: String) {
        guard started else { return }
        let hadPending = replay.pendingReplay != nil
        switch replay.observe(code, replayActive: replayActive, now: Date()) {
        case .replace(let target):
            guard let url = ShortVideoID.url(for: target, app: app) else { break }
            loadCommand = WrapperLoadCommand(url: url)
            withAnimation(.easeIn(duration: 0.15)) { isSwappingReel = true }
            let swapID = loadCommand?.id
            // Never leave the cover up if the replay fails to start.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard loadCommand?.id == swapID, isSwappingReel else { return }
                withAnimation(.easeOut(duration: 0.2)) { isSwappingReel = false }
            }
        case .none:
            if hadPending, replay.pendingReplay == nil, isSwappingReel {
                withAnimation(.easeOut(duration: 0.2)) { isSwappingReel = false }
            }
        }
        SeenReelStore.forApp(app).save(replay.log)
    }

    private func persistBalance() {
        guard unsavedBalanceSeconds > 0 else { return }
        balanceStore.save(balance)
        unsavedBalanceSeconds = 0
    }

    // MARK: - Every second

    private func tick() {
        guard started else { return }
        if betweenReelsRemaining > 0 {
            withAnimation(.easeOut(duration: 0.15)) { betweenReelsRemaining -= 1 }
        }
        trackSection()
        guard !isMessages else { return }

        // Time in here spends today's balance, slowed down or not.
        balance = balance.rolled(to: Date())
        if balance.spend(seconds: 1) > 0 { unsavedBalanceSeconds += 1 }
        if unsavedBalanceSeconds >= 5 { persistBalance() }

        guard slowDownReason == nil else { return }
        if purpose.kind == .minutes, secondsRemaining > 0 { secondsRemaining -= 1 }
        if balance.isEmpty {
            slowDown(.todayUsed)
        } else if purpose.kind == .minutes, secondsRemaining == 0 {
            slowDown(.pickUsed)
        }
    }

    // MARK: - Doing what they came for

    /// Adds this second to the section on screen, and reminds them once they've
    /// spent a while somewhere other than what they said they came for.
    private func trackSection() {
        sectionSeconds[section, default: 0] += 1
        guard purpose.isDrifting(in: section) else {
            offPurposeStreak = 0
            nextReminderAt = Self.firstReminderSeconds
            return
        }
        offPurposeSeconds += 1
        offPurposeStreak += 1
        // Count and messages purposes lock everything else away; only a
        // minutes purpose can wander far enough to need reminding.
        guard purpose.kind == .minutes, reminderSection == nil, !showingRecallPrompt,
              offPurposeStreak >= nextReminderAt else { return }
        reminderCount += 1
        HapticsService.impact(style: .light)
        withAnimation(.easeOut(duration: 0.25)) { reminderSection = section }
    }

    private func reminderOverlay(_ drifted: AppSection) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* absorb taps: this needs a choice */ }

            VStack(spacing: 12) {
                Text("You came to \(purpose.goal).")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("This is \(app.name(of: drifted)). You've been here \(durationText(offPurposeStreak)).")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                Button(action: returnToPurpose) {
                    Text(purpose.backLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
                .padding(.top, 6)

                Button(action: keepGoing) {
                    Text("Keep going")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: 260)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Where the page is

    /// Every page and in-page move: which part of the app it is, and for the
    /// apps whose address names the video (Shorts, Facebook Reels, Spotlight),
    /// which video, for replay mode. Instagram reports its reels from the page.
    private func locationChanged(_ url: URL) {
        section = app.section(for: url)
        guard app != .instagram, !isMessages, let id = ShortVideoID.id(in: url, app: app) else { return }
        handleReel(id)
    }

    // MARK: - Studying, and the way out

    private func escapeNotice(_ escape: StudyEscape) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* absorb taps: this needs a choice */ }

            VStack(spacing: 12) {
                Text(escape.headline)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(escape.midSession
                     ? "Your study session is still running."
                     : "Opening \(app.title) right after is often a way out of how the work feels.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                Button(action: returnToStudy) {
                    Text("Back to \(escape.task)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
                .padding(.top, 6)

                Button {
                    HapticsService.selection()
                    withAnimation(.easeIn(duration: 0.2)) { showingEscapeNotice = false }
                } label: {
                    Text("Open \(app.title) anyway")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: 260)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 24)
        }
    }

    /// One tap on how the session left them, and the way back to studying if
    /// they came from it. Messages skip it: they aren't the problem.
    private var endCard: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* absorb taps */ }

            VStack(spacing: 14) {
                Text("How do you feel now?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    ForEach(SessionFeeling.allCases, id: \.self) { option in
                        Button {
                            HapticsService.selection()
                            feeling = option
                            if escape == nil { dismiss() }
                        } label: {
                            Text(option.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(feeling == option ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(feeling == option ? Color.white : Color.white.opacity(0.14)))
                        }
                    }
                }
                .frame(maxWidth: 280)

                if let escape {
                    Button(action: returnToStudy) {
                        Text("Back to \(escape.task)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    }
                    .padding(.top, 4)
                    Text("Even two minutes counts.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Button {
                    dismiss()
                } label: {
                    Text(feeling == nil ? "Skip" : "Close")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: 260)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 24)
        }
    }

    private func close() {
        guard started, !isMessages else {
            dismiss()
            return
        }
        HapticsService.selection()
        withAnimation(.easeOut(duration: 0.2)) {
            reminderSection = nil
            showingRecallPrompt = false
            showingEndCard = true
        }
    }

    private func returnToStudy() {
        HapticsService.success()
        returnedToStudy = true
        dismiss()
    }

    /// Opens the study screen once this one (and the window flow under it)
    /// has gone, with what they were studying already filled in.
    private func reopenStudy() {
        let task = escape?.midSession == true ? nil : escape?.task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let study = StudyService.shared
            if let task { study.suggestedTask = task }
            study.showRequested = true
        }
    }

    private func returnToPurpose() {
        returnedCount += 1
        offPurposeStreak = 0
        nextReminderAt = Self.firstReminderSeconds
        if let url = app.startURL(for: purpose) { loadCommand = WrapperLoadCommand(url: url) }
        HapticsService.selection()
        withAnimation(.easeIn(duration: 0.2)) { reminderSection = nil }
    }

    private func keepGoing() {
        nextReminderAt = offPurposeStreak + Self.repeatReminderSeconds
        HapticsService.selection()
        withAnimation(.easeIn(duration: 0.2)) { reminderSection = nil }
    }

    private func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) seconds" }
        let minutes = seconds / 60
        return minutes == 1 ? "a minute" : "\(minutes) minutes"
    }

    // MARK: - "What was N videos ago?"

    private func handleScrollCountChange(_ newValue: Int) {
        guard started, slowDownReason != nil, !showingRecallPrompt, reminderSection == nil else { return }

        scrollsSinceLastPrompt += 1
        guard scrollsSinceLastPrompt >= nextPromptThreshold else { return }

        scrollsSinceLastPrompt = 0
        nextPromptThreshold = Int.random(in: 6...10)
        recallScrollsAgo = max(1, min(newValue, Int.random(in: 3...5)))
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

    private var recallQuestion: String {
        isCount
            ? "What was on screen \(recallScrollsAgo) \(app.shortVideoName.many.lowercased()) ago?"
            : "What was on screen \(recallScrollsAgo) scrolls ago?"
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

                Text(recallQuestion)
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
            replacedReelCount: replay.repeatsServed,
            limitKind: config.limitKind?.rawValue,
            limitAmount: config.limitKind == nil ? nil : config.amount,
            reelCount: isMessages ? 0 : liveStats.distinctVideos,
            reelsAfterSlowdown: reelsAtSlowdown.map { max(0, liveStats.distinctVideos - $0) } ?? 0,
            secondsToSlowdown: slowedAt.map { Int($0.timeIntervalSince(sessionStartedAt).rounded()) },
            slowDownCause: slowDownReason?.storedCause,
            reelSeconds: reelSeconds,
            platform: app.rawValue,
            purpose: purpose.id,
            reason: config.reason?.rawValue,
            sectionSeconds: Dictionary(uniqueKeysWithValues: sectionSeconds.map { ($0.key.rawValue, $0.value) }),
            offPurposeSeconds: offPurposeSeconds,
            driftReminders: reminderCount,
            returnedToPurpose: returnedCount,
            blockedAttempts: blockedCount,
            feeling: feeling?.rawValue,
            afterStudyMinutes: escape?.minutesAgo,
            returnedToStudy: returnedToStudy
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

/// How the web view behaves once the person's pick is used. It only ever
/// moves away from `.none` within a session.
private enum WrapperSlowdown: Equatable {
    case none
    /// Grey and quiet, and each short video opens in the iPhone's full-screen player.
    case reels
    /// Grey, quiet and laggy everywhere.
    case site
}

/// One instruction to load a page: a replayed reel, or the way back to what
/// they came for. The id makes it one-shot: the web view acts on each id once.
private struct WrapperLoadCommand: Equatable {
    let id = UUID()
    let url: URL
}

/// Keeps a purpose's lock in one place for both halves that enforce it: the
/// page script (taps and in-page navigation) and the navigation delegate (full
/// page loads, including redirects after signing in).
struct WrapperLock {
    let app: SocialApp
    let purpose: AppPurpose

    init?(app: SocialApp, purpose: AppPurpose) {
        guard purpose.allowedPaths != nil else { return nil }
        self.app = app
        self.purpose = purpose
    }

    /// Whether a full page load may go ahead. Other sites (a sign-in hop) are
    /// left to WebKit's own limits; only this app's pages are checked here.
    func allows(_ url: URL) -> Bool {
        guard app.owns(host: url.host) else { return true }
        // `URL.path` drops a trailing slash ("/shorts/" reads "/shorts");
        // the page script sees it, so this check must too.
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path
        return allows(path: path)
    }

    func allows(path: String) -> Bool {
        let lowered = path.lowercased()
        let normalized = lowered.isEmpty ? "/" : lowered
        if let allowed = purpose.allowedPaths, normalized.range(of: allowed, options: .regularExpression) != nil { return true }
        return normalized.range(of: app.accountPathPattern, options: .regularExpression) != nil
    }

    /// The same rule as a page script. Values go in as JSON so nothing in
    /// them can break out of the string.
    var script: String {
        func json(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let array = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(array.dropFirst().dropLast())
        }
        return """
        (function() {
            if (window.__mivoLock) return;
            window.__mivoLock = true;
            var DOMAIN = \(json(app.domain));
            var START = \(json(purpose.startPath));
            var ALLOWED = new RegExp(\(json(purpose.allowedPaths ?? "^$")));
            var ACCOUNT = new RegExp(\(json(app.accountPathPattern)));
            function onApp(host) { host = (host || '').toLowerCase(); return host === DOMAIN || host.endsWith('.' + DOMAIN); }
            if (!onApp(location.hostname)) return;
            function allowed(path) { path = (path || '/').toLowerCase(); return ALLOWED.test(path) || ACCOUNT.test(path); }
            function pathOf(url) {
                var u;
                try { u = new URL(url, location.href); } catch (e) { return null; }
                if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
                return onApp(u.hostname) ? u.pathname : '\\u0000';
            }
            function note() { try { window.webkit.messageHandlers.mivoBlocked.postMessage('1'); } catch (e) {} }
            function goBack() { note(); location.replace(START); }

            ['pushState', 'replaceState'].forEach(function(name) {
                var original = history[name];
                history[name] = function(state, title, url) {
                    if (url != null) {
                        var path = pathOf(url);
                        if (path !== null && !allowed(path)) { goBack(); return; }
                    }
                    return original.apply(this, arguments);
                };
            });
            window.addEventListener('popstate', function() {
                if (!allowed(location.pathname)) goBack();
            });
            document.addEventListener('click', function(e) {
                var link = e.target && e.target.closest ? e.target.closest('a[href]') : null;
                if (!link) return;
                var path = pathOf(link.getAttribute('href'));
                if (path !== null && !allowed(path)) { e.preventDefault(); e.stopPropagation(); note(); }
            }, true);
            if (!allowed(location.pathname)) location.replace(START);
        })();
        """
    }
}

/// Bare `WKWebView` — deliberately not `SFSafariViewController`, which
/// always renders a URL bar and "Done"/share chrome Apple doesn't let you
/// strip. A plain `WKWebView` has none of that by default, so "feels like
/// an app, not a browser" is mostly a matter of not adding any ourselves.
private struct WrapperStatsWebView: UIViewRepresentable {
    @Binding var liveStats: WrapperLiveStats
    let app: SocialApp
    let purpose: AppPurpose
    /// The latest page to load (a replayed reel, or back to the purpose); each is loaded once.
    var loadCommand: WrapperLoadCommand?
    /// What changes once the pick is used; applied once, on top of the page.
    var slowdown: WrapperSlowdown
    /// False under Mivo's overlays, so scrolling behind them can't keep
    /// counting (or keep moving the feed) while a choice is waiting.
    var isInteractive: Bool
    /// Instagram Reels only: report each reel's public shortcode for replay mode.
    var reportsReels: Bool
    var onReel: (String) -> Void
    /// The page address, on every page load and in-page navigation.
    var onLocation: (URL) -> Void
    /// The lock turned a navigation back.
    var onBlocked: () -> Void
    /// The page failed to load twice in a row (one automatic retry).
    var onLoadFailed: () -> Void

    /// What Safari adds to WebKit's own user agent, at this iPhone's real iOS
    /// version. A fixed, older Safari version makes sites treat the page as an
    /// old browser: YouTube's home redirects old iPhones to a page that never
    /// loads inside an app. Without the Safari part, sites treat it as an
    /// in-app browser instead.
    private static func safariApplicationName(desktop: Bool) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let safari = "Version/\(version.majorVersion).\(version.minorVersion)"
        return desktop ? "\(safari) Safari/605.1.15" : "\(safari) Mobile/15E148 Safari/604.1"
    }

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

    /// Short videos slowed down: videos lose `playsinline`, so the iPhone plays
    /// each one in its own full-screen player (and only after a tap) instead of
    /// in the scrolling page. The site re-adding the attribute is undone too.
    private static let fullScreenScript = """
    (function() {
        if (window.__mivoFullScreen) return;
        window.__mivoFullScreen = true;
        function release(video) {
            video.removeAttribute('playsinline');
            video.removeAttribute('webkit-playsinline');
            video.playsInline = false;
        }
        document.querySelectorAll('video').forEach(release);
        new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                if (m.type === 'attributes') {
                    if (m.target.tagName === 'VIDEO' && m.target.hasAttribute(m.attributeName)) release(m.target);
                    return;
                }
                m.addedNodes.forEach(function(node) {
                    if (node.tagName === 'VIDEO') release(node);
                    if (node.querySelectorAll) node.querySelectorAll('video').forEach(release);
                });
            });
        }).observe(document.documentElement, {
            childList: true, subtree: true, attributes: true, attributeFilter: ['playsinline', 'webkit-playsinline']
        });
    })();
    """

    /// The whole app slowed down: taps land late, the page's own script
    /// stalls in short bursts, and playing videos keep "buffering". The native
    /// half (touches dropped for a moment) is `Coordinator.startStutter`.
    private static let lagScript = """
    (function() {
        if (window.__mivoLag) return;
        window.__mivoLag = true;
        document.addEventListener('click', function(e) {
            if (!e.isTrusted) return;
            var target = e.target;
            e.preventDefault();
            e.stopImmediatePropagation();
            setTimeout(function() {
                target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
            }, 700 + Math.random() * 500);
        }, true);
        setInterval(function() {
            var until = Date.now() + 90 + Math.random() * 120;
            while (Date.now() < until) {}
        }, 350);
        setInterval(function() {
            document.querySelectorAll('video').forEach(function(video) {
                if (video.paused) return;
                video.pause();
                setTimeout(function() {
                    video.__mivoLagResume = true;
                    video.play().catch(function() {});
                }, 600 + Math.random() * 600);
            });
        }, 2600);
    })();
    """

    /// Dull mode, once slowed down: a separate script from the stats one, and
    /// it never reads the page — it only styles it and sets media properties.
    /// Grayscale via CSS, videos muted once when first seen (so the person can
    /// still unmute), looping switched off, including for videos added later.
    private static let dullScript = """
    (function() {
        if (window.__mivoDull) return;
        window.__mivoDull = true;
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
    ///
    /// A video counts as new when a new `<video>` plays, or when one plays
    /// something new: YouTube's Shorts player, for one, reuses a single element.
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

        // Only real taps: the lag script re-sends each tap late as a synthetic click.
        document.addEventListener('click', function(e) { if (e.isTrusted) stats.taps += 1; }, true);

        var playingSince = new WeakMap();
        function trackVideo(video) {
            if (video.__mivoTracked) return;
            video.__mivoTracked = true;
            video.addEventListener('play', function() {
                // A resume after the lag script's fake buffering isn't a new play.
                if (video.__mivoLagResume) { video.__mivoLagResume = false; } else { stats.videoPlays += 1; }
                var source = video.currentSrc || video.src || '';
                if (!video.__mivoCounted || (source && source !== video.__mivoSource)) {
                    video.__mivoCounted = true;
                    video.__mivoSource = source;
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
        Coordinator(app: app, startURL: app.startURL(for: purpose), lock: WrapperLock(app: app, purpose: purpose),
                    liveStats: $liveStats, onReel: onReel, onLocation: onLocation, onBlocked: onBlocked,
                    onLoadFailed: onLoadFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Mivo's Info.plist lists each app's domain under `WKAppBoundDomains`.
        // iOS only lets scripts run in a web view that opts in, so without
        // this the stats, lock and slow-down scripts never run at all.
        configuration.limitsNavigationsToAppBoundDomains = true
        // Like the app until the pick is used: video plays inside the page and
        // starts on its own. Without these an iPhone web view sends every
        // video to the full-screen player, which is kept for later.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let desktop = app.usesDesktopSite(for: purpose)
        configuration.defaultWebpagePreferences.preferredContentMode = desktop ? .desktop : .mobile
        configuration.applicationNameForUserAgent = Self.safariApplicationName(desktop: desktop)

        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: Self.statsScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if reportsReels {
            controller.addUserScript(WKUserScript(source: Self.reelScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let lock = context.coordinator.lock {
            controller.addUserScript(WKUserScript(source: lock.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        controller.add(context.coordinator, name: "mivoStats")
        controller.add(context.coordinator, name: "mivoReel")
        controller.add(context.coordinator, name: "mivoBlocked")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = isInteractive
        context.coordinator.allowsInteraction = isInteractive
        context.coordinator.observe(webView)
        context.coordinator.apply(slowdown, to: webView)
        if let start = app.startURL(for: purpose) {
            webView.load(URLRequest(url: start))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.allowsInteraction = isInteractive
        uiView.isUserInteractionEnabled = isInteractive && !context.coordinator.isStuttering
        context.coordinator.apply(slowdown, to: uiView)
        context.coordinator.onReel = onReel
        context.coordinator.onLocation = onLocation
        context.coordinator.onBlocked = onBlocked
        context.coordinator.onLoadFailed = onLoadFailed
        if let command = loadCommand, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            uiView.load(URLRequest(url: command.url))
        }
    }

    /// `WKUserContentController.add(_:name:)` retains the handler — without
    /// removing it here, the controller (and everything it retains) can
    /// outlive the view being torn down, and the injected script's
    /// `setInterval` keeps running against a screen nobody can see. This is
    /// the documented `UIViewRepresentable` teardown hook for exactly that.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        let controller = uiView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "mivoStats")
        controller.removeScriptMessageHandler(forName: "mivoReel")
        controller.removeScriptMessageHandler(forName: "mivoBlocked")
        coordinator.stopStutter()
        coordinator.stopObserving()
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let app: SocialApp
        let startURL: URL?
        let lock: WrapperLock?
        private let liveStats: Binding<WrapperLiveStats>
        private let decoder = JSONDecoder()
        var onReel: (String) -> Void
        var onLocation: (URL) -> Void
        var onBlocked: () -> Void
        var onLoadFailed: () -> Void
        var lastCommandID: UUID?
        /// One automatic retry per failure, reset once a page loads.
        private var retriedAfterFailure = false
        /// What the view wants (false under Mivo's overlays); the stutter
        /// restores this rather than blindly switching touches back on.
        var allowsInteraction = true
        private(set) var isStuttering = false
        private var appliedSlowdown: WrapperSlowdown = .none
        private var stutterTimer: Timer?
        private var urlObservation: NSKeyValueObservation?

        /// Totals from page loads that already finished, and the latest
        /// snapshot from the current one. A full page load restarts the
        /// injected script's counters, so they are added up here instead.
        private var carried = WrapperLiveStats()
        private var latest = WrapperLiveStats()

        init(
            app: SocialApp,
            startURL: URL?,
            lock: WrapperLock?,
            liveStats: Binding<WrapperLiveStats>,
            onReel: @escaping (String) -> Void,
            onLocation: @escaping (URL) -> Void,
            onBlocked: @escaping () -> Void,
            onLoadFailed: @escaping () -> Void
        ) {
            self.app = app
            self.startURL = startURL
            self.lock = lock
            self.onLoadFailed = onLoadFailed
            self.liveStats = liveStats
            self.onReel = onReel
            self.onLocation = onLocation
            self.onBlocked = onBlocked
        }

        /// The address changes on every page load and on every in-page move
        /// (these sites are single-page apps), so this is where Mivo learns
        /// which part of the app, and which video, is on screen.
        func observe(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                guard let self, let url = webView.url else { return }
                DispatchQueue.main.async { self.onLocation(url) }
            }
        }

        func stopObserving() {
            urlObservation?.invalidate()
            urlObservation = nil
        }

        /// Turns the slowdown on once: added as document-start scripts so later
        /// page loads get it too, and run now on the page already open.
        func apply(_ slowdown: WrapperSlowdown, to webView: WKWebView) {
            guard slowdown != .none, appliedSlowdown == .none else { return }
            appliedSlowdown = slowdown
            let scripts = [
                WrapperStatsWebView.dullScript,
                slowdown == .reels ? WrapperStatsWebView.fullScreenScript : WrapperStatsWebView.lagScript
            ]
            for source in scripts {
                webView.configuration.userContentController.addUserScript(WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                ))
                webView.evaluateJavaScript(source)
            }
            if slowdown == .site { startStutter(webView) }
        }

        /// Native half of the lag: every second or two the page stops taking
        /// touches for a moment, which drops a swipe halfway through.
        private func startStutter(_ webView: WKWebView) {
            webView.scrollView.decelerationRate = .fast
            scheduleStutter(webView)
        }

        private func scheduleStutter(_ webView: WKWebView) {
            // `.common` modes, so it also fires while a finger is mid-scroll.
            let timer = Timer(timeInterval: .random(in: 1.0...2.2), repeats: false) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.isStuttering = true
                webView.isUserInteractionEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0.35...0.8)) { [weak self, weak webView] in
                    guard let self, let webView, self.stutterTimer != nil else { return }
                    self.isStuttering = false
                    webView.isUserInteractionEnabled = self.allowsInteraction
                    self.scheduleStutter(webView)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            stutterTimer = timer
        }

        func stopStutter() {
            stutterTimer?.invalidate()
            stutterTimer = nil
            isStuttering = false
        }

        /// Full page loads the page script can't catch (a redirect after
        /// signing in, a typed-in link) still can't leave a locked purpose.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame?.isMainFrame == true {
                wrapperLog.debug("\(self.app.rawValue, privacy: .public) navigating to \(navigationAction.request.url?.absoluteString ?? "", privacy: .public)")
            }
            guard let lock, navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url, !lock.allows(url) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            onBlocked()
            if let start = app.startURL(for: lock.purpose), webView.url?.path != start.path {
                webView.load(URLRequest(url: start))
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            carried = carried.adding(latest)
            latest = WrapperLiveStats()
        }

        /// A page that never started loading leaves a blank screen, so a
        /// network failure (a dropped connection, say) is retried once, then
        /// handed to the view's "Try again". Cancelled loads are Mivo's own
        /// doing (the lock, a newer load) and need nothing.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            wrapperLog.error("\(self.app.rawValue, privacy: .public) page failed to start: \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String ?? "", privacy: .public)")
            guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else { return }
            let failing = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? startURL
            if !retriedAfterFailure, let failing {
                retriedAfterFailure = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak webView] in
                    webView?.load(URLRequest(url: failing))
                }
                return
            }
            retriedAfterFailure = false
            DispatchQueue.main.async { [weak self] in self?.onLoadFailed() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            wrapperLog.error("\(self.app.rawValue, privacy: .public) page failed: \(nsError.domain, privacy: .public) \(nsError.code)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retriedAfterFailure = false
            wrapperLog.debug("\(self.app.rawValue, privacy: .public) loaded \(webView.url?.absoluteString ?? "", privacy: .public)")
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
            case "mivoBlocked":
                DispatchQueue.main.async { [weak self] in
                    self?.onBlocked()
                }
            default:
                break
            }
        }
    }
}

/// Milo's lines on the wrapper's break screens. Fixed on purpose: the limits
/// are rules, not a conversation, so there is nothing here to talk round.
enum MiloBreakVoice {
    static let reelsSeen = "That was a good stretch. Take it or leave it, either is fine."
    static let minutesUsed = "That was your time. It only gets slower from here."
    static let timeUsed = "You spent it all. Go do something that gets you more."
    static let outsideWindow = "Your next window opens later. This one stays slow until then."
}
