import Foundation

/// The social apps Mivo opens inside its own view (`AppWrapperView`) instead of
/// the native app. Each one is the app's own mobile website, so it looks and
/// scrolls like the app, but Mivo can see which part of it is on screen.
///
/// Every host here must be listed under `WKAppBoundDomains` in Info.plist
/// (Apple allows ten), or Mivo's scripts never run on it.
enum SocialApp: String, Codable, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case snapchat
    case facebook
    case x
    case reddit
    case threads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .snapchat: return "Snapchat"
        case .facebook: return "Facebook"
        case .x: return "X"
        case .reddit: return "Reddit"
        case .threads: return "Threads"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera"
        case .tiktok: return "music.note"
        case .youtube: return "play.rectangle"
        case .snapchat: return "bubble.left.and.bubble.right"
        case .facebook: return "person.2"
        case .x: return "text.bubble"
        case .reddit: return "text.bubble.fill"
        case .threads: return "at"
        }
    }

    /// The App Store app's bundle identifier, which the shield extension sees.
    var bundleIdentifier: String {
        switch self {
        case .instagram: return "com.burbn.instagram"
        case .tiktok: return "com.zhiliaoapp.musically"
        case .youtube: return "com.google.ios.youtube"
        case .snapchat: return "com.toyopagroup.picaboo"
        case .facebook: return "com.facebook.Facebook"
        case .x: return "com.atebits.Tweetie2"
        case .reddit: return "com.reddit.Reddit"
        case .threads: return "com.burbn.barcelona"
        }
    }

    /// The registrable domain the site lives on; subdomains belong to it too.
    var domain: String {
        switch self {
        case .instagram: return "instagram.com"
        case .tiktok: return "tiktok.com"
        case .youtube: return "youtube.com"
        case .snapchat: return "snapchat.com"
        case .facebook: return "facebook.com"
        case .x: return "x.com"
        case .reddit: return "reddit.com"
        case .threads: return "threads.com"
        }
    }

    /// Where purposes' start paths are resolved.
    var origin: String {
        switch self {
        case .instagram: return "https://www.instagram.com"
        case .tiktok: return "https://www.tiktok.com"
        case .youtube: return "https://m.youtube.com"
        case .snapchat: return "https://www.snapchat.com"
        case .facebook: return "https://m.facebook.com"
        case .x: return "https://x.com"
        case .reddit: return "https://www.reddit.com"
        case .threads: return "https://www.threads.com"
        }
    }

    /// What one short video is called here, for counts ("10 Shorts").
    var shortVideoName: (one: String, many: String) {
        switch self {
        case .instagram, .facebook: return ("Reel", "Reels")
        case .youtube: return ("Short", "Shorts")
        case .snapchat: return ("Spotlight video", "Spotlight videos")
        case .tiktok, .x, .reddit, .threads: return ("video", "videos")
        }
    }

    func shortVideoCount(_ count: Int) -> String {
        count == 1 ? "1 \(shortVideoName.one)" : "\(count) \(shortVideoName.many)"
    }

    /// Sign-in and account pages, always reachable even when a purpose locks
    /// the rest of the site. Matched against the page's path.
    var accountPathPattern: String {
        switch self {
        case .instagram: return "^/(accounts/|challenge/|two_factor|auth_platform/|oauth/|consent/|privacy/checks/)"
        case .tiktok: return "^/(login|signup|passport|auth|logout)(/|$)"
        case .youtube: return "^/(signin|logout|account)(/|$|_)"
        case .snapchat: return "^/(accounts|login|v2/login)(/|$)"
        case .facebook: return "^/(login|checkpoint|recover|two_step_verification|two_factor|auth|privacy/consent|cookie|dialog/oauth)"
        case .x: return "^/(i/flow/|i/jf/|login|logout|account/|i/oauth|signup|i/sso)"
        case .reddit: return "^/(login|register|account|password|settings)(/|$)"
        case .threads: return "^/(login|accounts|logout)(/|$)"
        }
    }

    /// TikTok's mobile site leaves out direct messages; its desktop layout
    /// has them (the same approach Mivo Clear took).
    func usesDesktopSite(for purpose: AppPurpose) -> Bool {
        self == .tiktok && purpose.kind == .messages
    }

    func startURL(for purpose: AppPurpose) -> URL? {
        URL(string: origin + purpose.startPath)
    }

    func owns(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    func purpose(id: String) -> AppPurpose? {
        purposes.first { $0.id == id }
    }

    // MARK: - What each app offers

    var purposes: [AppPurpose] {
        switch self {
        case .instagram:
            return [
                .shortVideos(title: "Reels", detail: "Opens on Reels, and only Reels.", startPath: "/reels/", allowed: "^/(reels?/|reels$)"),
                .minutes(id: "feed", title: "Feed and stories", goal: "check your feed", back: "Back to your feed", startPath: "/",
                         onPurpose: [.feed, .stories, .post, .profile, .notifications, .messages]),
                .messages(startPath: "/direct/inbox/", allowed: "^/direct/"),
                .minutes(id: "search", title: "Look someone up", goal: "look someone up", back: "Back to search", startPath: "/explore/search/",
                         onPurpose: [.search, .profile, .post, .stories])
            ]
        case .tiktok:
            return [
                .shortVideos(title: "For You videos", detail: "Opens on For You, and only the video feed.", startPath: "/foryou",
                             allowed: "^/((foryou|following|friends)/?)?$|^/@[^/]+/video/"),
                .messages(startPath: "/messages", allowed: "^/messages")
            ]
        case .youtube:
            return [
                .minutes(id: "longVideos", title: "Long videos", goal: "watch long videos", back: "Back to long videos", startPath: "/",
                         onPurpose: [.longVideo, .feed, .search, .profile]),
                .shortVideos(title: "Shorts", detail: "Opens on Shorts, and only Shorts.", startPath: "/shorts/", allowed: "^/shorts(/|$)")
            ]
        case .snapchat:
            return [
                .shortVideos(title: "Spotlight", detail: "Opens on Spotlight, and only Spotlight.", startPath: "/spotlight", allowed: "^/spotlight(/|$)"),
                AppPurpose(
                    id: "chat", kind: .nativeApp, title: "Chat",
                    detail: "Snapchat chat only works in the Snapchat app, so this opens it for a timed window. Mivo can't keep that to chat.",
                    goal: "chat", backLabel: "", startPath: "", onPurpose: [.messages], allowedPaths: nil
                )
            ]
        case .facebook:
            return [
                .minutes(id: "feed", title: "Feed", goal: "check your feed", back: "Back to your feed", startPath: "/",
                         onPurpose: [.feed, .post, .profile, .groups, .notifications, .stories]),
                .shortVideos(title: "Reels", detail: "Opens on Reels, and only Reels.", startPath: "/reel/", allowed: "^/reels?(/|$)"),
                .minutes(id: "marketplace", title: "Marketplace", goal: "browse Marketplace", back: "Back to Marketplace", startPath: "/marketplace/",
                         onPurpose: [.marketplace, .search, .profile])
            ]
        case .x:
            return [
                .minutes(id: "feed", title: "Timeline", goal: "read your timeline", back: "Back to your timeline", startPath: "/home",
                         onPurpose: [.feed, .post, .profile, .notifications, .messages]),
                .messages(startPath: "/messages", allowed: "^/(messages|i/chat)(/|$)"),
                .minutes(id: "post", title: "Post something", goal: "post something", back: "Back to posting", startPath: "/compose/post",
                         onPurpose: [.create, .post, .profile, .notifications])
            ]
        case .reddit:
            return [
                .minutes(id: "feed", title: "Browse", goal: "browse Reddit", back: "Back to Reddit", startPath: "/",
                         onPurpose: [.feed, .post, .groups, .profile, .search, .notifications, .messages]),
                .messages(startPath: "/chat/", allowed: "^/(chat|message)(/|$)"),
                .minutes(id: "post", title: "Post something", goal: "post something", back: "Back to posting", startPath: "/submit",
                         onPurpose: [.create, .groups, .profile])
            ]
        case .threads:
            return [
                .minutes(id: "feed", title: "Feed", goal: "read your feed", back: "Back to your feed", startPath: "/",
                         onPurpose: [.feed, .post, .profile, .notifications, .search]),
                .minutes(id: "search", title: "Look someone up", goal: "look someone up", back: "Back to search", startPath: "/search",
                         onPurpose: [.search, .profile, .post])
            ]
        }
    }

    // MARK: - Which part of the app is on screen

    /// The part of the app a page belongs to, from its address alone. Pages on
    /// another site (a sign-in hop through Facebook, say) count as account pages.
    func section(for url: URL) -> AppSection {
        guard owns(host: url.host) else { return .account }
        let path = url.path.lowercased()
        if path.range(of: accountPathPattern, options: .regularExpression) != nil { return .account }
        let parts = path.split(separator: "/").map(String.init)
        let first = parts.first ?? ""
        let second = parts.count > 1 ? parts[1] : ""

        switch self {
        case .instagram:
            switch first {
            case "": return .feed
            case "reels", "reel": return .shortVideo
            case "direct": return .messages
            case "explore": return second == "search" ? .search : .explore
            case "stories": return .stories
            case "p", "tv": return .post
            case "create": return .create
            case "notifications": return .notifications
            default: return Self.looksLikeHandle(first) ? .profile : .other
            }
        case .tiktok:
            switch first {
            case "", "foryou", "following", "friends": return .shortVideo
            case "messages": return .messages
            case "search": return .search
            case "explore", "discover", "tag", "music": return .explore
            case "upload", "tiktokstudio", "creator-center": return .create
            case "live": return .other
            default:
                guard first.hasPrefix("@") else { return .other }
                if second == "video" { return .shortVideo }
                if second == "photo" { return .post }
                return .profile
            }
        case .youtube:
            switch first {
            case "": return .feed
            case "shorts": return .shortVideo
            case "watch", "live": return .longVideo
            case "results": return .search
            case "feed":
                switch second {
                case "subscriptions": return .feed
                case "trending", "explore": return .explore
                default: return .profile
                }
            case "playlist", "channel", "c", "user": return .profile
            case "gaming": return .explore
            default: return first.hasPrefix("@") ? .profile : .other
            }
        case .snapchat:
            switch first {
            case "spotlight": return .shortVideo
            case "web": return .messages
            case "discover", "stories": return .explore
            case "add": return .profile
            default: return first.hasPrefix("@") ? .profile : .other
            }
        case .facebook:
            switch first {
            case "", "home.php": return .feed
            case "reel", "reels": return .shortVideo
            case "watch": return .longVideo
            case "marketplace": return .marketplace
            case "groups": return .groups
            case "messages": return .messages
            case "search": return .search
            case "stories": return .stories
            case "story.php", "permalink.php", "photo.php", "photos": return .post
            case "notifications", "notifications.php": return .notifications
            case "profile.php": return .profile
            default: return Self.looksLikeHandle(first) ? .profile : .other
            }
        case .x:
            switch first {
            case "home": return .feed
            case "explore": return .explore
            case "search": return .search
            case "messages": return .messages
            case "notifications": return .notifications
            case "compose": return .create
            case "i":
                switch second {
                case "chat": return .messages
                case "trends": return .explore
                default: return .other
                }
            default:
                guard Self.looksLikeHandle(first) else { return .other }
                return second == "status" ? .post : .profile
            }
        case .reddit:
            switch first {
            case "", "best", "hot", "new", "top", "rising": return .feed
            case "r":
                if second == "popular" || second == "all" { return .feed }
                return parts.count > 2 && parts[2] == "comments" ? .post : .groups
            case "user", "u": return .profile
            case "search": return .search
            case "chat", "message": return .messages
            case "submit": return .create
            case "notifications": return .notifications
            default: return .other
            }
        case .threads:
            switch first {
            case "": return .feed
            case "search": return .search
            case "activity": return .notifications
            default:
                guard first.hasPrefix("@") else { return .other }
                return second == "post" ? .post : .profile
            }
        }
    }

    /// The name of a section on this app, as a person would say it.
    func name(of section: AppSection) -> String {
        switch section {
        case .shortVideo:
            switch self {
            case .tiktok: return "the For You feed"
            case .snapchat: return "Spotlight"
            default: return shortVideoName.many
            }
        case .longVideo: return self == .facebook ? "Facebook Watch" : "a long video"
        case .feed: return self == .reddit ? "the Reddit feed" : "the feed"
        case .stories: return "stories"
        case .messages: return "messages"
        case .search: return "search"
        case .explore: return self == .instagram ? "Explore" : "trending"
        case .profile: return "a profile"
        case .post: return "a post"
        case .create: return "posting"
        case .notifications: return "notifications"
        case .marketplace: return "Marketplace"
        case .groups: return self == .reddit ? "a community" : "groups"
        case .account: return "your account"
        case .other: return "another page"
        }
    }

    /// Usernames: letters, digits, dots and underscores, as Instagram, X and
    /// Facebook allow them. Anything else (a file name, a reserved page) isn't one.
    private static func looksLikeHandle(_ segment: String) -> Bool {
        !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
            && !segment.hasSuffix(".php")
    }
}

