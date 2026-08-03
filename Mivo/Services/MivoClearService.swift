import Foundation
import WebKit
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum MivoClearError: LocalizedError {
    case unavailable
    case invalidConfiguration
    case ageRestricted
    case googleNotConfigured
    case googleSignInFailed(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Mivo Clear BETA is temporarily unavailable."
        case .invalidConfiguration: return "Mivo Clear BETA received an invalid platform configuration."
        case .ageRestricted: return "Mivo Clear BETA is available to users age 13 and older."
        case .googleNotConfigured: return "YouTube setup is not configured in this build yet."
        case .googleSignInFailed(let detail): return detail
        case .api(let detail): return detail
        }
    }
}

@MainActor
final class MivoClearStore: ObservableObject {
    static let shared = MivoClearStore()
    private static let currentTutorialVersion = 1

    @Published private(set) var configurations: [MivoClearPlatformConfiguration] = []
    @Published private(set) var sessions: [MivoClearSession] = []
    @Published var lastError: String?

    private var loadedEmail: String?
    private var activeSession: MivoClearSession?
    private var activeBeganAt: Date?

    private init() {}

    func prepare(for appVM: AppViewModel) async {
        guard let email = appVM.user?.email else { return }
        if loadedEmail != email {
            loadedEmail = email
            sessions = StorageService.load([MivoClearSession].self, forKey: .mivoClearSessions, email: email) ?? []
        }
        do {
            let remote = try await ProductExpansionService.mivoClearConfigurations()
            guard !remote.isEmpty else { throw MivoClearError.unavailable }
            configurations = try validated(hardened(remote))
            lastError = nil
        } catch {
            // A bundled, validated ruleset keeps Clear usable during a network or
            // backend rollout issue. Remote disabled flags still take precedence.
            do {
                configurations = try validated(MivoClearDefaults.configurations)
                lastError = nil
            } catch {
                configurations = []
                lastError = MivoClearError.invalidConfiguration.localizedDescription
            }
        }
    }

    func configuration(for platform: MivoClearPlatform) -> MivoClearPlatformConfiguration? {
        guard ProductExpansionStore.shared.isEnabled(.mivoClear),
              ProductExpansionStore.shared.isEnabled(platform.featureKey),
              let config = configurations.first(where: { $0.platform == platform }),
              config.enabled else { return nil }
        return config
    }

    func isEligible(profile: OnboardingProfile) -> Bool? {
        if let age = profile.age { return age >= 13 }
        if let range = profile.ageRange, range != "Under 18" { return true }
        guard let email = loadedEmail else { return nil }
        return StorageService.load(Bool.self, forKey: .mivoClearAgeConfirmed, email: email)
    }

    func confirmAge13OrOlder() {
        guard let email = loadedEmail else { return }
        StorageService.save(true, forKey: .mivoClearAgeConfirmed, email: email)
    }

    func hasSeenDisclosure() -> Bool {
        guard let email = loadedEmail else { return false }
        return StorageService.load(Bool.self, forKey: .mivoClearDisclosureSeen, email: email) ?? false
    }

    func acceptDisclosure() {
        guard let email = loadedEmail else { return }
        StorageService.save(true, forKey: .mivoClearDisclosureSeen, email: email)
    }

    func hasCompletedTutorial() -> Bool {
        guard let email = loadedEmail else { return false }
        let completedVersion = StorageService.load(
            Int.self,
            forKey: .mivoClearTutorialVersion,
            email: email
        ) ?? 0
        return completedVersion >= Self.currentTutorialVersion
    }

    func completeTutorial() {
        guard let email = loadedEmail else { return }
        StorageService.save(
            Self.currentTutorialVersion,
            forKey: .mivoClearTutorialVersion,
            email: email
        )
    }

    func beginSession(platform: MivoClearPlatform, entryPoint: MivoClearEntryPoint, filterVersion: Int) {
        endActiveSession()
        let now = ISO8601DateFormatter().string(from: Date())
        activeSession = MivoClearSession(
            id: UUID().uuidString.lowercased(),
            platform: platform,
            entryPoint: entryPoint,
            startedAt: now,
            endedAt: nil,
            activeSeconds: 0,
            blockedRouteCount: 0,
            filterVersion: filterVersion
        )
        activeBeganAt = Date()
    }

    func pauseActiveSession() {
        guard var current = activeSession, let activeBeganAt else { return }
        current.activeSeconds += max(0, Int(Date().timeIntervalSince(activeBeganAt)))
        activeSession = current
        self.activeBeganAt = nil
    }

    func resumeActiveSession() {
        guard activeSession != nil, activeBeganAt == nil else { return }
        activeBeganAt = Date()
    }

    func recordBlockedRoute() {
        guard var current = activeSession else { return }
        current.blockedRouteCount += 1
        activeSession = current
    }

    func endActiveSession() {
        pauseActiveSession()
        guard var finished = activeSession else { return }
        finished.endedAt = ISO8601DateFormatter().string(from: Date())
        activeSession = nil
        activeBeganAt = nil
        sessions.insert(finished, at: 0)
        sessions = Array(sessions.prefix(180))
        if let email = loadedEmail {
            StorageService.save(sessions, forKey: .mivoClearSessions, email: email)
        }
        Task { try? await ProductExpansionService.recordMivoClearSession(finished) }
    }

    var minutesToday: Int {
        let calendar = Calendar.current
        return sessions.reduce(0) { total, session in
            guard let date = ISO8601DateFormatter().date(from: session.startedAt),
                  calendar.isDateInToday(date) else { return total }
            return total + session.activeSeconds
        } / 60
    }

    var sessionsToday: Int {
        sessions.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.startedAt) else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
    }

    private func validated(_ values: [MivoClearPlatformConfiguration]) throws -> [MivoClearPlatformConfiguration] {
        let knownHosts: [MivoClearPlatform: Set<String>] = [
            .instagram: ["instagram.com", "facebook.com"],
            .tiktok: ["tiktok.com"],
            .youtube: ["youtube.com", "youtu.be", "googlevideo.com"],
            .snapchat: ["snapchat.com"]
        ]
        var seen = Set<MivoClearPlatform>()
        for value in values {
            let home = URL(string: value.homeURL)
            guard !seen.contains(value.platform),
                  value.version > 0,
                  home?.scheme == "https",
                  value.allows(host: home?.host),
                  !value.allowedHosts.isEmpty,
                  Set(value.allowedHosts).isSubset(of: knownHosts[value.platform] ?? []),
                  value.blockedPathPrefixes.allSatisfy({ $0.hasPrefix("/") && !$0.contains(":") }),
                  value.quickActions.allSatisfy({ $0.path.hasPrefix("/") && !$0.path.lowercased().contains("javascript:") }),
                  value.hiddenSelectors.allSatisfy({
                      !$0.lowercased().contains("<script")
                          && !$0.lowercased().contains("javascript:")
                          && !$0.contains("{")
                          && !$0.contains("}")
                  }) else {
                throw MivoClearError.invalidConfiguration
            }
            seen.insert(value.platform)
        }
        return values
    }

    private func hardened(_ remote: [MivoClearPlatformConfiguration]) -> [MivoClearPlatformConfiguration] {
        MivoClearDefaults.configurations.map { bundled in
            guard let server = remote.first(where: { $0.platform == bundled.platform }) else {
                return bundled
            }
            let serverBlockedPaths = server.blockedPathPrefixes.filter {
                !(bundled.platform == .tiktok && $0.lowercased().hasPrefix("/upload"))
            }
            let serverHiddenSelectors = server.hiddenSelectors.filter {
                let selector = $0.lowercased()
                if bundled.platform == .tiktok,
                   selector.contains("upload") || selector.contains("create") {
                    return false
                }
                if bundled.platform == .instagram,
                   selector.contains(":has(") && selector.contains("/reel") {
                    return false
                }
                return true
            }
            return MivoClearPlatformConfiguration(
                platform: bundled.platform,
                enabled: server.enabled,
                version: max(server.version, bundled.version),
                homeURL: bundled.homeURL,
                allowedHosts: bundled.allowedHosts,
                blockedPathPrefixes: Array(Set(bundled.blockedPathPrefixes + serverBlockedPaths)).sorted(),
                hiddenSelectors: Array(Set(bundled.hiddenSelectors + serverHiddenSelectors)).sorted(),
                quickActions: bundled.quickActions,
                updatedAt: server.updatedAt
            )
        }
    }
}

