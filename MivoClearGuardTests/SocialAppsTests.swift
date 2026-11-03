import XCTest
@testable import Mivo

final class SocialAppsTests: XCTestCase {
    private func url(_ app: SocialApp, _ path: String) -> URL {
        URL(string: app.origin + path)!
    }

    // MARK: - Purposes

    func testEveryLockAllowsItsOwnStartPage() throws {
        // A lock that refused its own start page would send the page in circles.
        for app in SocialApp.allCases {
            for purpose in app.purposes where purpose.runsInMivo {
                let start = try XCTUnwrap(app.startURL(for: purpose), "\(app) \(purpose.id)")
                XCTAssertTrue(app.owns(host: start.host), "\(app) \(purpose.id)")
                if let lock = WrapperLock(app: app, purpose: purpose) {
                    XCTAssertTrue(lock.allows(start), "\(app) \(purpose.id) blocks its own start \(start)")
                }
            }
        }
    }

    func testOnlyCountAndMessagePurposesLock() {
        for app in SocialApp.allCases {
            for purpose in app.purposes {
                let locks = WrapperLock(app: app, purpose: purpose) != nil
                XCTAssertEqual(locks, purpose.kind == .count || purpose.kind == .messages, "\(app) \(purpose.id)")
            }
        }
    }

    func testPurposeIDsAreUniquePerApp() {
        for app in SocialApp.allCases {
            let ids = app.purposes.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(app)")
            XCTAssertFalse(ids.isEmpty, "\(app)")
        }
    }

    func testYouTubeOffersLongVideosAndShorts() {
        let kinds = SocialApp.youtube.purposes.map { "\($0.id):\($0.kind.rawValue)" }
        XCTAssertEqual(kinds, ["longVideos:minutes", "shortVideos:count"])
    }

    func testSnapchatChatOpensTheAppItself() {
        let chat = SocialApp.snapchat.purpose(id: "chat")
        XCTAssertEqual(chat?.kind, .nativeApp)
        XCTAssertEqual(chat?.runsInMivo, false)
    }