/// The part of an app a page belongs to. Recorded per second, so Mivo can tell
/// whether someone is doing what they said they came to do.
enum AppSection: String, Codable, CaseIterable {
    case shortVideo
    case longVideo
    case feed
    case stories
    case messages
    case search
    case explore
    case profile
    case post
    case create
    case notifications
    case marketplace
    case groups
    case account
    case other

    /// Sign-in pages and pages Mivo can't place never count as drifting.
    var isNeutral: Bool { self == .account || self == .other }
}

/// What someone says they'll do in an app before it opens. It decides how the
/// session is counted, what's reachable, and what counts as drifting.
struct AppPurpose: Identifiable, Equatable {
    enum Kind: String, Codable {
        /// Short videos, counted one by one. Only the video feed is reachable.
        case count
        /// Minutes. The whole app is reachable; drifting gets a reminder.
        case minutes
        /// Messages, unlimited and free. Only messages are reachable.
        case messages
        /// Something the web version can't do; the native app opens for a timed window.
        case nativeApp
    }

    /// Stable: stored on every session.
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    /// Finishes "You came to …".
    let goal: String
    /// The button that takes them back.
    let backLabel: String
    let startPath: String
    /// Sections that count as doing this. Others count as drifting, except
    /// neutral ones (see `AppSection.isNeutral`).
    let onPurpose: Set<AppSection>
    /// For count and messages purposes: the only paths reachable (a regular
    /// expression matched against the page's path), besides sign-in pages.
    let allowedPaths: String?