extension MivoClearPlatform {
    var featureKey: MivoFeatureKey {
        switch self {
        case .instagram: return .mivoClearInstagram
        case .tiktok: return .mivoClearTikTok
        case .youtube: return .mivoClearYouTube
        case .snapchat: return .mivoClearSnapchat
        }
    }
}

enum MivoClearContentRuleCompiler {
    @MainActor private static var cachedLists: [String: WKContentRuleList] = [:]

    @MainActor
    static func compile(configuration: MivoClearPlatformConfiguration) async throws -> WKContentRuleList? {
        // Keep a local compiler revision in the identifier so a shipped safety
        // rule change cannot be masked by WebKit's previously compiled list.
        let identifier = "mivo-clear-\(configuration.platform.rawValue)-v\(configuration.version)-fast-r3"
        if let cached = cachedLists[identifier] { return cached }

        // YouTube's Polymer tree is large and changes constantly. Broad :has()
        // selectors force WebKit to repeatedly walk that tree and cause visible
        // stutter. Route blocking still prevents every Shorts URL, while the
        // remaining simple selectors hide its direct entry points cheaply.
        let selectors: [String]
        if configuration.platform == .youtube || configuration.platform == .instagram {
            // Instagram Direct mutates its conversation tree constantly. Complex
            // relational selectors make WebKit repeatedly rescan that entire tree.
            // Route enforcement remains active for every blocked destination.
            selectors = configuration.hiddenSelectors.filter { !$0.localizedCaseInsensitiveContains(":has(") }
        } else if configuration.platform == .tiktok {
            // These nodes are needed to open one chosen profile or activity video.
            // Continuous navigation is stopped by the route and gesture guards.
            let requiredMediaSelectors: Set<String> = [
                "a[href*='/video/']",
                "[data-e2e='user-post-item']",
                "[data-e2e='browse-video']",
                "[data-e2e='video-feed']"
            ]
            selectors = configuration.hiddenSelectors.filter { !requiredMediaSelectors.contains($0.lowercased()) }
        } else {
            selectors = configuration.hiddenSelectors
        }
        guard !selectors.isEmpty else { return nil }

        if let existing = await existingRuleList(identifier: identifier) {
            cachedLists[identifier] = existing
            return existing
        }

        let rules: [[String: Any]] = selectors.map { selector in
            [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": configuration.allowedHosts.map { "*\($0)" }
                ],
                "action": [
                    "type": "css-display-none",
                    "selector": selector
                ]
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        guard let json = String(data: data, encoding: .utf8) else { throw MivoClearError.invalidConfiguration }
        let compiled: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { list, error in
                if let error { continuation.resume(throwing: error) }
                else if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: MivoClearError.invalidConfiguration) }
            }
        }
        cachedLists[identifier] = compiled
        return compiled
    }

    @MainActor
    private static func existingRuleList(identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }
}

