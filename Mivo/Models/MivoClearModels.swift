import Foundation

enum MivoClearPlatform: String, Codable, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case snapchat

    /// Platforms currently available in Mivo Clear. Snapchat remains a
    /// decodable legacy value so existing on-device records stay readable.
    static let supportedCases: [MivoClearPlatform] = [.instagram, .tiktok, .youtube]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .snapchat: return "Snapchat"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .youtube: return "play.rectangle.fill"
        case .snapchat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

enum MivoClearEntryPoint: String, Codable {
    case home
    case settings
    case shield
    case deepLink = "deep_link"
}

enum MivoClearMappingError: LocalizedError {
    case selectOneApp
    case alreadyMapped(MivoClearPlatform)

    var errorDescription: String? {
        switch self {
        case .selectOneApp:
            return "Choose exactly one app, without a category or website."
        case .alreadyMapped(let platform):
            return "That app is already mapped to \(platform.title)."
        }
    }
}

enum MivoClearNavigationDecision: Equatable {
    case allow
    case redirect(URL)
    case external(URL)
    case cancel
}

struct MivoClearNavigationPolicy {
    let configuration: MivoClearPlatformConfiguration

    func decision(for url: URL, allowBlockedQuickAction: Bool = false) -> MivoClearNavigationDecision {
        guard url.scheme == "https" else { return .external(url) }
        guard configuration.allows(host: url.host) else { return .external(url) }
        if configuration.platform == .instagram,
           url.host?.lowercased().hasPrefix("accountscenter.") == true {
            return .allow
        }
        let isConfiguredUtility = configuration.allowsQuickAction(path: url.path)
        if !allowBlockedQuickAction && !isConfiguredUtility && configuration.blocks(path: url.path),
           let fallback = configuration.url(for: nil) {
            return .redirect(fallback)
        }
        return .allow
    }
}

enum MivoClearSingleMediaPolicy {
    static func singleMediaPath(for url: URL, configuration: MivoClearPlatformConfiguration) -> String? {
        switch configuration.platform {
        case .instagram:
            return instagramReelPath(for: url, configuration: configuration)
        case .tiktok:
            return tiktokVideoPath(for: url, configuration: configuration)
        case .youtube, .snapchat:
            return nil
        }
    }

    static func instagramReelPath(for url: URL, configuration: MivoClearPlatformConfiguration) -> String? {
        guard configuration.platform == .instagram,
              url.scheme?.lowercased() == "https",
              configuration.allows(host: url.host) else { return nil }
        guard let identifier = instagramReelIdentifier(in: url.path) else { return nil }
        return "/reel/\(identifier.lowercased())"
    }

    static func tiktokVideoPath(for url: URL, configuration: MivoClearPlatformConfiguration) -> String? {
        guard configuration.platform == .tiktok,
              url.scheme?.lowercased() == "https",
              configuration.allows(host: url.host) else { return nil }
        let path = normalizedPath(url.path)
        guard path.contains("/video/") || path.hasSuffix("/video") else { return nil }
        return path
    }

    static func matchesInstagramReel(_ url: URL, path: String, configuration: MivoClearPlatformConfiguration) -> Bool {
        instagramReelPath(for: url, configuration: configuration) == normalizedPath(path)
    }

    static func matchesTikTokVideo(_ url: URL, path: String, configuration: MivoClearPlatformConfiguration) -> Bool {
        tiktokVideoPath(for: url, configuration: configuration) == normalizedPath(path)
    }

    static func instagramReelIdentifier(in path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let markerIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare("reel") == .orderedSame
                || $0.caseInsensitiveCompare("reels") == .orderedSame
        }), components.indices.contains(markerIndex + 1) else { return nil }
        let identifier = components[markerIndex + 1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? nil : identifier
    }

    private static func normalizedPath(_ value: String) -> String {
        let lowered = value.lowercased()
        let trimmed = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/\(trimmed)"
    }
}

struct MivoClearRoute: Identifiable, Equatable {
    let id = UUID()
    let platform: MivoClearPlatform?
    let quickActionID: String?
    let directURL: URL?
    let entryPoint: MivoClearEntryPoint

    init(
        platform: MivoClearPlatform? = nil,
        quickActionID: String? = nil,
        directURL: URL? = nil,
        entryPoint: MivoClearEntryPoint
    ) {
        self.platform = platform
        self.quickActionID = quickActionID
        self.directURL = directURL
        self.entryPoint = entryPoint
    }

    static func == (lhs: MivoClearRoute, rhs: MivoClearRoute) -> Bool {
        lhs.id == rhs.id
    }
}

struct MivoClearQuickAction: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let path: String
}