    var runsInMivo: Bool { kind != .nativeApp }

    func isDrifting(in section: AppSection) -> Bool {
        !section.isNeutral && !onPurpose.contains(section)
    }

    static func shortVideos(title: String, detail: String, startPath: String, allowed: String) -> AppPurpose {
        AppPurpose(id: "shortVideos", kind: .count, title: title, detail: detail, goal: "watch \(title)",
                   backLabel: "Back to \(title)", startPath: startPath, onPurpose: [.shortVideo], allowedPaths: allowed)
    }

    static func minutes(id: String, title: String, goal: String, back: String, startPath: String, onPurpose: Set<AppSection>) -> AppPurpose {
        AppPurpose(id: id, kind: .minutes, title: title, detail: "", goal: goal, backLabel: back,
                   startPath: startPath, onPurpose: onPurpose, allowedPaths: nil)
    }

    static func messages(startPath: String, allowed: String) -> AppPurpose {
        AppPurpose(id: "messages", kind: .messages, title: "Messages",
                   detail: "As long as you need, and nothing but messages.",
                   goal: "reply to messages", backLabel: "Back to messages",
                   startPath: startPath, onPurpose: [.messages], allowedPaths: allowed)
    }
}

/// Everything decided before an app opens in Mivo.
struct AppWindowConfig: Identifiable, Equatable {
    let id = UUID()
    let app: SocialApp
    let purpose: AppPurpose
    /// Short videos for a count purpose, minutes for a minutes purpose; unused for messages.
    let amount: Int
    /// The reason step's answer, when one was asked.
    let reason: Intention?
    /// Outside a scroll window the app still opens, already slowed down.
    let startsSlowed: Bool

