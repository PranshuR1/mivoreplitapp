import WebKit
import XCTest
@testable import Mivo

/// Exercises `MivoClearRuntimeGuard.script(configuration:singleMediaURL:)` end to
/// end: the real injected JavaScript, in a real `WKWebView`, against DOM fixtures.
///
/// The guard is a large JavaScript string built inside Swift, so nothing else in
/// the project can catch a regression in it — the compiler only sees a `String`,
/// and `MivoClearContractTests` only covers URL policy on `MivoClearDefaults`.
/// The case that matters most is `testSuggestedReelUnderSharedReelEscapes`: a
/// viewer being able to scroll forever past a reel shared in a DM has been
/// reported twice.
@MainActor
final class MivoClearRuntimeGuardTests: XCTestCase {
    /// How long the guard is given to reach a decision. It re-checks Instagram
    /// routes every 450ms and debounces each check by 180ms, so this allows
    /// several full cycles.
    private let decisionTimeout: TimeInterval = 5

    /// How long a "nothing happens" case is observed before it is believed.
    private let quietTimeout: TimeInterval = 3

    private var harness: GuardHarness?

    override func tearDown() {
        harness?.tearDown()
        harness = nil
        super.tearDown()
    }

    private var instagram: MivoClearPlatformConfiguration {
        get throws {
            try XCTUnwrap(
                MivoClearDefaults.configurations.first { $0.platform == .instagram },
                "Instagram must ship a bundled Mivo Clear configuration"
            )
        }
    }

    private var tiktok: MivoClearPlatformConfiguration {
        get throws {
            try XCTUnwrap(
                MivoClearDefaults.configurations.first { $0.platform == .tiktok },
                "TikTok must ship a bundled Mivo Clear configuration"
            )
        }
    }

    private func makeHarness(
        _ configuration: MivoClearPlatformConfiguration,
        singleMediaURL: URL? = nil
    ) throws -> GuardHarness {
        let harness = try GuardHarness(configuration: configuration, singleMediaURL: singleMediaURL)
        self.harness = harness
        return harness
    }

    private static let conversationURL = URL(string: "https://www.instagram.com/direct/t/1234/")!
    private static let inboxURL = URL(string: "https://www.instagram.com/direct/inbox/")!

    // MARK: - Instagram: a reel shared in a DM

    /// The reel the conversation actually linked to is still on screen. Returning
    /// the viewer to the inbox here would break the feature outright.
    func testSharedReelStillPlayingDoesNotEscape() throws {
        let harness = try makeHarness(instagram)
        let noEscape = harness.expectNoEscape()
        // The viewer still has to be *recognised*, otherwise "no escape" would
        // pass for the trivial reason that the guard never engaged.
        let recognised = harness.expectSingleMediaActive()

        harness.load(GuardFixtures.instagramSharedReelPlaying, baseURL: Self.conversationURL)

        wait(for: [recognised], timeout: decisionTimeout)
        wait(for: [noEscape], timeout: quietTimeout)
    }

    /// The reported bug. Instagram keeps the shared reel mounted and appends
    /// "Suggested" reels underneath, so a viewer can scroll indefinitely. A
    /// suggested heading next to a large video on a /direct route means the
    /// viewer is past the one reel the conversation linked to.
    func testSuggestedReelUnderSharedReelEscapes() throws {
        let harness = try makeHarness(instagram)
        let escape = harness.expectEscape(reason: "suggested")

        harness.load(GuardFixtures.instagramSuggestedReel, baseURL: Self.conversationURL)

        wait(for: [escape], timeout: decisionTimeout)
        XCTAssertEqual(harness.escapeReasons.first, "suggested")
        // The escape carries the conversation it started from, so the viewer is
        // returned to that thread rather than a generic inbox.
        XCTAssertEqual(harness.firstEscapeOrigin, Self.conversationURL.absoluteString)
    }

    /// The third report of this bug, 2026-08-04. The viewer is on a suggested
    /// reel with no reachable "Suggested" text — so label matching, however
    /// permissive, cannot save it. The escape has to come from the swap of the
    /// conversation's "Reply to …" box for a "Send to group" pill.
    func testSuggestedReelWithoutLabelEscapesViaSendControl() throws {
        let harness = try makeHarness(instagram)
        let escape = harness.expectEscape(reason: "suggested")

        harness.load(GuardFixtures.instagramSuggestedReelNoLabel, baseURL: Self.conversationURL)

        wait(for: [escape], timeout: decisionTimeout)
    }

    /// The fourth report of this bug, 2026-08-04. A reel opened from a friend
    /// does not have to land under `/direct` — a bare permalink
    /// (`/reel/<id>/`) reached the same locked single-media state, but until
    /// now both the "Suggested" label and the send-control signal only ran
    /// inside a function gated on `location.pathname.startsWith('/direct')`.
    /// This loads the fixture at the reel's own permalink instead of a
    /// conversation URL, which is exactly the gap: `instagramActive` (used by
    /// `detectSingleMediaEscape`, the unconditional path) is true here, but
    /// the send-control signal used to be unreachable outside `/direct`.
    func testSuggestedReelOutsideDirectRouteEscapes() throws {
        let shared = URL(string: "https://www.instagram.com/reel/abc123xyz/")!
        let harness = try makeHarness(instagram, singleMediaURL: shared)
        let escape = harness.expectEscape(reason: "suggested")

        harness.load(GuardFixtures.instagramSuggestedReelNoLabel, baseURL: shared)

        wait(for: [escape], timeout: decisionTimeout)
    }