struct MivoClearPlatformConfiguration: Codable, Identifiable, Equatable {
    let platform: MivoClearPlatform
    var enabled: Bool
    let version: Int
    let homeURL: String
    let allowedHosts: [String]
    let blockedPathPrefixes: [String]
    let hiddenSelectors: [String]
    let quickActions: [MivoClearQuickAction]
    let updatedAt: String?

    var id: String { platform.rawValue }

    var userFacingQuickActions: [MivoClearQuickAction] {
        platform == .tiktok
            ? quickActions.filter { $0.id != "messages" }
            : quickActions
    }

    func url(for actionID: String?) -> URL? {
        let action = quickActions.first { $0.id == actionID }
        guard let base = URL(string: homeURL) else { return nil }
        guard let action else { return base }
        return URL(string: action.path, relativeTo: base)?.absoluteURL
    }

    func allows(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowedHosts.contains { allowed in
            let normalized = allowed.lowercased()
            return host == normalized || host.hasSuffix(".\(normalized)")
        }
    }

    func blocks(path: String) -> Bool {
        let normalized = path.lowercased()
        let configuredBlock = blockedPathPrefixes.contains { prefix in
            normalized == prefix.lowercased() || normalized.hasPrefix(prefix.lowercased() + "/")
        }
        if configuredBlock { return true }

        // These routes are a bundled safety floor. They cannot be relaxed by
        // stale remote configuration or a social site's client-side routing.
        switch platform {
        case .instagram:
            return normalized == "/"
                || normalized == "/reel"
                || normalized.hasPrefix("/reel/")
                || normalized == "/reels"
                || normalized.hasPrefix("/reels/")
        case .tiktok:
            return normalized == "/"
                || normalized.contains("/video/")
                || normalized.hasSuffix("/video")
                || normalized == "/discover"
                || normalized.hasPrefix("/discover/")
                || normalized == "/friends"
                || normalized.hasPrefix("/friends/")
        case .youtube:
            let pathSegments = normalized.split(separator: "/").map(String.init)
            return normalized == "/"
                || normalized == "/shorts"
                || normalized.hasPrefix("/shorts/")
                || pathSegments.contains("shorts")
        case .snapchat:
            return normalized == "/spotlight"
                || normalized.hasPrefix("/spotlight/")
                || normalized == "/discover"
                || normalized.hasPrefix("/discover/")
        }
    }

    func allowsQuickAction(path: String) -> Bool {
        let slashes = CharacterSet(charactersIn: "/")
        let normalized = path.lowercased().trimmingCharacters(in: slashes)
        return quickActions.contains { action in
            let utility = action.path.lowercased().trimmingCharacters(in: slashes)
            guard !utility.isEmpty else { return normalized.isEmpty }
            // Utility routes own their sub-paths: typing a search query or
            // stepping through the post composer stays inside the same tool.
            return normalized == utility || normalized.hasPrefix(utility + "/")
        }
    }
}

struct MivoClearAppMapping: Codable, Identifiable, Equatable {
    let platform: MivoClearPlatform
    let tokenData: Data
    let updatedAt: String

    var id: String { platform.rawValue }
}

struct MivoClearSession: Codable, Identifiable, Equatable {
    let id: String
    let platform: MivoClearPlatform
    let entryPoint: MivoClearEntryPoint
    let startedAt: String
    var endedAt: String?
    var activeSeconds: Int
    var blockedRouteCount: Int
    let filterVersion: Int
}

struct YouTubeFocusVideo: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: String?
    let durationSeconds: Int

    var durationLabel: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct YouTubeFocusChannel: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let thumbnailURL: String?
}

struct YouTubeFocusPlaylist: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let itemCount: Int
    let thumbnailURL: String?
}