    static func == (lhs: AppWindowConfig, rhs: AppWindowConfig) -> Bool { lhs.id == rhs.id }

    /// How the session is stored: `WrapperSessionLimit` raw value, or nil for messages.
    var limitKind: WrapperSessionLimit? {
        switch purpose.kind {
        case .count: return .reels
        case .minutes: return .minutes
        case .messages, .nativeApp: return nil
        }
    }
}

/// The last purpose and amount per app, so the next window starts there.
enum AppPickStore {
    static func purposeKey(_ app: SocialApp) -> String { "mivo.appWindow.\(app.rawValue).purpose" }
    static func amountKey(_ app: SocialApp, purposeID: String) -> String { "mivo.appWindow.\(app.rawValue).\(purposeID).amount" }

    static func lastPurpose(for app: SocialApp, defaults: UserDefaults = .standard) -> AppPurpose? {
        if let id = defaults.string(forKey: purposeKey(app)), let purpose = app.purpose(id: id) { return purpose }
        // Instagram's picks from before every app opened in Mivo.
        guard app == .instagram, let kind = defaults.string(forKey: WrapperPickStore.kindKey) else { return nil }
        return app.purpose(id: kind == WrapperSessionLimit.reels.rawValue ? "shortVideos" : "feed")
    }

    static func lastAmount(for app: SocialApp, purpose: AppPurpose, defaults: UserDefaults = .standard) -> Int? {
        let stored = defaults.integer(forKey: amountKey(app, purposeID: purpose.id))
        if stored > 0 { return stored }
        guard app == .instagram, let kind = purpose.kind == .count ? WrapperSessionLimit.reels : (purpose.kind == .minutes ? .minutes : nil),
              defaults.string(forKey: WrapperPickStore.kindKey) == kind.rawValue else { return nil }
        let legacy = defaults.integer(forKey: WrapperPickStore.amountKey)
        return legacy > 0 ? legacy : nil
    }

