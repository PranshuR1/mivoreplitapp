import WebKit
import XCTest
@testable import Mivo

/// Runs the real injected guard — the JavaScript built by
/// `MivoClearRuntimeGuard.script(configuration:singleMediaURL:)` — against an HTML
/// fixture in a live `WKWebView`, and turns the messages it posts back on the
/// `mivoClearSingleMedia` handler into `XCTestExpectation`s.
///
/// The guard measures elements against `innerWidth`/`innerHeight` and reacts to
/// mutations on a timer, so the web view is given a phone-sized frame and put in
/// a visible window: an unsized or detached web view reports zero-area rects and
/// every size heuristic in the guard silently disarms.
@MainActor
final class GuardHarness: NSObject {
    /// Wide enough that a `100vw` video clears the `innerWidth * 0.62` bar and
    /// tall enough that an `80vh` video clears `innerHeight * 0.40`.
    static let viewportSize = CGSize(width: 390, height: 844)

    private let window: UIWindow
    private let webView: WKWebView
    private var baseURL: URL?

    private struct Matcher {
        let matches: ([String: Any]) -> Bool
        let expectation: XCTestExpectation
    }

    private var messageMatchers: [Matcher] = []
    private var navigationMatchers: [(url: URL, expectation: XCTestExpectation)] = []
    private var loadExpectation: XCTestExpectation?

    /// Every payload received on `mivoClearSingleMedia`, in arrival order.
    private(set) var messages: [[String: Any]] = []

    /// Every URL the page tried to navigate to after the fixture loaded. These are
    /// cancelled rather than followed so no test ever touches the network.
    private(set) var attemptedNavigations: [URL] = []

    init(configuration: MivoClearPlatformConfiguration, singleMediaURL: URL? = nil) throws {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController.addUserScript(
            try MivoClearRuntimeGuard.script(configuration: configuration, singleMediaURL: singleMediaURL)
        )

        let frame = CGRect(origin: .zero, size: Self.viewportSize)
        window = UIWindow(frame: frame)
        webView = WKWebView(frame: frame, configuration: webConfiguration)
        super.init()

        // The app registers this exact handler name in MivoClearViews; the guard
        // posts to it by name, so a rename on either side has to fail here.
        webConfiguration.userContentController.add(self, name: "mivoClearSingleMedia")
        webView.navigationDelegate = self

        window.addSubview(webView)
        window.isHidden = false
        window.makeKeyAndVisible()
    }

    func tearDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mivoClearSingleMedia")
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        window.isHidden = true
    }

    // MARK: - Driving the page

    func load(_ html: String, baseURL: URL) {
        self.baseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Fulfilled when the fixture has finished loading, so a test can drive the
    /// page afterwards without guessing at a delay.
    func expectLoad() -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "fixture finished loading")
        loadExpectation = expectation
        return expectation
    }

    func evaluate(_ javaScript: String) {
        webView.evaluateJavaScript(javaScript)
    }

    // MARK: - Expectations

    /// An escape message carrying `reason`.
    func expectEscape(reason: String) -> XCTestExpectation {
        expectMessage(description: "escapedSingleMedia(\(reason))") { payload in
            payload["escapedSingleMedia"] as? Bool == true && payload["reason"] as? String == reason
        }
    }

    /// An inverted expectation: the test fails if the guard decides the viewer
    /// escaped. This is the false-positive guard — the reason a suggested-people
    /// heading in the DM inbox must not yank the viewer home.
    func expectNoEscape() -> XCTestExpectation {
        let expectation = expectMessage(description: "no escapedSingleMedia") { payload in
            payload["escapedSingleMedia"] as? Bool == true
        }
        expectation.isInverted = true
        return expectation
    }

    /// The guard recognising an inline single-media viewer. Instagram and TikTok
    /// report this differently — `instagramDirectViewer` vs `active` — and the app
    /// reads both, so either counts here.
    func expectSingleMediaActive() -> XCTestExpectation {
        expectMessage(description: "single media viewer recognised") { payload in
            payload["active"] as? Bool == true || payload["instagramDirectViewer"] as? Bool == true
        }
    }

    /// A navigation attempt to `url`, which the harness cancels.
    func expectNavigation(to url: URL) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "navigation to \(url.absoluteString)")
        navigationMatchers.append((url: url, expectation: expectation))
        return expectation
    }

    func expectMessage(
        description: String,
        matching: @escaping ([String: Any]) -> Bool
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        // Late duplicates are expected: the guard re-checks the route on a timer,
        // and an inverted expectation must still fail on the *first* match.
        expectation.assertForOverFulfill = false
        messageMatchers.append(Matcher(matches: matching, expectation: expectation))
        return expectation
    }

    /// The `reason` values of every escape message received so far.
    var escapeReasons: [String] {
        messages
            .filter { $0["escapedSingleMedia"] as? Bool == true }
            .map { $0["reason"] as? String ?? "" }
    }

    /// The `origin` of the first escape message, which is the route the viewer is
    /// sent back to.
    var firstEscapeOrigin: String? {
        messages
            .first { $0["escapedSingleMedia"] as? Bool == true }
            .map { $0["origin"] as? String ?? "" }
    }
}

extension GuardHarness: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard let payload = message.body as? [String: Any] else { return }
            guard message.name == "mivoClearSingleMedia" else { return }
            messages.append(payload)
            for matcher in messageMatchers where matcher.matches(payload) {
                matcher.expectation.fulfill()
            }
        }
    }
}

extension GuardHarness: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        MainActor.assumeIsolated {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // The fixture itself has to load; anything the page navigates to
            // afterwards is recorded and cancelled so the test stays offline.
            guard url != baseURL else {
                decisionHandler(.allow)
                return
            }
            attemptedNavigations.append(url)
            for matcher in navigationMatchers where matcher.url == url {
                matcher.expectation.fulfill()
            }
            decisionHandler(.cancel)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loadExpectation?.fulfill()
        }
    }
}