enum MivoClearDefaults {
    static let configurations: [MivoClearPlatformConfiguration] = [
        MivoClearPlatformConfiguration(
            platform: .instagram,
            enabled: true,
            version: 13,
            homeURL: "https://www.instagram.com/direct/inbox/",
            allowedHosts: ["instagram.com", "facebook.com"],
            blockedPathPrefixes: ["/", "/reel", "/reels", "/explore", "/shopping", "/live"],
            hiddenSelectors: [
                "a[href='/']",
                "a[href^='/reel']",
                "a[href^='/reels']",
                "a[href^='/explore']",
                "a[href*='/shopping']",
                "a[href*='/live']",
                "[aria-label='Home']",
                "[aria-label='Reels']",
                "[aria-label='Explore']",
                "[data-testid='clips-tab']",
                "[data-testid='explore-tab']",
                "div[role='button']:has([aria-label='Live'])"
            ],
            quickActions: [
                MivoClearQuickAction(id: "messages", title: "Messages", icon: "message.fill", path: "/direct/inbox/"),
                MivoClearQuickAction(id: "search", title: "Search", icon: "magnifyingglass", path: "/explore/search/"),
                MivoClearQuickAction(id: "create", title: "Post", icon: "plus.app.fill", path: "/create/select/"),
                MivoClearQuickAction(id: "profile", title: "Profile", icon: "person.crop.circle.fill", path: "/accounts/edit/"),
                MivoClearQuickAction(id: "settings", title: "Settings", icon: "gearshape.fill", path: "/accounts/center/")
            ],
            updatedAt: nil
        ),
        MivoClearPlatformConfiguration(
            platform: .tiktok,
            enabled: true,
            version: 11,
            homeURL: "https://www.tiktok.com/messages",
            allowedHosts: ["tiktok.com"],
            blockedPathPrefixes: ["/", "/foryou", "/following", "/friends", "/live", "/shop", "/discover", "/explore"],
            hiddenSelectors: [
                "a[href='/']",
                "a[href^='/?']",
                "a[href='https://www.tiktok.com']",
                "a[href='https://www.tiktok.com/']",
                "a[href='/foryou']",
                "a[href^='/foryou?']",
                "a[href='/following']",
                "a[href^='/following?']",
                "a[href='/friends']",
                "a[href^='/friends/']",
                "a[href^='/friends?']",
                "a[href='/discover']",
                "a[href^='/discover/']",
                "a[href^='/discover?']",
                "a[href^='/live']",
                "a[href^='/shop']",
                "[data-e2e='recommend-list-item-container']",
                "[data-e2e='search-card-video-container']",
                "[data-e2e='live-nav-item']",
                "[data-e2e='shop-entrance']",
                "[data-e2e='recommend-list']",
                "[data-e2e='following-feed']",
                "[data-e2e='nav-home']",
                "[data-e2e='nav-foryou']",
                "[data-e2e='left-nav-home']",
                "[data-e2e*='nav-home']",
                "[data-e2e*='nav-foryou']",
                "[data-e2e*='nav-following']",
                "[data-e2e*='nav-friends']",
                "[data-e2e*='discover']",
                "[data-e2e='app-side-nav']",
                "[data-e2e='side-nav']",
                "[data-e2e='nav-search']",
                "[data-e2e='nav-messages']",
                "[data-e2e='nav-upload']",
                "[data-e2e='nav-profile']",
                "div[class*='DivSideNavContainer']",
                "div[class*='DivSideNavWrapper']",
                "div[class*='DivSideNavPlaceholder']",
                "[aria-label='Home']",
                "[aria-label='For You']",
                "[aria-label='Following']",
                "[aria-label='Friends']",
                "[aria-label='Discover']"
            ],
            quickActions: [
                MivoClearQuickAction(id: "create", title: "Create", icon: "plus.circle.fill", path: "/upload"),
                MivoClearQuickAction(id: "profile", title: "Profile", icon: "person.crop.circle", path: "/profile")
            ],
            updatedAt: nil
        ),
        MivoClearPlatformConfiguration(
            platform: .youtube,
            enabled: true,
            version: 5,
            homeURL: "https://www.youtube.com/results?search_query=",
            allowedHosts: ["youtube.com", "youtu.be", "googlevideo.com"],
            blockedPathPrefixes: ["/", "/shorts", "/feed/trending", "/gaming", "/live", "/shopping"],
            hiddenSelectors: [
                "a[href*='/shorts']",
                "[title='Shorts']",
                "[aria-label='Shorts']",
                "yt-tab-shape[tab-title='Shorts']",
                "ytd-reel-shelf-renderer",
                "ytd-rich-item-renderer:has(a[href^='/shorts/'])",
                "ytd-video-renderer:has(a[href^='/shorts/'])",
                "ytd-grid-video-renderer:has(a[href^='/shorts/'])",
                "ytd-rich-section-renderer:has(a[href^='/shorts'])",
                "ytd-guide-entry-renderer:has(a[href^='/shorts'])",
                "ytm-reel-shelf-renderer",
                "ytm-video-with-context-renderer:has(a[href^='/shorts/'])",
                "ytm-pivot-bar-item-renderer:has(a[href^='/shorts'])",
                "ytm-pivot-bar-item-renderer:has([aria-label='Shorts'])",
                "ytm-pivot-bar-item-renderer:has(a[href='/'])",
                "ytd-guide-entry-renderer:has(a[href='/'])",
                "ytd-watch-next-secondary-results-renderer"
            ],
            quickActions: [
                MivoClearQuickAction(id: "subscriptions", title: "Subscriptions", icon: "rectangle.stack.fill", path: "/feed/subscriptions"),
                MivoClearQuickAction(id: "search", title: "Search", icon: "magnifyingglass", path: "/results"),
                MivoClearQuickAction(id: "playlists", title: "Playlists", icon: "list.bullet.rectangle", path: "/feed/playlists")
            ],
            updatedAt: nil
        )
    ]
}