    static func save(app: SocialApp, purpose: AppPurpose, amount: Int?, defaults: UserDefaults = .standard) {
        defaults.set(purpose.id, forKey: purposeKey(app))
        if let amount, amount > 0 { defaults.set(amount, forKey: amountKey(app, purposeID: purpose.id)) }
    }
}

/// A shield asked for the window flow; see `AppViewModel.pendingAppWindow`.
/// Nil `app` starts on the flow's first question, which app.
struct AppWindowRequest: Identifiable, Equatable {
    let id = UUID()
    let app: SocialApp?
}

enum AppMappingError: LocalizedError, Equatable {
    case selectOneApp
    case alreadyChosen(SocialApp)

    var errorDescription: String? {
        switch self {
        case .selectOneApp: return "Choose exactly one app, without a category or website."
        case .alreadyChosen(let app): return "That app is already chosen as \(app.title)."
        }
    }
}

/// Whether this device has answered "Which apps do you use?" — in onboarding,
/// or in the one-time prompt people who joined before it get on their next
/// open. App picks are Screen Time tokens, which belong to the device, so the
/// answer does too.
enum AppPicksPrompt {
    static let answeredKey = "mivo.appPicks.answered"

    static func isAnswered(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: answeredKey)
    }

    static func markAnswered(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: answeredKey)
    }
}