enum MivoClearRuntimeGuard {
    static func script(configuration: MivoClearPlatformConfiguration, singleMediaURL: URL? = nil) throws -> WKUserScript {
        let payload: [String: Any] = [
            "platform": configuration.platform.rawValue,
            "homeURL": configuration.homeURL,
            "allowedHosts": configuration.allowedHosts,
            "blockedPrefixes": configuration.blockedPathPrefixes,
            "utilityPaths": configuration.quickActions.map(\.path),
            "singleInstagramReelPath": singleMediaURL.flatMap {
                MivoClearSingleMediaPolicy.instagramReelPath(for: $0, configuration: configuration)
            } ?? "",
            "singleTikTokVideoPath": singleMediaURL.flatMap {
                MivoClearSingleMediaPolicy.tiktokVideoPath(for: $0, configuration: configuration)
            } ?? ""
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MivoClearError.invalidConfiguration
        }
        let source = """
        (() => {
          const config = \(json);
          const instagramSingleKey = 'mivo.clear.single.instagram.reel';
          const instagramInlineKey = 'mivo.clear.single.instagram.inline';
          const tiktokSingleKey = 'mivo.clear.single.tiktok.video';
          const tiktokInlineKey = 'mivo.clear.single.tiktok.inline';
          const trim = value => {
            const result = (value || '/').toLowerCase().replace(/\\/+$/, '');
            return result.length ? result : '/';
          };
          const utilityPaths = config.utilityPaths.map(trim).filter(value => value !== '/');
          const isUtilityPath = path => utilityPaths.some(value =>
            path === value || path.startsWith(value + '/')
          );
          const originKey = 'mivo.clear.single.origin';
          const backKey = 'mivo.clear.back.until';
          const isBackNavigation = () => {
            const until = Number(sessionStorage.getItem(backKey) || 0);
            return Number.isFinite(until) && Date.now() <= until;
          };
          const rememberOrigin = () => {
            // The route the viewer came from, so an escaped swipe can be
            // returned to that exact conversation instead of a generic inbox.
            try {
              const path = trim(location.pathname);
              if (isInstagramReel(path) || isTikTokVideo(path)) return;
              if (blocked(path)) return;
              sessionStorage.setItem(originKey, location.href);
            } catch (_) {}
          };
          const storedOrigin = () => {
            try { return sessionStorage.getItem(originKey) || ''; } catch (_) { return ''; }
          };
          let escapeNotified = false;
          const notifyEscape = reason => {
            if (escapeNotified) return;
            escapeNotified = true;
            try {
              window.webkit.messageHandlers.mivoClearSingleMedia.postMessage({
                escapedSingleMedia: true,
                origin: storedOrigin(),
                reason: reason || ''
              });
            } catch (_) {}
          };
          const instagramReelIdentifier = path => {
            const parts = trim(path).split('/').filter(Boolean);
            const marker = parts.findIndex(value => value === 'reel' || value === 'reels');
            return marker >= 0 && parts.length > marker + 1 ? parts[marker + 1] : '';
          };
          const isInstagramReel = path => !!instagramReelIdentifier(path);
          const isTikTokVideo = path => path.includes('/video/') || path.endsWith('/video');
          const currentInstagramSingle = () => trim(sessionStorage.getItem(instagramSingleKey) || config.singleInstagramReelPath || '');
          const inlineInstagramSingle = () => sessionStorage.getItem(instagramInlineKey) === '1';
          const currentTikTokSingle = () => trim(sessionStorage.getItem(tiktokSingleKey) || config.singleTikTokVideoPath || '');
          const inlineTikTokSingle = () => sessionStorage.getItem(tiktokInlineKey) === '1';
          const lockedInstagramScroll = new Map();
          const lockedTikTokScroll = new Map();
          const notifySingleMedia = active => {
            try {
              window.webkit.messageHandlers.mivoClearSingleMedia.postMessage({ active: !!active });
            } catch (_) {}
          };
          const presentInstagramSingleMedia = target => {
            if (!target) return false;
            try {
              window.webkit.messageHandlers.mivoClearSingleMedia.postMessage({
                instagramMediaURL: target.href
              });
              return true;
            } catch (_) {
              return false;
            }
          };
          let pendingInstagramDirectMediaUntil = 0;
          let pendingInstagramDirectMediaArea = 0;
          let pendingInstagramDirectMediaSource = '';
          let pendingInstagramPointerMedia = null;
          let pendingInstagramPointerOrigin = null;
          let suppressInstagramMediaClickUntil = 0;
          const instagramReelURL = rawValue => {
            if (!rawValue) return null;
            try {
              const normalizedValue = String(rawValue).replace(/\\\\\\//g, '/');
              const embeddedPath = normalizedValue.match(
                /(?:https?:\\/\\/[^\\s"'<>]+)?\\/(?:reel|reels|share\\/reel)\\/([a-z0-9_-]{5,40})/i
              );
              if (embeddedPath && embeddedPath[1]) {
                return new URL(`https://www.instagram.com/reel/${embeddedPath[1]}/`);
              }
              let target = new URL(normalizedValue, location.href);
              if (target.hostname.toLowerCase() === 'l.instagram.com') {
                const wrapped = target.searchParams.get('u');
                if (wrapped) target = new URL(wrapped, location.href);
              }
              if (!allowedHost(target.hostname.toLowerCase()) || !isInstagramReel(target.pathname)) return null;
              return target;
            } catch (_) {
              return null;
            }
          };
          const instagramReelFromObject = root => {
            if (!root || (typeof root !== 'object' && typeof root !== 'function')) return null;
            const visited = new WeakSet();
            let remaining = 900;
            const inspect = (value, depth) => {
              if (remaining <= 0 || depth > 8 || value == null) return null;
              remaining -= 1;
              if (typeof value === 'string') return instagramReelURL(value);
              if (typeof value !== 'object' && typeof value !== 'function') return null;
              if (visited.has(value)) return null;
              visited.add(value);

              try {
                const productType = String(value.product_type || value.productType || '').toLowerCase();
                const looksLikeVideo = productType === 'clips' || productType === 'reels' ||
                  value.media_type === 2 || value.mediaType === 2 ||
                  !!value.video_versions || !!value.videoVersions || !!value.clips_metadata;
                const shortCode = value.code || value.shortcode || value.short_code;
                if (looksLikeVideo && typeof shortCode === 'string' &&
                    /^[a-z0-9_-]{5,40}$/i.test(shortCode)) {
                  return new URL(`https://www.instagram.com/reel/${shortCode}/`);
                }
              } catch (_) {}

              let keys = [];
              try { keys = Object.keys(value); } catch (_) { return null; }
              const priority = keys.filter(key =>
                /url|href|permalink|link|code|short|media|video|clip|reel|props|children|state|item|attachment|share/i.test(key)
              );
              const ignored = new Set([
                'return', 'sibling', 'stateNode', '_debugOwner', '_owner',
                'alternate', 'firstEffect', 'lastEffect', 'nextEffect'
              ]);
              const remainder = keys.filter(key => !priority.includes(key) && !ignored.has(key));
              for (const key of priority.concat(remainder).slice(0, 90)) {
                let nested;
                try { nested = value[key]; } catch (_) { continue; }
                const match = inspect(nested, depth + 1);
                if (match) return match;
              }
              return null;
            };
            return inspect(root, 0);
          };
          const instagramReelFromNode = node => {
            if (!(node instanceof Element)) return null;
            for (const attribute of ['href', 'data-href', 'data-url', 'data-permalink']) {
              const match = instagramReelURL(node.getAttribute(attribute));
              if (match) return match;
            }
            const anchor = node.matches("a[href*='/reel/'], a[href*='/reels/'], a[href*='/share/reel/']")
              ? node
              : node.querySelector("a[href*='/reel/'], a[href*='/reels/'], a[href*='/share/reel/']");
            const anchorMatch = instagramReelURL(anchor && (anchor.href || anchor.getAttribute('href')));
            if (anchorMatch) return anchorMatch;

            let propertyNames = [];
            try { propertyNames = Object.getOwnPropertyNames(node); } catch (_) {}
            for (const key of propertyNames) {
              if (!key.startsWith('__reactProps$') &&
                  !key.startsWith('__reactFiber$') &&
                  !key.startsWith('__reactContainer$')) continue;
              let internalValue;
              try { internalValue = node[key]; } catch (_) { continue; }
              const match = instagramReelFromObject(internalValue);
              if (match) return match;
            }
            return null;
          };
          const safeInstagramVideoSource = rawValue => {
            if (!rawValue) return null;
            try {
              const target = new URL(String(rawValue), location.href);
              const host = target.hostname.toLowerCase();
              const allowedMediaHost = target.protocol === 'https:' && (
                host === 'instagram.com' || host.endsWith('.instagram.com') ||
                host === 'cdninstagram.com' || host.endsWith('.cdninstagram.com') ||
                host === 'fbcdn.net' || host.endsWith('.fbcdn.net')
              );
              return allowedMediaHost ? target : null;
            } catch (_) {
              return null;
            }
          };
          const presentInstagramDirectVideo = target => {
            if (!target) return false;
            try {
              window.webkit.messageHandlers.mivoClearSingleMedia.postMessage({
                instagramVideoSource: target.href
              });
              return true;
            } catch (_) {
              return false;
            }
          };
          const setInlineInstagramSingle = active => {
            const previous = inlineInstagramSingle();
            if (active) sessionStorage.setItem(instagramInlineKey, '1');
            else sessionStorage.removeItem(instagramInlineKey);
            if (previous !== active) {
              try {
                window.webkit.messageHandlers.mivoClearSingleMedia.postMessage({
                  instagramDirectViewer: !!active
                });
              } catch (_) {}
            }
          };
          const setInlineTikTokSingle = active => {
            const previous = inlineTikTokSingle();
            if (active) sessionStorage.setItem(tiktokInlineKey, '1');
            else sessionStorage.removeItem(tiktokInlineKey);
            if (previous !== active) notifySingleMedia(active);
          };
          const largestVisibleInstagramVideo = () => {
            if (config.platform !== 'instagram') return false;
            return Array.from(document.querySelectorAll('video')).reduce((largest, video) => {
              const rect = video.getBoundingClientRect();
              const visible = rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
              if (!visible || !(rect.height >= innerHeight * 0.40 || rect.width >= innerWidth * 0.62)) return largest;
              if (!largest) return video;
              const largestRect = largest.getBoundingClientRect();
              return rect.width * rect.height > largestRect.width * largestRect.height ? video : largest;
            }, null);
          };
          const instagramVideoArea = video => {
            if (!video) return 0;
            const rect = video.getBoundingClientRect();
            return Math.max(0, rect.width) * Math.max(0, rect.height);
          };
          const instagramVideoSource = video => {
            if (!video) return '';
            return String(video.currentSrc || video.src || video.getAttribute('src') || '');
          };
          const pointInsideVideo = (event, video) => {
            if (!event || !video || !Number.isFinite(event.clientX) || !Number.isFinite(event.clientY)) return false;
            const rect = video.getBoundingClientRect();
            return event.clientX >= rect.left && event.clientX <= rect.right &&
              event.clientY >= rect.top && event.clientY <= rect.bottom;
          };
          const markInstagramDirectMediaClick = event => {
            const route = trim(location.pathname);
            const isConversation = route.startsWith('/direct/t/') ||
              (route.startsWith('/direct/') && route !== '/direct' && route !== '/direct/inbox');
            if (config.platform !== 'instagram' || !isConversation) return null;
            const video = largestVisibleInstagramVideo();
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            let reelURL = null;
            for (const node of path) {
              reelURL = instagramReelFromNode(node);
              if (reelURL) break;
            }
            for (let node = event.target, depth = 0; !reelURL && node && depth < 18;
                 depth += 1, node = node.parentElement) {
              reelURL = instagramReelFromNode(node);
            }
            const touchesVideo = !!video && (
              pointInsideVideo(event, video) ||
              path.some(node => node === video || (node && node.contains && node.contains(video)))
            );
            const touchesReelPreview = path.some(node => {
              if (!(node instanceof Element)) return false;
              const marker = [
                node.getAttribute('aria-label'),
                node.getAttribute('title'),
                node.getAttribute('role')
              ].filter(Boolean).join(' ').toLowerCase();
              if (marker.includes('reel') || marker.includes('play video')) return true;
              const rect = node.getBoundingClientRect();
              const sizedLikePreview = rect.width >= 90 && rect.height >= 120;
              return sizedLikePreview && !!node.querySelector(
                "video, svg[aria-label*='Reel' i], svg[aria-label*='Play' i], [aria-label*='Reel' i]"
              );
            });
            if (!reelURL && !touchesVideo && !touchesReelPreview) return null;
            pendingInstagramDirectMediaUntil = Date.now() + 2600;
            pendingInstagramDirectMediaArea = instagramVideoArea(video);
            pendingInstagramDirectMediaSource = instagramVideoSource(video);
            return {
              reelURL,
              videoSource: safeInstagramVideoSource(pendingInstagramDirectMediaSource),
              isPreview: true
            };
          };
          const presentInstagramDirectMediaCandidate = candidate => {
            if (!candidate || !candidate.isPreview) return false;
            if (candidate.reelURL) return presentInstagramSingleMedia(candidate.reelURL);
            if (candidate.videoSource) return presentInstagramDirectVideo(candidate.videoSource);
            return false;
          };
          const hasLargeInstagramVideo = () => {
            return !!largestVisibleInstagramVideo();
          };
          const visibleInstagramReplyControl = () => {
            const candidates = document.querySelectorAll(
              "input, textarea, [role='textbox'], [contenteditable='true'], [data-placeholder]"
            );
            for (const control of candidates) {
              const marker = [
                control.getAttribute('placeholder'),
                control.getAttribute('aria-label'),
                control.getAttribute('data-placeholder'),
                control.textContent
              ].filter(Boolean).join(' ').trim().toLowerCase();
              if (!marker.includes('reply to')) continue;
              const rect = control.getBoundingClientRect();
              if (rect.width > 40 && rect.height > 18 && rect.bottom > 0 && rect.top < innerHeight) {
                return control;
              }
            }
            const bottomElements = document.elementsFromPoint(
              Math.max(1, innerWidth / 2),
              Math.max(1, innerHeight - 44)
            );
            for (const element of bottomElements) {
              const marker = (element.textContent || '').trim().toLowerCase();
              if (marker.includes('reply to')) return element;
            }
            return null;
          };
          const hasInstagramMediaOverlay = () => {
            if (config.platform !== 'instagram') return false;
            if (visibleInstagramReplyControl()) return true;
            const candidates = document.querySelectorAll("[role='dialog'], iframe, [aria-modal='true']");
            return Array.from(candidates).some(node => {
              const rect = node.getBoundingClientRect();
              const style = getComputedStyle(node);
              const visible = style.display !== 'none' && style.visibility !== 'hidden' &&
                rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
              return visible && rect.height >= innerHeight * 0.42 && rect.width >= innerWidth * 0.45;
            });
          };
          const hasInstagramDirectReelViewer = () => {
            const route = trim(location.pathname);
            if (config.platform !== 'instagram' || !route.startsWith('/direct')) return false;
            const video = largestVisibleInstagramVideo();
            return !!video && !!visibleInstagramReplyControl();
          };
          const detectInlineInstagramViewer = (forceScan = false) => {
            if (config.platform !== 'instagram') return;
            const path = trim(location.pathname);
            if (isInstagramReel(path)) {
              pendingInstagramDirectMediaUntil = 0;
              return;
            }
            if (path.startsWith('/direct')) {
              const video = largestVisibleInstagramVideo();
              const pendingClick = Date.now() <= pendingInstagramDirectMediaUntil;
              const grewAfterTap = pendingClick && instagramVideoArea(video) >=
                Math.max(1, pendingInstagramDirectMediaArea) * 1.12;
              const currentSource = instagramVideoSource(video);
              const sourceChangedAfterTap = pendingClick && !!currentSource &&
                !!pendingInstagramDirectMediaSource &&
                currentSource !== pendingInstagramDirectMediaSource;
              const directViewerVisible = hasInstagramDirectReelViewer();
              const viewerVisible = directViewerVisible ||
                (pendingClick && (hasInstagramMediaOverlay() || grewAfterTap || sourceChangedAfterTap));
              if (viewerVisible) {
                pendingInstagramDirectMediaUntil = 0;
                setInlineInstagramSingle(true);
              } else if (inlineInstagramSingle() && !pendingClick && !directViewerVisible) {
                setInlineInstagramSingle(false);
              }
              return;
            }
            setInlineInstagramSingle(hasLargeInstagramVideo() || hasInstagramMediaOverlay());
          };
          const hasLargeTikTokVideo = () => {
            if (config.platform !== 'tiktok') return false;
            return Array.from(document.querySelectorAll('video')).some(video => {
              const rect = video.getBoundingClientRect();
              const visible = rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
              return visible && (rect.height >= innerHeight * 0.46 || rect.width >= innerWidth * 0.72);
            });
          };
          const detectInlineTikTokViewer = () => {
            if (config.platform !== 'tiktok') return;
            const path = trim(location.pathname);
            if (isTikTokVideo(path)) {
              setInlineTikTokSingle(false);
              return;
            }
            setInlineTikTokSingle(hasLargeTikTokVideo());
          };
          const lockInstagramViewerScroll = () => {
            const candidates = new Set([document.scrollingElement, document.documentElement, document.body]);
            document.querySelectorAll('video').forEach(video => {
              const rect = video.getBoundingClientRect();
              if (!(rect.height >= innerHeight * 0.46 || rect.width >= innerWidth * 0.72)) return;
              let node = video.parentElement;
              for (let depth = 0; node && depth < 12; depth += 1, node = node.parentElement) {
                if (node.scrollHeight > node.clientHeight + 4 || node.scrollWidth > node.clientWidth + 4) {
                  candidates.add(node);
                }
              }
            });
            candidates.forEach(node => {
              if (node && !lockedInstagramScroll.has(node)) {
                lockedInstagramScroll.set(node, { top: node.scrollTop || 0, left: node.scrollLeft || 0 });
              }
            });
          };
          const lockTikTokViewerScroll = () => {
            const candidates = new Set([document.scrollingElement, document.documentElement, document.body]);
            document.querySelectorAll('video').forEach(video => {
              const rect = video.getBoundingClientRect();
              if (!(rect.height >= innerHeight * 0.46 || rect.width >= innerWidth * 0.72)) return;
              let node = video.parentElement;
              for (let depth = 0; node && depth < 14; depth += 1, node = node.parentElement) {
                if (node.scrollHeight > node.clientHeight + 4 || node.scrollWidth > node.clientWidth + 4) {
                  candidates.add(node);
                }
              }
            });
            candidates.forEach(node => {
              if (node && !lockedTikTokScroll.has(node)) {
                lockedTikTokScroll.set(node, { top: node.scrollTop || 0, left: node.scrollLeft || 0 });
              }
            });
          };
          if (config.platform === 'instagram' && config.singleInstagramReelPath) {
            sessionStorage.setItem(instagramSingleKey, trim(config.singleInstagramReelPath));
          }
          if (config.platform === 'tiktok' && config.singleTikTokVideoPath) {
            sessionStorage.setItem(tiktokSingleKey, trim(config.singleTikTokVideoPath));
          }
          const allowedHost = host => config.allowedHosts.some(value =>
            host === value || host.endsWith('.' + value)
          );
          const blocked = (rawPath, rawHost = location.hostname) => {
            const path = trim(rawPath);
            const host = (rawHost || '').toLowerCase();
            if (config.platform === 'instagram' && host.startsWith('accountscenter.')) return false;
            if (isUtilityPath(path)) return false;
            if (config.platform === 'instagram' && isInstagramReel(path) && path === currentInstagramSingle()) {
              return false;
            }
            if (config.platform === 'tiktok' && isTikTokVideo(path) && path === currentTikTokSingle()) {
              return false;
            }
            const configured = config.blockedPrefixes.some(value => {
              const prefix = trim(value);
              return path === prefix || (prefix !== '/' && path.startsWith(prefix + '/'));
            });
            if (configured) return true;
            if (config.platform === 'instagram') {
              return path === '/' || path === '/reel' || path.startsWith('/reel/') || path === '/reels' || path.startsWith('/reels/');
            }
            if (config.platform === 'tiktok') {
              return path === '/' || path.includes('/video/') || path.endsWith('/video') ||
                path === '/discover' || path.startsWith('/discover/') ||
                path === '/friends' || path.startsWith('/friends/');
            }
            if (config.platform === 'youtube') {
              return path === '/' || path.split('/').filter(Boolean).includes('shorts');
            }
            if (config.platform === 'snapchat') {
              return path === '/spotlight' || path.startsWith('/spotlight/') || path === '/discover' || path.startsWith('/discover/');
            }
            return false;
          };
          const checkCurrentRoute = () => {
            const path = trim(location.pathname);
            detectInlineInstagramViewer();
            detectInlineTikTokViewer();
            removeYouTubeShortsEntries();
            removeTikTokNativeSidebar();
            removeInstagramDirectBackControl();
            rememberOrigin();
            if (config.platform === 'instagram' && !isInstagramReel(path)) {
              sessionStorage.removeItem(instagramSingleKey);
            }
            if (config.platform === 'tiktok' && !isTikTokVideo(path) && !inlineTikTokSingle()) {
              sessionStorage.removeItem(tiktokSingleKey);
            }
            if (allowedHost(location.hostname.toLowerCase()) && blocked(path)) {
              // A back gesture that lands on a filtered route should keep
              // stepping back instead of throwing the viewer to the home route.
              if (isBackNavigation() && history.length > 1) {
                history.back();
                return;
              }
              location.replace(config.homeURL);
              return;
            }
            detectSingleMediaEscape();
            applyInstagramSingleLock();
            applyTikTokSingleLock();
          };
          const visibleSuggestedReelLabel = () => {
            const labels = document.querySelectorAll("h1, h2, h3, h4, [role='heading'], span");
            for (const label of labels) {
              const text = (label.textContent || '').trim().toLowerCase();
              if (text !== 'suggested' && text !== 'suggested reels' &&
                  text !== 'suggested for you' && text !== 'more reels') continue;
              const rect = label.getBoundingClientRect();
              if (rect.bottom > 0 && rect.top < innerHeight && rect.width > 0) return true;
            }
            return false;
          };
          let lockedInstagramVideoSource = '';
          let changedSourceStreak = 0;
          const detectSingleMediaEscape = () => {
            const path = trim(location.pathname);
            const instagramActive = config.platform === 'instagram' &&
              ((isInstagramReel(path) && path === currentInstagramSingle()) || inlineInstagramSingle());
            const tiktokActive = config.platform === 'tiktok' &&
              ((isTikTokVideo(path) && path === currentTikTokSingle()) || inlineTikTokSingle());
            if (!instagramActive && !tiktokActive) {
              lockedInstagramVideoSource = '';
              changedSourceStreak = 0;
              escapeNotified = false;
              return;
            }
            if (instagramActive) {
              // Instagram keeps the shared reel mounted and appends "Suggested"
              // reels underneath. Either signal means the viewer moved past the
              // one reel the conversation actually linked to.
              if (visibleSuggestedReelLabel()) {
                notifyEscape('suggested');
                return;
              }
              const source = instagramVideoSource(largestVisibleInstagramVideo());
              if (!source) return;
              if (!lockedInstagramVideoSource) {
                lockedInstagramVideoSource = source;
                changedSourceStreak = 0;
                return;
              }
              if (source === lockedInstagramVideoSource) {
                changedSourceStreak = 0;
                return;
              }
              // Instagram re-attaches sources during quality switches, so only a
              // change that survives consecutive checks counts as a new reel.
              changedSourceStreak += 1;
              if (changedSourceStreak >= 3) notifyEscape('nextVideo');
              return;
            }
            const selected = currentTikTokSingle();
            if (isTikTokVideo(path) && isTikTokVideo(selected) && path !== selected) {
              notifyEscape('nextVideo');
            }
          };
          const removeYouTubeShortsEntries = () => {
            if (config.platform !== 'youtube') return;
            const candidates = document.querySelectorAll(
              "a[href*='/shorts'], [title='Shorts'], [aria-label='Shorts'], yt-tab-shape[tab-title='Shorts']"
            );
            candidates.forEach(node => {
              const target = node.closest(
                'ytm-pivot-bar-item-renderer, ytd-guide-entry-renderer, ytd-mini-guide-entry-renderer, tp-yt-paper-tab, [role="tab"], [role="navigation"] li'
              ) || node;
              target.style.setProperty('display', 'none', 'important');
              target.setAttribute('aria-hidden', 'true');
            });
          };
          const removeTikTokNativeSidebar = () => {
            if (config.platform !== 'tiktok') return;
            let style = document.getElementById('mivo-clear-tiktok-navigation-style');
            if (!style) {
              style = document.createElement('style');
              style.id = 'mivo-clear-tiktok-navigation-style';
              style.textContent = `
                [data-e2e='app-side-nav'], [data-e2e='side-nav'],
                [data-e2e='nav-search'], [data-e2e='nav-messages'],
                [data-e2e='nav-upload'], [data-e2e='nav-profile'],
                div[class*='DivSideNavContainer'], div[class*='DivSideNavWrapper'],
                div[class*='DivSideNavPlaceholder'] {
                  display: none !important; width: 0 !important; min-width: 0 !important;
                }
                div[class*='DivMainContainer'], main[class*='Main'] {
                  margin-left: 0 !important; left: 0 !important; width: 100% !important;
                  max-width: 100% !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            }

            const controls = document.querySelectorAll(
              "[data-e2e='nav-search'], [data-e2e='nav-messages'], [data-e2e='nav-upload'], [data-e2e='nav-profile']"
            );
            controls.forEach(control => {
              let node = control;
              for (let depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
                const rect = node.getBoundingClientRect();
                if (rect.left <= 24 && rect.width >= 48 && rect.width <= 320 && rect.height >= innerHeight * 0.55) {
                  node.style.setProperty('display', 'none', 'important');
                  node.style.setProperty('width', '0', 'important');
                  node.style.setProperty('min-width', '0', 'important');
                  break;
                }
              }
            });
          };
          const removeInstagramSuggestedReels = () => {
            if (config.platform !== 'instagram') return;
            const path = trim(location.pathname);
            const active = (isInstagramReel(path) && path === currentInstagramSingle()) ||
              inlineInstagramSingle();
            if (!active) return;

            document.querySelectorAll("h1, h2, h3, h4, [role='heading'], span").forEach(label => {
              const text = (label.textContent || '').trim().toLowerCase();
              const isSuggestedLabel = text === 'suggested' ||
                text === 'suggested reels' ||
                text === 'suggested for you' ||
                text === 'more reels';
              if (!isSuggestedLabel) return;

              let removable = label;
              for (let depth = 0, node = label; node && depth < 8; depth += 1, node = node.parentElement) {
                const rect = node.getBoundingClientRect();
                const containsSuggestedMedia = !!node.querySelector &&
                  !!node.querySelector("a[href*='/reel/'], a[href*='/reels/'], video");
                if (containsSuggestedMedia && rect.height >= 100) {
                  removable = node;
                  break;
                }
              }
              removable.style.setProperty('display', 'none', 'important');
              removable.setAttribute('aria-hidden', 'true');
            });

            document.querySelectorAll("button, [role='button'], a").forEach(control => {
              const marker = [
                control.getAttribute('aria-label'),
                control.getAttribute('title'),
                control.textContent
              ].filter(Boolean).join(' ').trim().toLowerCase();
              const rect = control.getBoundingClientRect();
              const isTopBackControl = rect.left < 96 && rect.top < 130 &&
                (marker === 'back' || marker.includes('go back'));
              if (isTopBackControl) {
                control.style.setProperty('display', 'none', 'important');
                control.setAttribute('aria-hidden', 'true');
              }
            });
          };
          const removeInstagramDirectBackControl = () => {
            if (config.platform !== 'instagram') return;
            const path = trim(location.pathname);
            if (!path.startsWith('/direct')) return;

            let style = document.getElementById('mivo-clear-instagram-direct-back-style');
            if (!style) {
              style = document.createElement('style');
              style.id = 'mivo-clear-instagram-direct-back-style';
              style.textContent = `
                svg[aria-label='Back' i],
                svg[aria-label*='go back' i],
                [data-icon='arrow-left'],
                [data-testid*='back' i][role='button'] {
                  display: none !important;
                  visibility: hidden !important;
                  pointer-events: none !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            }

            document.querySelectorAll(
              "svg, button, [role='button'], a, [tabindex='0']"
            ).forEach(control => {
              const backIconSelector =
                "svg[aria-label='Back' i], svg[aria-label*='go back' i], [data-icon='arrow-left']";
              const icon = control.matches("svg")
                ? (control.matches(backIconSelector) ? control : null)
                : control.querySelector(
                    backIconSelector
                  );
              const marker = [
                control.getAttribute('aria-label'),
                control.getAttribute('title'),
                control.getAttribute('data-testid'),
                icon && icon.getAttribute('aria-label'),
                icon && icon.querySelector('title') && icon.querySelector('title').textContent
              ].filter(Boolean).join(' ').trim().toLowerCase();
              const rect = control.getBoundingClientRect();
              const explicitlyBack = marker === 'back' || marker.includes('go back') ||
                marker.includes('arrow-left') || marker.includes('arrow left') || !!icon;
              const isSmallTopLeftSVG = control.matches('svg') &&
                rect.left < 105 && rect.top < 165 &&
                rect.width >= 12 && rect.width <= 56 &&
                rect.height >= 12 && rect.height <= 56 &&
                control.querySelectorAll('path, polyline, line').length > 0;
              const isDirectEscape = explicitlyBack || isSmallTopLeftSVG;
              if (!isDirectEscape) return;

              let target = control;
              const wrapper = control.closest("button, [role='button'], a, [tabindex='0']");
              if (wrapper) {
                const wrapperRect = wrapper.getBoundingClientRect();
                if (wrapperRect.left < 120 && wrapperRect.top < 180 &&
                    wrapperRect.width <= 120 && wrapperRect.height <= 100) {
                  target = wrapper;
                }
              }
              target.style.setProperty('display', 'none', 'important');
              target.style.setProperty('visibility', 'hidden', 'important');
              target.style.setProperty('pointer-events', 'none', 'important');
              target.setAttribute('aria-hidden', 'true');
              target.setAttribute('data-mivo-clear-hidden-direct-back', '1');
            });
          };
          const applyInstagramSingleLock = () => {
            if (config.platform !== 'instagram') return;
            const path = trim(location.pathname);
            const active = (isInstagramReel(path) && path === currentInstagramSingle()) || inlineInstagramSingle();
            let style = document.getElementById('mivo-clear-single-reel-style');
            if (!active) {
              lockedInstagramScroll.clear();
              if (style) style.remove();
              document.documentElement.style.removeProperty('overflow');
              document.documentElement.style.removeProperty('overscroll-behavior');
              document.documentElement.style.removeProperty('touch-action');
              if (document.body) {
                document.body.style.removeProperty('overflow');
                document.body.style.removeProperty('overscroll-behavior');
                document.body.style.removeProperty('touch-action');
              }
              return;
            }
            if (!style) {
              style = document.createElement('style');
              style.id = 'mivo-clear-single-reel-style';
              style.textContent = `
                html, body { overflow: hidden !important; overscroll-behavior: none !important; touch-action: none !important; }
                [role='dialog'], [role='presentation'] { overscroll-behavior: none !important; }
                button[aria-label='Next'], button[aria-label='Previous'],
                [role='button'][aria-label='Next'], [role='button'][aria-label='Previous'],
                button:has(svg[aria-label='Next']), button:has(svg[aria-label='Previous']),
                a[href^='/reels/'], a[href='/reels/'] { display: none !important; }
              `;
              (document.head || document.documentElement).appendChild(style);
            }
            document.documentElement.style.setProperty('overflow', 'hidden', 'important');
            document.documentElement.style.setProperty('overscroll-behavior', 'none', 'important');
            document.documentElement.style.setProperty('touch-action', 'none', 'important');
            if (document.body) {
              document.body.style.setProperty('overflow', 'hidden', 'important');
              document.body.style.setProperty('overscroll-behavior', 'none', 'important');
              document.body.style.setProperty('touch-action', 'none', 'important');
            }
            lockInstagramViewerScroll();
            removeInstagramSuggestedReels();
          };
          const applyTikTokSingleLock = () => {
            if (config.platform !== 'tiktok') return;
            const path = trim(location.pathname);
            const active = (isTikTokVideo(path) && path === currentTikTokSingle()) || inlineTikTokSingle();
            let style = document.getElementById('mivo-clear-single-tiktok-style');
            if (!active) {
              lockedTikTokScroll.clear();
              if (style) style.remove();
              document.documentElement.style.removeProperty('overflow');
              document.documentElement.style.removeProperty('overscroll-behavior');
              document.documentElement.style.removeProperty('touch-action');
              if (document.body) {
                document.body.style.removeProperty('overflow');
                document.body.style.removeProperty('overscroll-behavior');
                document.body.style.removeProperty('touch-action');
              }
              return;
            }
            if (!style) {
              style = document.createElement('style');
              style.id = 'mivo-clear-single-tiktok-style';
              style.textContent = `
                html, body { overflow: hidden !important; overscroll-behavior: none !important; touch-action: none !important; }
                video, button, [role='button'], [role='slider'] { touch-action: manipulation !important; }
                [data-e2e='recommend-list'], [data-e2e='recommend-list-item-container'],
                [data-e2e='related-video-list'], [data-e2e='video-switch-next'], [data-e2e='video-switch-prev'],
                button[aria-label*='next' i], button[aria-label*='previous' i] { display: none !important; }
              `;
              (document.head || document.documentElement).appendChild(style);
            }
            document.documentElement.style.setProperty('overflow', 'hidden', 'important');
            document.documentElement.style.setProperty('overscroll-behavior', 'none', 'important');
            document.documentElement.style.setProperty('touch-action', 'none', 'important');
            if (document.body) {
              document.body.style.setProperty('overflow', 'hidden', 'important');
              document.body.style.setProperty('overscroll-behavior', 'none', 'important');
              document.body.style.setProperty('touch-action', 'none', 'important');
            }
            lockTikTokViewerScroll();
            document.querySelectorAll('video').forEach(video => {
              try {
                video.setAttribute('playsinline', '');
                video.playsInline = true;
                const result = video.play();
                if (result && result.catch) result.catch(() => {});
              } catch (_) {}
            });
          };
          document.addEventListener('pointerdown', event => {
            if (config.platform !== 'instagram' || event.button > 0) return;
            pendingInstagramPointerMedia = markInstagramDirectMediaClick(event);
            pendingInstagramPointerOrigin = pendingInstagramPointerMedia
              ? { x: event.clientX, y: event.clientY, pointerId: event.pointerId }
              : null;
          }, true);
          document.addEventListener('pointermove', event => {
            if (!pendingInstagramPointerOrigin ||
                pendingInstagramPointerOrigin.pointerId !== event.pointerId) return;
            const distance = Math.hypot(
              event.clientX - pendingInstagramPointerOrigin.x,
              event.clientY - pendingInstagramPointerOrigin.y
            );
            if (distance > 14) {
              pendingInstagramPointerMedia = null;
              pendingInstagramPointerOrigin = null;
            }
          }, true);
          document.addEventListener('pointercancel', () => {
            pendingInstagramPointerMedia = null;
            pendingInstagramPointerOrigin = null;
          }, true);
          document.addEventListener('pointerup', event => {
            if (!pendingInstagramPointerOrigin ||
                pendingInstagramPointerOrigin.pointerId !== event.pointerId) return;
            const candidate = pendingInstagramPointerMedia;
            pendingInstagramPointerMedia = null;
            pendingInstagramPointerOrigin = null;
            if (!presentInstagramDirectMediaCandidate(candidate)) return;
            suppressInstagramMediaClickUntil = Date.now() + 900;
            event.preventDefault();
            event.stopImmediatePropagation();
            event.stopPropagation();
          }, true);
          document.addEventListener('click', event => {
            if (config.platform === 'instagram' && event.target) {
              if (Date.now() <= suppressInstagramMediaClickUntil) {
                event.preventDefault();
                event.stopImmediatePropagation();
                event.stopPropagation();
                return;
              }
              const directMedia = markInstagramDirectMediaClick(event);
              if (directMedia && directMedia.isPreview) {
                event.preventDefault();
                event.stopImmediatePropagation();
                event.stopPropagation();
                presentInstagramDirectMediaCandidate(directMedia);
                return;
              }
              const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
              let reelURL = null;
              for (const node of path) {
                reelURL = instagramReelFromNode(node);
                if (reelURL) break;
              }
              for (let node = event.target, depth = 0; !reelURL && node && depth < 24; depth += 1, node = node.parentElement) {
                reelURL = instagramReelFromNode(node);
              }
              if (reelURL) {
                event.preventDefault();
                event.stopImmediatePropagation();
                event.stopPropagation();
                presentInstagramSingleMedia(reelURL);
                return;
              }
            }
            const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (anchor) {
              try {
                const target = new URL(anchor.href, location.href);
                const targetPath = trim(target.pathname);
                if (config.platform === 'instagram' && allowedHost(target.hostname.toLowerCase()) && isInstagramReel(targetPath)) {
                  event.preventDefault();
                  event.stopImmediatePropagation();
                  event.stopPropagation();
                  presentInstagramSingleMedia(target);
                  return;
                }
                if (config.platform === 'tiktok' && allowedHost(target.hostname.toLowerCase()) && isTikTokVideo(targetPath)) {
                  const selected = currentTikTokSingle();
                  if (!isTikTokVideo(selected)) {
                    sessionStorage.setItem(tiktokSingleKey, targetPath);
                    notifySingleMedia(true);
                  } else if (selected !== targetPath) {
                    event.preventDefault();
                    event.stopImmediatePropagation();
                    notifyEscape('nextVideo');
                    return;
                  }
                }
                if (allowedHost(target.hostname.toLowerCase()) && blocked(target.pathname, target.hostname)) {
                  event.preventDefault();
                  event.stopImmediatePropagation();
                  location.assign(config.homeURL);
                  return;
                }
              } catch (_) {}
            }
            if (config.platform === 'tiktok' && event.target && event.target.closest) {
              const control = event.target.closest('[data-e2e], [aria-label], [role="link"], [role="button"]');
              if (!control) return;
              const marker = ((control.getAttribute('data-e2e') || '') + ' ' +
                (control.getAttribute('aria-label') || '') + ' ' +
                (control.textContent || '')).trim().toLowerCase();
              const blockedControl = marker === 'home' || marker === 'for you' || marker === 'following' ||
                marker === 'friends' || marker === 'discover' ||
                marker.includes('nav-home') || marker.includes('nav-foryou') ||
                marker.includes('nav-following') || marker.includes('nav-friends') || marker.includes('discover');
              if (blockedControl) {
                event.preventDefault();
                event.stopImmediatePropagation();
                location.assign(config.homeURL);
              }
            }
            if (config.platform === 'instagram') {
              [80, 180, 360, 700, 1200].forEach(delay => setTimeout(() => {
                detectInlineInstagramViewer(true);
                applyInstagramSingleLock();
              }, delay));
            }
            if (config.platform === 'tiktok') {
              setTimeout(() => {
                const path = trim(location.pathname);
                if (isTikTokVideo(path) && !isTikTokVideo(currentTikTokSingle())) {
                  sessionStorage.setItem(tiktokSingleKey, path);
                }
                detectInlineTikTokViewer();
                applyTikTokSingleLock();
              }, 180);
            }
          }, true);
          let blockedSingleMediaGesture = false;
          const stopSingleMediaMotion = event => {
            const path = trim(location.pathname);
            const instagramActive = config.platform === 'instagram' &&
              ((isInstagramReel(path) && path === currentInstagramSingle()) || inlineInstagramSingle());
            const tiktokActive = config.platform === 'tiktok' &&
              ((isTikTokVideo(path) && path === currentTikTokSingle()) || inlineTikTokSingle());
            const active = instagramActive || tiktokActive;
            if (!active) return false;
            if (tiktokActive) {
              event.preventDefault();
              event.stopImmediatePropagation();
              event.stopPropagation();
              return true;
            }
            const interactive = event.target && event.target.closest
              ? event.target.closest('input, [role="slider"], [contenteditable="true"]')
              : null;
            if (interactive) return false;
            event.preventDefault();
            event.stopImmediatePropagation();
            event.stopPropagation();
            return true;
          };
          document.addEventListener('touchstart', () => {
            blockedSingleMediaGesture = false;
          }, { capture: true, passive: true });
          document.addEventListener('touchmove', event => {
            if (stopSingleMediaMotion(event)) blockedSingleMediaGesture = true;
          }, { capture: true, passive: false });
          document.addEventListener('touchend', event => {
            if (!blockedSingleMediaGesture) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            event.stopPropagation();
            blockedSingleMediaGesture = false;
          }, { capture: true, passive: false });
          document.addEventListener('touchcancel', () => {
            blockedSingleMediaGesture = false;
          }, { capture: true, passive: true });
          document.addEventListener('wheel', stopSingleMediaMotion, { capture: true, passive: false });
          document.addEventListener('pointermove', event => {
            if (!event.pointerType || event.pointerType === 'touch') stopSingleMediaMotion(event);
          }, { capture: true, passive: false });
          document.addEventListener('gesturechange', stopSingleMediaMotion, { capture: true, passive: false });
          document.addEventListener('scroll', event => {
            const node = event.target === document ? document.scrollingElement : event.target;
            const locked = config.platform === 'instagram' && inlineInstagramSingle()
              ? lockedInstagramScroll.get(node)
              : config.platform === 'tiktok' && inlineTikTokSingle()
                ? lockedTikTokScroll.get(node)
                : null;
            if (!node || !locked) return;
            if (node.scrollTop !== locked.top) node.scrollTop = locked.top;
            if (node.scrollLeft !== locked.left) node.scrollLeft = locked.left;
          }, true);
          document.addEventListener('keydown', event => {
            const path = trim(location.pathname);
            const active = (config.platform === 'instagram' && ((isInstagramReel(path) && path === currentInstagramSingle()) || inlineInstagramSingle())) ||
              (config.platform === 'tiktok' && ((isTikTokVideo(path) && path === currentTikTokSingle()) || inlineTikTokSingle()));
            if (!active) return;
            if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown'].includes(event.key)) event.preventDefault();
          }, true);
          let checkScheduled = false;
          let checkTimer = null;
          const scheduleCheck = () => {
            if (checkScheduled) return;
            checkScheduled = true;
            const delay = config.platform === 'instagram' ? 180 : 60;
            checkTimer = setTimeout(() => {
              checkScheduled = false;
              checkCurrentRoute();
            }, delay);
          };
          ['pushState', 'replaceState'].forEach(name => {
            const original = history[name];
            history[name] = function(...args) {
              if (config.platform === 'instagram' && args.length > 2 && args[2]) {
                const target = instagramReelURL(args[2]);
                if (target && !isInstagramReel(location.pathname)) {
                  presentInstagramSingleMedia(target);
                  return null;
                }
              }
              if (config.platform === 'tiktok' && args.length > 2 && args[2]) {
                try {
                  const target = new URL(args[2], location.href);
                  const targetPath = trim(target.pathname);
                  if (allowedHost(target.hostname.toLowerCase()) && isTikTokVideo(targetPath)) {
                    const selected = currentTikTokSingle();
                    if (!isTikTokVideo(selected)) {
                      sessionStorage.setItem(tiktokSingleKey, targetPath);
                      notifySingleMedia(true);
                    } else if (selected !== targetPath) {
                      notifyEscape('nextVideo');
                      return null;
                    }
                  }
                } catch (_) {}
              }
              const result = original.apply(this, args);
              scheduleCheck();
              return result;
            };
          });
          window.addEventListener('popstate', scheduleCheck);
          window.addEventListener('hashchange', scheduleCheck);
          window.addEventListener('pageshow', scheduleCheck);
          document.addEventListener('yt-navigate-finish', scheduleCheck);
          new MutationObserver(scheduleCheck).observe(document.documentElement, { childList: true, subtree: true });
          if (config.platform === 'instagram') {
            window.setInterval(scheduleCheck, 450);
          }
          scheduleCheck();
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}

@MainActor
final class YouTubeFocusService: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var channels: [YouTubeFocusChannel] = []
    @Published private(set) var videos: [YouTubeFocusVideo] = []
    @Published private(set) var playlists: [YouTubeFocusPlaylist] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    static let readonlyScope = "https://www.googleapis.com/auth/youtube.readonly"

    private static var googleClientID: String? {
        for key in ["MIVO_GOOGLE_CLIENT_ID", "GIDClientID"] {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty,
               !value.contains("$("),
               !value.localizedCaseInsensitiveContains("not-configured") {
                return value
            }
        }
        return nil
    }

    static var isGoogleConfigured: Bool {
        googleClientID != nil
    }

    var isConfigured: Bool {
        Self.isGoogleConfigured
    }

    func restore() async {
        #if canImport(GoogleSignIn)
        configureGoogleSignIn()
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                Task { @MainActor in
                    self.isSignedIn = user?.grantedScopes?.contains(Self.readonlyScope) == true
                    continuation.resume()
                }
            }
        }
        #else
        isSignedIn = false
        #endif
    }

    func signIn() async {
        guard isConfigured else { lastError = MivoClearError.googleNotConfigured.localizedDescription; return }
        #if canImport(GoogleSignIn)
        configureGoogleSignIn()
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else {
            lastError = "Mivo could not present Google sign-in."
            return
        }
        isLoading = true
        defer { isLoading = false }
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [Self.readonlyScope]
            ) { result, error in
                Task { @MainActor in
                    if let error {
                        self.lastError = error.localizedDescription
                    } else {
                        self.isSignedIn = result?.user.grantedScopes?.contains(Self.readonlyScope) == true
                        self.lastError = self.isSignedIn ? nil : "YouTube read access was not granted."
                    }
                    continuation.resume()
                }
            }
        }
        #else
        lastError = MivoClearError.googleNotConfigured.localizedDescription
        #endif
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        isSignedIn = false
        channels = []
        videos = []
        playlists = []
    }

    func loadSubscriptions() async {
        await load {
            let response: SubscriptionResponse = try await self.request(
                path: "subscriptions",
                query: ["part": "snippet", "mine": "true", "maxResults": "50"]
            )
            self.channels = response.items.map {
                YouTubeFocusChannel(
                    id: $0.snippet.resourceId.channelId,
                    title: $0.snippet.title,
                    thumbnailURL: $0.snippet.thumbnails.medium?.url ?? $0.snippet.thumbnails.defaultImage?.url
                )
            }
        }
    }

    func loadPlaylists() async {
        await load {
            let response: PlaylistResponse = try await self.request(
                path: "playlists",
                query: ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"]
            )
            self.playlists = response.items.map {
                YouTubeFocusPlaylist(
                    id: $0.id,
                    title: $0.snippet.title,
                    itemCount: $0.contentDetails.itemCount,
                    thumbnailURL: $0.snippet.thumbnails.medium?.url ?? $0.snippet.thumbnails.defaultImage?.url
                )
            }
        }
    }

    func search(_ query: String, channelID: String? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || channelID != nil else { videos = []; return }
        await load {
            var queryItems = [
                "part": "snippet",
                "type": "video",
                "maxResults": "25",
                "safeSearch": "moderate"
            ]
            if !trimmed.isEmpty { queryItems["q"] = trimmed }
            if let channelID { queryItems["channelId"] = channelID; queryItems["order"] = "date" }
            let search: SearchResponse = try await self.request(path: "search", query: queryItems)
            let ids = search.items.map(\.id.videoId).filter { !$0.isEmpty }
            guard !ids.isEmpty else { self.videos = []; return }
            let details: VideoResponse = try await self.request(
                path: "videos",
                query: ["part": "snippet,contentDetails", "id": ids.joined(separator: ",")]
            )
            self.videos = details.items.compactMap { item in
                let duration = Self.seconds(fromISO8601Duration: item.contentDetails.duration)
                guard duration > 180 else { return nil }
                return YouTubeFocusVideo(
                    id: item.id,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: item.snippet.thumbnails.medium?.url ?? item.snippet.thumbnails.defaultImage?.url,
                    durationSeconds: duration
                )
            }
        }
    }

    func loadPlaylistVideos(_ playlistID: String) async {
        await load {
            let playlist: PlaylistItemsResponse = try await self.request(
                path: "playlistItems",
                query: ["part": "contentDetails", "playlistId": playlistID, "maxResults": "50"]
            )
            let ids = playlist.items.map(\.contentDetails.videoId).filter { !$0.isEmpty }
            guard !ids.isEmpty else { self.videos = []; return }
            let details: VideoResponse = try await self.request(
                path: "videos",
                query: ["part": "snippet,contentDetails", "id": ids.joined(separator: ",")]
            )
            self.videos = details.items.compactMap { item in
                let duration = Self.seconds(fromISO8601Duration: item.contentDetails.duration)
                guard duration > 180 else { return nil }
                return YouTubeFocusVideo(
                    id: item.id,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: item.snippet.thumbnails.medium?.url ?? item.snippet.thumbnails.defaultImage?.url,
                    durationSeconds: duration
                )
            }
        }
    }

    private func load(_ operation: @escaping () async throws -> Void) async {
        guard isSignedIn else { lastError = "Connect YouTube first."; return }
        isLoading = true
        defer { isLoading = false }
        do { try await operation(); lastError = nil }
        catch { lastError = error.localizedDescription }
    }

    private func request<Response: Decodable>(path: String, query: [String: String]) async throws -> Response {
        #if canImport(GoogleSignIn)
        let accessToken = try await freshGoogleAccessToken()
        guard var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(path)") else {
            throw MivoClearError.api("Invalid YouTube request.")
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw MivoClearError.api("Invalid YouTube request.") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = value?["error"] as? [String: Any]
            throw MivoClearError.api(error?["message"] as? String ?? "YouTube could not load this content.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
        #else
        throw MivoClearError.googleNotConfigured
        #endif
    }

    #if canImport(GoogleSignIn)
    private func freshGoogleAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw MivoClearError.googleSignInFailed("Connect YouTube first.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshed, error in
                if let error { continuation.resume(throwing: error) }
                else if let token = refreshed?.accessToken.tokenString { continuation.resume(returning: token) }
                else { continuation.resume(throwing: MivoClearError.googleSignInFailed("YouTube authorization expired.")) }
            }
        }
    }
    #endif

    private func configureGoogleSignIn() {
        #if canImport(GoogleSignIn)
        guard let clientID = Self.googleClientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        #endif
    }

    private static func seconds(fromISO8601Duration value: String) -> Int {
        let expression = try? NSRegularExpression(pattern: #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#)
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression?.firstMatch(in: value, range: range) else { return 0 }
        func number(_ index: Int) -> Int {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return 0 }
            return Int(value[swiftRange]) ?? 0
        }
        return number(1) * 3600 + number(2) * 60 + number(3)
    }
}

private struct YouTubeThumbnail: Decodable { let url: String }
private struct YouTubeThumbnails: Decodable {
    let medium: YouTubeThumbnail?
    let defaultImage: YouTubeThumbnail?
    enum CodingKeys: String, CodingKey { case medium; case defaultImage = "default" }
}
private struct SubscriptionResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let snippet: Snippet }
    struct Snippet: Decodable {
        let title: String
        let resourceId: Resource
        let thumbnails: YouTubeThumbnails
    }
    struct Resource: Decodable { let channelId: String }
}
private struct SearchResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let id: Identifier }
    struct Identifier: Decodable { let videoId: String }
}
private struct VideoResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let id: String; let snippet: Snippet; let contentDetails: ContentDetails }
    struct Snippet: Decodable { let title: String; let channelTitle: String; let thumbnails: YouTubeThumbnails }
    struct ContentDetails: Decodable { let duration: String }
}
private struct PlaylistResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let id: String; let snippet: Snippet; let contentDetails: ContentDetails }
    struct Snippet: Decodable { let title: String; let thumbnails: YouTubeThumbnails }
    struct ContentDetails: Decodable { let itemCount: Int }
}
private struct PlaylistItemsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let contentDetails: ContentDetails }
    struct ContentDetails: Decodable { let videoId: String }
}