    func testEveryAppDomainIsAppBound() throws {
        // Scripts only run on domains listed in Info.plist, and Apple allows ten.
        let bound = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String])
        XCTAssertLessThanOrEqual(bound.count, 10)
        for app in SocialApp.allCases {
            XCTAssertTrue(bound.contains(app.domain), "\(app.domain) missing from WKAppBoundDomains")
        }
    }

    // MARK: - Locks

    func testReelsLockKeepsInstagramToReels() throws {
        let lock = try XCTUnwrap(WrapperLock(app: .instagram, purpose: SocialApp.instagram.purpose(id: "shortVideos")!))
        XCTAssertTrue(lock.allows(url(.instagram, "/reel/Cabc123xyz/")))
        XCTAssertTrue(lock.allows(url(.instagram, "/reels/")))
        XCTAssertTrue(lock.allows(url(.instagram, "/accounts/login/")))
        XCTAssertFalse(lock.allows(url(.instagram, "/")))
        XCTAssertFalse(lock.allows(url(.instagram, "/direct/inbox/")))
        XCTAssertFalse(lock.allows(url(.instagram, "/explore/")))
        // Another site (a sign-in hop) is left to WebKit's own limits.
        XCTAssertTrue(lock.allows(URL(string: "https://www.facebook.com/login/")!))
    }

    func testMessagesLockAllowsNothingButMessages() throws {
        for app in SocialApp.allCases {
            guard let purpose = app.purpose(id: "messages") else { continue }
            let lock = try XCTUnwrap(WrapperLock(app: app, purpose: purpose))
            XCTAssertTrue(lock.allows(app.startURL(for: purpose)!), "\(app)")
            XCTAssertFalse(lock.allows(url(app, "/")), "\(app) lets messages-only reach the home feed")
        }
        let instagram = try XCTUnwrap(WrapperLock(app: .instagram, purpose: SocialApp.instagram.purpose(id: "messages")!))
        XCTAssertTrue(instagram.allows(url(.instagram, "/direct/t/12345/")))
        XCTAssertFalse(instagram.allows(url(.instagram, "/reel/Cabc123xyz/")))
        XCTAssertFalse(instagram.allows(url(.instagram, "/someone/")))
    }

    func testShortsLockKeepsYouTubeToShorts() throws {
        let lock = try XCTUnwrap(WrapperLock(app: .youtube, purpose: SocialApp.youtube.purpose(id: "shortVideos")!))
        XCTAssertTrue(lock.allows(url(.youtube, "/shorts/dQw4w9WgXcQ")))
        XCTAssertFalse(lock.allows(url(.youtube, "/watch?v=dQw4w9WgXcQ")))
        XCTAssertFalse(lock.allows(url(.youtube, "/")))
    }

    func testTikTokForYouLockAllowsTheFeedAndVideos() throws {
        let lock = try XCTUnwrap(WrapperLock(app: .tiktok, purpose: SocialApp.tiktok.purpose(id: "shortVideos")!))
        XCTAssertTrue(lock.allows(url(.tiktok, "/")))
        XCTAssertTrue(lock.allows(url(.tiktok, "/foryou")))
        XCTAssertTrue(lock.allows(url(.tiktok, "/@someone/video/7300000000000000000")))
        XCTAssertTrue(lock.allows(url(.tiktok, "/login")))
        XCTAssertFalse(lock.allows(url(.tiktok, "/messages")))
        XCTAssertFalse(lock.allows(url(.tiktok, "/@someone")))
    }

    func testLockScriptCarriesItsRulesAsJSON() throws {
        let lock = try XCTUnwrap(WrapperLock(app: .youtube, purpose: SocialApp.youtube.purpose(id: "shortVideos")!))
        XCTAssertTrue(lock.script.contains("var DOMAIN = \"youtube.com\";"))
        XCTAssertTrue(lock.script.contains("var START = \"\\/shorts\\/\";") || lock.script.contains("var START = \"/shorts/\";"))
    }

    // MARK: - Sections

    func testSectionsFromAddresses() {
        let cases: [(SocialApp, String, AppSection)] = [
            (.instagram, "/", .feed),
            (.instagram, "/reels/", .shortVideo),
            (.instagram, "/reel/Cabc123xyz/", .shortVideo),
            (.instagram, "/direct/inbox/", .messages),
            (.instagram, "/explore/search/", .search),
            (.instagram, "/explore/", .explore),
            (.instagram, "/p/Cabc123xyz/", .post),
            (.instagram, "/some.user_1/", .profile),
            (.instagram, "/accounts/login/", .account),
            (.tiktok, "/foryou", .shortVideo),
            (.tiktok, "/@someone/video/7300000000000000000", .shortVideo),
            (.tiktok, "/@someone", .profile),
            (.tiktok, "/messages", .messages),
            (.youtube, "/", .feed),
            (.youtube, "/shorts/dQw4w9WgXcQ", .shortVideo),
            (.youtube, "/watch?v=dQw4w9WgXcQ", .longVideo),
            (.youtube, "/results?search_query=swift", .search),
            (.youtube, "/@channel", .profile),
            (.snapchat, "/spotlight/abc", .shortVideo),
            (.facebook, "/", .feed),
            (.facebook, "/reel/123", .shortVideo),
            (.facebook, "/marketplace/item/1", .marketplace),
            (.facebook, "/story.php?story_fbid=1", .post),
            (.x, "/home", .feed),
            (.x, "/someone/status/123", .post),
            (.x, "/i/chat", .messages),
            (.x, "/explore", .explore),
            (.reddit, "/", .feed),
            (.reddit, "/r/swift/", .groups),
            (.reddit, "/r/swift/comments/abc/title/", .post),
            (.reddit, "/chat/", .messages),
            (.threads, "/", .feed),
            (.threads, "/@someone/post/abc", .post),
            (.threads, "/@someone", .profile)
        ]
        for (app, path, expected) in cases {
            XCTAssertEqual(app.section(for: url(app, path)), expected, "\(app) \(path)")
        }
    }

    func testPagesOnAnotherSiteCountAsAccount() {
        XCTAssertEqual(SocialApp.instagram.section(for: URL(string: "https://www.facebook.com/login/")!), .account)
        XCTAssertEqual(SocialApp.threads.section(for: URL(string: "https://www.instagram.com/accounts/login/")!), .account)
    }

    // MARK: - Drifting

    func testLongVideosDriftIntoShortsButNotSearchOrSignIn() throws {
        let purpose = try XCTUnwrap(SocialApp.youtube.purpose(id: "longVideos"))
        XCTAssertTrue(purpose.isDrifting(in: .shortVideo))
        XCTAssertFalse(purpose.isDrifting(in: .longVideo))
        XCTAssertFalse(purpose.isDrifting(in: .search))
        XCTAssertFalse(purpose.isDrifting(in: .account))
        XCTAssertFalse(purpose.isDrifting(in: .other))
    }

    func testInstagramFeedDriftsIntoReelsAndExplore() throws {
        let purpose = try XCTUnwrap(SocialApp.instagram.purpose(id: "feed"))
        XCTAssertTrue(purpose.isDrifting(in: .shortVideo))
        XCTAssertTrue(purpose.isDrifting(in: .explore))
        XCTAssertFalse(purpose.isDrifting(in: .messages))
        XCTAssertFalse(purpose.isDrifting(in: .stories))
    }

    // MARK: - Remembered picks

    func testPicksAreRememberedPerAppAndPurpose() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SocialAppsTests"))
        defaults.removePersistentDomain(forName: "SocialAppsTests")
        let longVideos = try XCTUnwrap(SocialApp.youtube.purpose(id: "longVideos"))
        let shorts = try XCTUnwrap(SocialApp.youtube.purpose(id: "shortVideos"))

        XCTAssertNil(AppPickStore.lastPurpose(for: .youtube, defaults: defaults))
        AppPickStore.save(app: .youtube, purpose: shorts, amount: 15, defaults: defaults)
        AppPickStore.save(app: .youtube, purpose: longVideos, amount: 20, defaults: defaults)

        XCTAssertEqual(AppPickStore.lastPurpose(for: .youtube, defaults: defaults)?.id, "longVideos")
        XCTAssertEqual(AppPickStore.lastAmount(for: .youtube, purpose: shorts, defaults: defaults), 15)
        XCTAssertEqual(AppPickStore.lastAmount(for: .youtube, purpose: longVideos, defaults: defaults), 20)
        XCTAssertNil(AppPickStore.lastPurpose(for: .tiktok, defaults: defaults))
    }

    func testInstagramFallsBackToItsOlderPick() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SocialAppsTestsLegacy"))
        defaults.removePersistentDomain(forName: "SocialAppsTestsLegacy")
        WrapperPickStore.save(.reels, amount: 15, defaults: defaults)
        let purpose = try XCTUnwrap(AppPickStore.lastPurpose(for: .instagram, defaults: defaults))
        XCTAssertEqual(purpose.id, "shortVideos")
        XCTAssertEqual(AppPickStore.lastAmount(for: .instagram, purpose: purpose, defaults: defaults), 15)
        XCTAssertNil(AppPickStore.lastAmount(for: .instagram, purpose: SocialApp.instagram.purpose(id: "feed")!, defaults: defaults))
    }

    func testAppPicksAreAskedUntilAnswered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SocialAppsTestsPicks"))
        defaults.removePersistentDomain(forName: "SocialAppsTestsPicks")
        XCTAssertFalse(AppPicksPrompt.isAnswered(defaults: defaults))
        AppPicksPrompt.markAnswered(defaults: defaults)
        XCTAssertTrue(AppPicksPrompt.isAnswered(defaults: defaults))
    }

    // MARK: - Stored sessions

    func testOlderSessionsReadAsInstagramWithNothingTracked() throws {
        let json = """
        {"id":"a","date":"2026-10-30","startedAt":"x","endedAt":"y","scrollCount":4}
        """
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.app, .instagram)
        XCTAssertNil(decoded.purpose)
        XCTAssertEqual(decoded.sectionSeconds, [:])
        XCTAssertEqual(decoded.offPurposeSeconds, 0)
        XCTAssertEqual(decoded.blockedAttempts, 0)
    }

    func testPurposeFieldsSurviveARoundTrip() throws {
        let original = session(app: .youtube, purpose: "longVideos", sections: ["longVideo": 300, "shortVideo": 60],
                               off: 60, reminders: 2, returned: 1, blocked: 0, reason: Intention.relax.rawValue)
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.app, .youtube)
        XCTAssertEqual(decoded.purpose, "longVideos")
        XCTAssertEqual(decoded.reason, "Relax")
        XCTAssertEqual(decoded.sectionSeconds, ["longVideo": 300, "shortVideo": 60])
        XCTAssertEqual(decoded.offPurposeSeconds, 60)
        XCTAssertEqual(decoded.driftReminders, 2)
        XCTAssertEqual(decoded.returnedToPurpose, 1)
    }

    // MARK: - Report

    private func session(
        app: SocialApp,
        purpose: String,
        sections: [String: Int],
        off: Int = 0,
        reminders: Int = 0,
        returned: Int = 0,
        blocked: Int = 0,
        reels: Int = 0,
        reason: String? = nil
    ) -> InstagramWrapperSession {
        InstagramWrapperSession(
            id: UUID().uuidString, date: "2026-11-02",
            startedAt: "2026-11-02T20:00:00Z", endedAt: "2026-11-02T20:10:00Z",
            scrollCount: 0,
            limitKind: purpose == "messages" ? nil : (purpose == "shortVideos" ? "reels" : "minutes"),
            reelCount: reels,
            platform: app.rawValue, purpose: purpose, reason: reason,
            sectionSeconds: sections, offPurposeSeconds: off,
            driftReminders: reminders, returnedToPurpose: returned, blockedAttempts: blocked
        )
    }

    func testReportMeasuresTimeOnPurposeAndNamesTheDrift() {
        let sessions = [
            session(app: .youtube, purpose: "longVideos", sections: ["longVideo": 480, "shortVideo": 120, "account": 30], off: 120, reminders: 2, returned: 1),
            session(app: .youtube, purpose: "longVideos", sections: ["longVideo": 300, "search": 60], off: 0),
            session(app: .instagram, purpose: "messages", sections: ["messages": 200], blocked: 3)
        ]
        let report = AppPurposeReport(sessions: sessions, days: 7)
        XCTAssertEqual(report.sessionCount, 3)
        XCTAssertEqual(report.rows.first?.app, .youtube)
        // 120 off of 1,160 placed seconds (sign-in left out).
        XCTAssertEqual(report.onPurposeShare ?? 0, 1 - 120.0 / 1160.0, accuracy: 0.0001)
        XCTAssertEqual(report.rows.first?.topDrift, .shortVideo)
        XCTAssertEqual(report.rows.first?.usualPurpose?.id, "longVideos")
        XCTAssertEqual(report.findings.first, "On YouTube you came to watch long videos twice, and 13% of that time went to Shorts.")
        XCTAssertTrue(report.findings.contains("Mivo reminded you what you came for twice. You went back once."))
        XCTAssertTrue(report.findings.contains("In messages-only, you tried to leave messages 3 times."))
    }

    // MARK: - The feed runs out

    func testShortVideoIDsFromAddresses() {
        XCTAssertEqual(ShortVideoID.id(in: url(.youtube, "/shorts/dQw4w9WgXcQ"), app: .youtube), "dQw4w9WgXcQ")
        XCTAssertEqual(ShortVideoID.id(in: url(.facebook, "/reel/1234567890123"), app: .facebook), "1234567890123")
        XCTAssertEqual(ShortVideoID.id(in: url(.snapchat, "/spotlight/W7_EDlXWTBiXAEEniNoMPw"), app: .snapchat), "W7_EDlXWTBiXAEEniNoMPw")
        XCTAssertEqual(ShortVideoID.id(in: url(.instagram, "/reel/Cabc123xyz/"), app: .instagram), "Cabc123xyz")
        XCTAssertNil(ShortVideoID.id(in: url(.youtube, "/shorts/"), app: .youtube))
        XCTAssertNil(ShortVideoID.id(in: url(.youtube, "/watch?v=dQw4w9WgXcQ"), app: .youtube))
        XCTAssertNil(ShortVideoID.id(in: url(.facebook, "/reel/abc"), app: .facebook))
        XCTAssertNil(ShortVideoID.id(in: url(.tiktok, "/@someone/video/7300000000000000000"), app: .tiktok))
        // Another site's address never yields an ID.
        XCTAssertNil(ShortVideoID.id(in: URL(string: "https://evil.example/shorts/dQw4w9WgXcQ")!, app: .youtube))
    }

    func testReplayAddressesStayOnEachApp() {
        XCTAssertEqual(ShortVideoID.url(for: "dQw4w9WgXcQ", app: .youtube)?.absoluteString, "https://m.youtube.com/shorts/dQw4w9WgXcQ")
        XCTAssertEqual(ShortVideoID.url(for: "1234567890123", app: .facebook)?.absoluteString, "https://m.facebook.com/reel/1234567890123")
        XCTAssertNil(ShortVideoID.url(for: "../../etc", app: .youtube))
        XCTAssertNil(ShortVideoID.url(for: "dQw4w9WgXcQ", app: .tiktok))
        for app in SocialApp.allCases where ShortVideoID.supportsReplay(app) {
            let sample = app == .facebook ? "1234567890123" : (app == .snapchat ? "W7_EDlXWTBiXAEEniNoMPw" : "dQw4w9WgXcQ")
            guard let replay = ShortVideoID.url(for: sample, app: app) else { return XCTFail("\(app)") }
            XCTAssertTrue(app.owns(host: replay.host), "\(app)")
            // A replay must be reachable inside the counted purpose's lock.
            if let purpose = app.purpose(id: "shortVideos"), let lock = WrapperLock(app: app, purpose: purpose) {
                XCTAssertTrue(lock.allows(replay), "\(app) locks out its own replays")
            }
        }
    }

    func testEachAppKeepsItsOwnSeenLog() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SocialAppsTestsSeen"))
        defaults.removePersistentDomain(forName: "SocialAppsTestsSeen")
        let youtube = SeenReelStore(defaults: defaults, key: "\(SeenReelStore.defaultsKey).youtube")
        var log = SeenReelLog()
        log.record("dQw4w9WgXcQ", at: Date())
        youtube.save(log)
        XCTAssertEqual(youtube.load().count, 1)
        XCTAssertEqual(SeenReelStore(defaults: defaults).load().count, 0)
        XCTAssertTrue(SeenReelStore.forApp(.instagram) === SeenReelStore.shared)
    }

    // MARK: - Studying, then a social app

    func testOpeningAnAppWhileOrJustAfterStudyingIsAnEscape() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let running = StudyEscape.detect(runningTask: "Chemistry", lastEnded: nil, now: now)
        XCTAssertEqual(running?.midSession, true)
        XCTAssertEqual(running?.headline, "You're in the middle of Chemistry.")

        let recent = StudyEscape.detect(runningTask: nil, lastEnded: ("Chemistry", now.addingTimeInterval(-4 * 60 - 10)), now: now)
        XCTAssertEqual(recent?.minutesAgo, 4)
        XCTAssertEqual(recent?.headline, "You left Chemistry 4 minutes ago.")

        XCTAssertNil(StudyEscape.detect(runningTask: nil, lastEnded: ("Chemistry", now.addingTimeInterval(-11 * 60)), now: now))
        XCTAssertNil(StudyEscape.detect(runningTask: nil, lastEnded: ("Chemistry", now.addingTimeInterval(60)), now: now))
        XCTAssertNil(StudyEscape.detect(runningTask: nil, lastEnded: nil, now: now))
    }

    // MARK: - Feelings, escapes and kept sessions

    private func felt(_ feeling: SessionFeeling, app: SocialApp = .tiktok, purpose: String = "shortVideos",
                      at time: String = "2026-11-02T23:30:00Z") -> InstagramWrapperSession {
        InstagramWrapperSession(
            id: UUID().uuidString, date: "2026-11-02", startedAt: time, endedAt: time,
            scrollCount: 0, limitKind: "reels", reelCount: 5,
            platform: app.rawValue, purpose: purpose, sectionSeconds: ["shortVideo": 120],
            feeling: feeling.rawValue
        )
    }

    func testReportNamesWhatLeavesYouWorseAndBetter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let night = "2026-11-02T23:30:00Z", day = "2026-11-02T14:00:00Z"
        XCTAssertTrue(AppPurposeReport.isLateNight(felt(.worse, at: night), calendar: calendar))
        XCTAssertFalse(AppPurposeReport.isLateNight(felt(.worse, at: day), calendar: calendar))

        let sessions = [felt(.worse), felt(.worse), felt(.worse), felt(.same),
                        felt(.better, app: .youtube, purpose: "longVideos", at: day),
                        felt(.better, app: .youtube, purpose: "longVideos", at: day),
                        felt(.better, app: .youtube, purpose: "longVideos", at: day)]
        let report = AppPurposeReport(sessions: sessions, days: 7)
        XCTAssertEqual(report.answeredFeelings, 7)
        XCTAssertEqual(report.feelingShare(.better) ?? 0, 3.0 / 7.0, accuracy: 0.0001)
        let lateNight = AppPurposeReport.isLateNight(felt(.worse))
        XCTAssertTrue(report.findings.contains("For You videos on TikTok\(lateNight ? " after 10 pm" : "") left you feeling worse 3 of 4 times. Try leaving it out this week."))
        XCTAssertTrue(report.findings.contains { $0.hasPrefix("Long videos on YouTube") && $0.contains("better 3 of 3") })
    }

    func testReportCountsEscapesFromStudying() {
        let sessions = [
            InstagramWrapperSession(id: "a", date: "2026-11-02", startedAt: "x", endedAt: "y", scrollCount: 0,
                                    platform: "instagram", purpose: "shortVideos", afterStudyMinutes: 3, returnedToStudy: true),
            InstagramWrapperSession(id: "b", date: "2026-11-02", startedAt: "x", endedAt: "y", scrollCount: 0,
                                    platform: "youtube", purpose: "shortVideos", afterStudyMinutes: 0),
            InstagramWrapperSession(id: "c", date: "2026-11-02", startedAt: "x", endedAt: "y", scrollCount: 0,
                                    platform: "youtube", purpose: "shortVideos")
        ]
        let report = AppPurposeReport(sessions: sessions, days: 7)
        XCTAssertEqual(report.escapes, 2)
        XCTAssertEqual(report.returnedToStudy, 1)
        XCTAssertTrue(report.findings.contains("You opened a social app straight from studying twice, and went back to it once."))
    }

    func testKeptMeansOnPurposeAndStoppedAtThePick() {
        let kept = session(app: .youtube, purpose: "longVideos", sections: ["longVideo": 600], off: 0)
        let drifted = session(app: .youtube, purpose: "longVideos", sections: ["longVideo": 300, "shortVideo": 300], off: 300)
        let wentPast = InstagramWrapperSession(
            id: "p", date: "2026-11-02", startedAt: "x", endedAt: "y", scrollCount: 0,
            limitKind: "reels", reelCount: 14, reelsAfterSlowdown: 4, slowDownCause: "pick",
            platform: "instagram", purpose: "shortVideos", sectionSeconds: ["shortVideo": 400]
        )
        let messages = session(app: .instagram, purpose: "messages", sections: ["messages": 600])
        let report = AppPurposeReport(sessions: [kept, drifted, wentPast, messages], days: 7)
        XCTAssertEqual(report.keptCandidates, 3)
        XCTAssertEqual(report.keptSessions, 1)
    }

    func testFeelingAndStudyFieldsRoundTrip() throws {
        let original = InstagramWrapperSession(id: "r", date: "2026-11-02", startedAt: "x", endedAt: "y", scrollCount: 0,
                                               feeling: "worse", afterStudyMinutes: 2, returnedToStudy: true)
        let decoded = try JSONDecoder().decode(InstagramWrapperSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.feeling, "worse")
        XCTAssertEqual(decoded.afterStudyMinutes, 2)
        XCTAssertTrue(decoded.returnedToStudy)
        let old = try JSONDecoder().decode(InstagramWrapperSession.self, from: Data(#"{"id":"a","date":"d","startedAt":"x","endedAt":"y","scrollCount":1}"#.utf8))
        XCTAssertNil(old.feeling)
        XCTAssertNil(old.afterStudyMinutes)
        XCTAssertFalse(old.returnedToStudy)
    }

    func testReportWithoutEnoughTimeMakesNoShare() {
        let report = AppPurposeReport(sessions: [session(app: .tiktok, purpose: "messages", sections: ["messages": 40])], days: 7)
        XCTAssertNil(report.onPurposeShare)
        XCTAssertTrue(report.hasData)
        XCTAssertTrue(report.findings.isEmpty)
    }
}