    /// The counterpart to the permalink-route test: the shared reel itself,
    /// still playing, viewed at its own permalink rather than a /direct
    /// route, must not escape just because the route check was removed.
    func testSharedReelAtOwnPermalinkDoesNotEscape() throws {
        let shared = URL(string: "https://www.instagram.com/reel/abc123xyz/")!
        let harness = try makeHarness(instagram, singleMediaURL: shared)
        let noEscape = harness.expectNoEscape()

        harness.load(GuardFixtures.instagramSharedReelCompact, baseURL: shared)

        wait(for: [noEscape], timeout: quietTimeout)
        XCTAssertEqual(harness.escapeReasons, [])
    }

    /// The counterpart that keeps the send-to signal honest: the shared reel in
    /// the same compact layout still has its reply box, so nothing escapes.
    func testSharedReelCompactDoesNotEscape() throws {
        let harness = try makeHarness(instagram)
        let noEscape = harness.expectNoEscape()

        harness.load(GuardFixtures.instagramSharedReelCompact, baseURL: Self.conversationURL)

        wait(for: [noEscape], timeout: quietTimeout)
        XCTAssertEqual(harness.escapeReasons, [])
    }

    /// The running guard announces its build. A stale install is otherwise
    /// indistinguishable from a broken heuristic in a bug report.
    func testGuardAnnouncesItsVersion() throws {
        let harness = try makeHarness(instagram)
        let ready = harness.expectMessage(description: "guard announced its version") { payload in
            payload["guardReady"] as? Bool == true
                && payload["guardVersion"] as? Int == MivoClearRuntimeGuard.version
        }

        harness.load(GuardFixtures.instagramSharedReelCompact, baseURL: Self.conversationURL)

        wait(for: [ready], timeout: decisionTimeout)
    }

    /// The label matching must not have traded one tag for another: a `span`
    /// label, which the original selector handled, still has to escape.
    func testSuggestedReelWithSpanLabelEscapes() throws {
        let harness = try makeHarness(instagram)
        let escape = harness.expectEscape(reason: "suggested")

        harness.load(GuardFixtures.instagramSuggestedReelSpanLabel, baseURL: Self.conversationURL)

        wait(for: [escape], timeout: decisionTimeout)
    }

    /// The false-positive path. The DM inbox has a "Suggested" people section of
    /// its own; with no video on screen it must not read as a suggested reel.
    func testInboxSuggestedPeopleDoesNotEscape() throws {
        let harness = try makeHarness(instagram)
        let noEscape = harness.expectNoEscape()

        harness.load(GuardFixtures.instagramInboxSuggestedPeople, baseURL: Self.inboxURL)

        wait(for: [noEscape], timeout: quietTimeout)
        XCTAssertEqual(harness.escapeReasons, [])
    }

    // MARK: - TikTok: swiping to the next video

    /// TikTok advances by rewriting the URL rather than navigating, so the guard
    /// patches `history.pushState`. A push to a different /video/ path than the
    /// one that was shared is the viewer swiping onward.
    func testTikTokNextVideoEscapes() throws {
        let shared = URL(string: "https://www.tiktok.com/@mivo/video/111")!
        let harness = try makeHarness(tiktok, singleMediaURL: shared)
        let loaded = harness.expectLoad()
        let escape = harness.expectEscape(reason: "nextVideo")

        harness.load(GuardFixtures.tiktokSingleVideo, baseURL: shared)
        wait(for: [loaded], timeout: decisionTimeout)

        harness.evaluate("history.pushState({}, '', '/@mivo/video/222')")

        wait(for: [escape], timeout: decisionTimeout)
    }

    /// The shared video itself is exempt from the blocked-path rules that
    /// otherwise cover every /video/ route, so it must not escape on arrival.
    func testTikTokSharedVideoDoesNotEscapeOnArrival() throws {
        let shared = URL(string: "https://www.tiktok.com/@mivo/video/111")!
        let harness = try makeHarness(tiktok, singleMediaURL: shared)
        let noEscape = harness.expectNoEscape()

        harness.load(GuardFixtures.tiktokSingleVideo, baseURL: shared)

        wait(for: [noEscape], timeout: quietTimeout)
        XCTAssertEqual(harness.attemptedNavigations, [], "The shared video must not be redirected away")
    }

    // MARK: - Blocked routes

    /// A blocked route redirects to the configured home rather than rendering.
    /// The harness cancels the navigation, so this asserts on the attempt.
    func testBlockedInstagramRouteRedirectsHome() throws {
        let configuration = try instagram
        let harness = try makeHarness(configuration)
        let home = try XCTUnwrap(URL(string: configuration.homeURL))
        let redirect = harness.expectNavigation(to: home)

        harness.load(GuardFixtures.genericFeed, baseURL: URL(string: "https://www.instagram.com/explore/")!)

        wait(for: [redirect], timeout: decisionTimeout)
    }

    /// The same rule for TikTok, which has a different home and a different set of
    /// blocked prefixes.
    func testBlockedTikTokRouteRedirectsHome() throws {
        let configuration = try tiktok
        let harness = try makeHarness(configuration)
        let home = try XCTUnwrap(URL(string: configuration.homeURL))
        let redirect = harness.expectNavigation(to: home)

        harness.load(GuardFixtures.genericFeed, baseURL: URL(string: "https://www.tiktok.com/foryou")!)

        wait(for: [redirect], timeout: decisionTimeout)
    }
}
