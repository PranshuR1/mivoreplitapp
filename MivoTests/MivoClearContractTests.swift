import Foundation

@main
enum MivoClearContractTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for configuration in MivoClearDefaults.configurations {
            try testFixture(configuration, root: root)
            try testExternalDomain(configuration)
            try testInsecureRoute(configuration)
            try testConfiguredUtilities(configuration)
            try testFirstPartyAuthentication(configuration)
            try testTikTokFeedRoutes(configuration)
            try testTikTokMessaging(configuration)
            try testTikTokCreateIsAvailable(configuration)
            try testTikTokSingleVideo(configuration)
            try testInstagramSingleReel(configuration)
            try testInstagramAccountAccess(configuration)
            try testInstagramMessaging(configuration)
            try testYouTubeShortsRoutes(configuration)
        }
        print("Mivo Clear contract tests passed")
    }

    private static func testFixture(_ configuration: MivoClearPlatformConfiguration, root: URL) throws {
        let file = root.appendingPathComponent("MivoTests/Fixtures/\(configuration.platform.rawValue)-focused.html")
        let html = try String(contentsOf: file, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"href=\"([^\"]+)\""#)
        let range = NSRange(html.startIndex..., in: html)
        let paths = expression.matches(in: html, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[valueRange])
        }
        precondition(!paths.isEmpty, "Fixture must contain routes")
        var blocked = 0
        var allowed = 0
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        for path in paths {
            let url = URL(string: path, relativeTo: URL(string: configuration.homeURL)!)!.absoluteURL
            switch policy.decision(for: url) {
            case .allow: allowed += 1
            case .redirect: blocked += 1
            default: preconditionFailure("First-party fixture route escaped its allowlist")
            }
        }
        precondition(allowed > 0, "Each platform must retain a useful route")
        precondition(blocked > 0, "Each platform fixture must exercise a blocked route")
    }

    private static func testExternalDomain(_ configuration: MivoClearPlatformConfiguration) throws {
        let decision = MivoClearNavigationPolicy(configuration: configuration)
            .decision(for: URL(string: "https://example.com/endless")!)
        if case .external = decision { return }
        preconditionFailure("Unknown hosts must leave Mivo Clear")
    }

    private static func testInsecureRoute(_ configuration: MivoClearPlatformConfiguration) throws {
        let host = URL(string: configuration.homeURL)!.host!
        let decision = MivoClearNavigationPolicy(configuration: configuration)
            .decision(for: URL(string: "http://\(host)/")!)
        if case .external = decision { return }
        preconditionFailure("Non-HTTPS routes must never load inside Mivo Clear")
    }

    private static func testConfiguredUtilities(_ configuration: MivoClearPlatformConfiguration) throws {
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        for action in configuration.quickActions {
            guard let url = configuration.url(for: action.id) else {
                preconditionFailure("Every utility shortcut needs a valid URL")
            }
            if case .allow = policy.decision(for: url) { continue }
            preconditionFailure("Configured utility shortcut must remain usable: \(action.id)")
        }
    }

    private static func testFirstPartyAuthentication(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .tiktok else { return }
        let login = URL(string: "https://www.tiktok.com/login/phone-or-email/email?redirect_url=https%3A%2F%2Fwww.tiktok.com%2Fprofile")!
        let decision = MivoClearNavigationPolicy(configuration: configuration).decision(for: login)
        if case .allow = decision { return }
        preconditionFailure("TikTok's first-party email login must remain usable")
    }

    private static func testTikTokFeedRoutes(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .tiktok else { return }
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        let blockedURLs = [
            URL(string: "https://www.tiktok.com/")!,
            URL(string: "https://www.tiktok.com/?lang=en")!,
            URL(string: "https://www.tiktok.com/foryou")!,
            URL(string: "https://www.tiktok.com/following")!,
            URL(string: "https://www.tiktok.com/friends")!,
            URL(string: "https://www.tiktok.com/friends/recommended")!,
            URL(string: "https://www.tiktok.com/discover")!,
            URL(string: "https://www.tiktok.com/discover/trending")!
        ]
        for url in blockedURLs {
            if case .redirect = policy.decision(for: url) { continue }
            preconditionFailure("TikTok feed route must redirect to Inbox: \(url.absoluteString)")
        }
    }

    private static func testTikTokMessaging(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .tiktok else { return }
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        let messageURLs = [
            URL(string: "https://www.tiktok.com/messages")!,
            URL(string: "https://www.tiktok.com/messages?lang=en")!,
            URL(string: "https://www.tiktok.com/messages/739001234567890")!,
            URL(string: "https://www.tiktok.com/inbox")!
        ]
        for url in messageURLs {
            if case .allow = policy.decision(for: url) { continue }
            preconditionFailure("TikTok messaging and Inbox must remain usable: \(url.absoluteString)")
        }
    }

    private static func testTikTokCreateIsAvailable(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .tiktok else { return }
        precondition(
            configuration.quickActions.contains { $0.id == "create" && $0.path == "/upload" },
            "TikTok Clear must expose a working create action"
        )
        precondition(
            configuration.hiddenSelectors.allSatisfy {
                let selector = $0.lowercased()
                return !(selector.contains("href") && selector.contains("upload"))
            },
            "TikTok's upload link must remain available through Mivo's Create action"
        )
        precondition(
            configuration.hiddenSelectors.contains { $0.lowercased().contains("sidenav") },
            "TikTok's native desktop sidebar must stay hidden behind Mivo's bottom navigation"
        )
        if case .allow = MivoClearNavigationPolicy(configuration: configuration)
            .decision(for: URL(string: "https://www.tiktok.com/upload")!) {
            return
        }
        preconditionFailure("TikTok's upload route must remain available")
    }

    private static func testTikTokSingleVideo(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .tiktok else { return }
        let selected = URL(string: "https://www.tiktok.com/@mivo/video/739001234567890")!
        let next = URL(string: "https://www.tiktok.com/@mivo/video/739009876543210")!
        guard let selectedPath = MivoClearSingleMediaPolicy.tiktokVideoPath(
            for: selected,
            configuration: configuration
        ) else {
            preconditionFailure("A chosen TikTok profile video must enter single-media mode")
        }
        precondition(
            MivoClearSingleMediaPolicy.matchesTikTokVideo(
                selected,
                path: selectedPath,
                configuration: configuration
            ),
            "The selected TikTok must remain playable"
        )
        precondition(
            !MivoClearSingleMediaPolicy.matchesTikTokVideo(
                next,
                path: selectedPath,
                configuration: configuration
            ),
            "A second TikTok must not inherit single-media access"
        )
        if case .redirect = MivoClearNavigationPolicy(configuration: configuration).decision(for: selected) {
            return
        }
        preconditionFailure("TikTok videos must remain blocked outside single-media mode")
    }

    private static func testInstagramSingleReel(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .instagram else { return }
        let selected = URL(string: "https://www.instagram.com/reel/ABC123/")!
        let next = URL(string: "https://www.instagram.com/reel/XYZ789/")!
        let shared = URL(string: "https://www.instagram.com/share/reel/SHARED123/")!
        guard let selectedPath = MivoClearSingleMediaPolicy.instagramReelPath(
            for: selected,
            configuration: configuration
        ) else {
            preconditionFailure("A selected Instagram reel must enter single-media mode")
        }
        precondition(
            MivoClearSingleMediaPolicy.matchesInstagramReel(
                selected,
                path: selectedPath,
                configuration: configuration
            ),
            "The selected reel must remain playable"
        )
        precondition(
            !MivoClearSingleMediaPolicy.matchesInstagramReel(
                next,
                path: selectedPath,
                configuration: configuration
            ),
            "A different reel must not inherit single-media access"
        )
        precondition(
            MivoClearSingleMediaPolicy.instagramReelPath(
                for: shared,
                configuration: configuration
            ) == "/reel/shared123",
            "A reel shared through Instagram Messages must resolve to one isolated reel"
        )
        if case .redirect = MivoClearNavigationPolicy(configuration: configuration).decision(for: selected) {
            return
        }
        preconditionFailure("Instagram reels must remain blocked outside single-media mode")
    }

    private static func testInstagramAccountAccess(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .instagram else { return }
        let actionIDs = Set(configuration.quickActions.map(\.id))
        precondition(actionIDs.contains("profile"), "Instagram Clear must expose the user's profile")
        precondition(actionIDs.contains("settings"), "Instagram Clear must expose account settings")

        let policy = MivoClearNavigationPolicy(configuration: configuration)
        let allowedURLs = [
            URL(string: "https://www.instagram.com/mivo/")!,
            URL(string: "https://www.instagram.com/accounts/edit/")!,
            URL(string: "https://www.instagram.com/accounts/privacy_and_security/")!,
            URL(string: "https://accountscenter.instagram.com/")!
        ]
        for url in allowedURLs {
            if case .allow = policy.decision(for: url) { continue }
            preconditionFailure("Instagram account route must remain available: \(url.absoluteString)")
        }
    }

    private static func testInstagramMessaging(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .instagram else { return }
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        let messageURLs = [
            URL(string: "https://www.instagram.com/direct/inbox/")!,
            URL(string: "https://www.instagram.com/direct/t/123456789/")!,
            URL(string: "https://www.instagram.com/accounts/login/?next=%2Fdirect%2Finbox%2F")!
        ]
        for url in messageURLs {
            if case .allow = policy.decision(for: url) { continue }
            preconditionFailure("Instagram messaging must remain usable: \(url.absoluteString)")
        }
        precondition(
            configuration.hiddenSelectors.allSatisfy {
                !($0.lowercased().contains(":has(") && $0.lowercased().contains("/reel"))
            },
            "A shared Reel must not hide its entire Instagram conversation"
        )
    }

    private static func testYouTubeShortsRoutes(_ configuration: MivoClearPlatformConfiguration) throws {
        guard configuration.platform == .youtube else { return }
        let policy = MivoClearNavigationPolicy(configuration: configuration)
        let blockedURLs = [
            URL(string: "https://www.youtube.com/shorts/abc123")!,
            URL(string: "https://www.youtube.com/@mivo/shorts")!,
            URL(string: "https://www.youtube.com/channel/UC123/shorts")!,
            URL(string: "https://www.youtube.com/c/Mivo/shorts")!
        ]
        for url in blockedURLs {
            if case .redirect = policy.decision(for: url) { continue }
            preconditionFailure("Every YouTube Shorts route must redirect: \(url.absoluteString)")
        }

        let allowedURLs = [
            URL(string: "https://www.youtube.com/@mivo")!,
            URL(string: "https://www.youtube.com/channel/UC123/videos")!,
            URL(string: "https://www.youtube.com/feed/playlists")!
        ]
        for url in allowedURLs {
            if case .allow = policy.decision(for: url) { continue }
            preconditionFailure("Long-form YouTube profile routes must remain available: \(url.absoluteString)")
        }
    }
}
