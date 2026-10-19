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
/// looked at — this measures behavior, not content.
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

    @State private var liveStats = WrapperLiveStats()
    @State private var secondsRemaining: Int
    private let sessionStartedAt = Date()
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
            WrapperStatsWebView(liveStats: $liveStats, isInteractive: !showingRecallPrompt)
                .ignoresSafeArea()

            markAndCloseRow

            VStack {
                Spacer()
                if showingLastReelWarning {
                    lastReelBanner
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if showingRecallPrompt {
                recallPromptOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden(false)
        .onReceive(timer) { _ in tick() }
        .onChange(of: liveStats.scrollBursts) { _, newValue in handleScrollCountChange(newValue) }
        .onDisappear { recordSession() }
    }

    private var markAndCloseRow: some View {
        HStack(spacing: 8) {
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

    // MARK: - Session timer

    private func tick() {
        guard !didFinish, secondsRemaining > 0 else { return }
        secondsRemaining -= 1

        if secondsRemaining == lastReelWarningSeconds {
            HapticsService.impact(style: .medium)
            withAnimation(.easeOut(duration: 0.3)) {
                showingLastReelWarning = true
            }
        }

        if secondsRemaining <= 0 {
            didFinish = true
            HapticsService.impact(style: .heavy)
            dismiss()
        }
    }

    // MARK: - "What was N reels ago?"

    private func handleScrollCountChange(_ newValue: Int) {
        guard !showingRecallPrompt, !didFinish else { return }
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
            firstScrollDelaySeconds: liveStats.firstScrollDelayMs < 0 ? 0 : Int((liveStats.firstScrollDelayMs / 1000).rounded())
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
    var videoSeconds: Double = 0
    var sectionChanges: Int = 0
    var firstScrollDelayMs: Double = -1
    var longestPauseMs: Double = 0
}

/// Bare `WKWebView` — deliberately not `SFSafariViewController`, which
/// always renders a URL bar and "Done"/share chrome Apple doesn't let you
/// strip. A plain `WKWebView` has none of that by default, so "feels like
/// an app, not a browser" is mostly a matter of not adding any ourselves.
private struct WrapperStatsWebView: UIViewRepresentable {
    @Binding var liveStats: WrapperLiveStats
    /// False while the recall prompt overlay is up, so scrolling behind it
    /// can't keep incrementing stats (or keep advancing reels) while the
    /// person is meant to be answering, not scrolling.
    var isInteractive: Bool

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
        Coordinator(liveStats: $liveStats)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userScript = WKUserScript(
            source: Self.statsScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)
        configuration.userContentController.add(context.coordinator, name: "mivoStats")

        let webView = WKWebView(frame: .zero, configuration: configuration)
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
    }

    /// `WKUserContentController.add(_:name:)` retains the handler — without
    /// removing it here, the controller (and everything it retains) can
    /// outlive the view being torn down, and the injected script's
    /// `setInterval` keeps running against a screen nobody can see. This is
    /// the documented `UIViewRepresentable` teardown hook for exactly that.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mivoStats")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let liveStats: Binding<WrapperLiveStats>
        private let decoder = JSONDecoder()

        init(liveStats: Binding<WrapperLiveStats>) {
            self.liveStats = liveStats
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mivoStats",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let decoded = try? decoder.decode(WrapperLiveStats.self, from: data) else { return }
            DispatchQueue.main.async { [liveStats] in
                liveStats.wrappedValue = decoded
            }
        }
    }
}
