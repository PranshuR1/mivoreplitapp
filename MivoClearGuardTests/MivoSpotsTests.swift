import XCTest
@testable import Mivo

// MARK: - Links

/// The identification layer: a Spot ID in a link, nothing else.
final class SpotLinkTests: XCTestCase {
    private let id = "3f2a9c1e-7b4d-4e0a-9d3c-1a2b3c4d5e6f"

    func testUniversalLinkRoundTrips() {
        let url = SpotLink.universalURL(for: id)
        XCTAssertEqual(url.absoluteString, "https://usemivo.app/spot/\(id)")
        XCTAssertEqual(SpotLink.spotID(from: url), id)
    }

    func testCustomSchemeRoundTrips() {
        let url = SpotLink.customSchemeURL(for: id)
        XCTAssertEqual(url.absoluteString, "mivo://spot/\(id)")
        XCTAssertEqual(SpotLink.spotID(from: url), id)
    }

    func testIDIsLowercasedSoACaseSensitivePathStillMatches() {
        let url = URL(string: "https://usemivo.app/spot/\(id.uppercased())")!
        XCTAssertEqual(SpotLink.spotID(from: url), id)
    }

    func testOtherHostsSchemesAndShapesAreRejected() {
        let rejected = [
            "https://example.com/spot/\(id)",
            "http://usemivo.app/spot/\(id)",
            "https://usemivo.app/r/\(id)",
            "https://usemivo.app/spot/\(id)/extra",
            "https://usemivo.app/spot",
            "mivo://clear/\(id)",
            "mivo://spot/\(id)/extra",
            "mivo://spot"
        ]
        for string in rejected {
            XCTAssertNil(SpotLink.spotID(from: URL(string: string)!), string)
        }
    }

    func testIDMustLookLikeALookupKey() {
        XCTAssertTrue(SpotLink.isValidSpotID(id))
        XCTAssertFalse(SpotLink.isValidSpotID("short"))
        XCTAssertFalse(SpotLink.isValidSpotID(String(repeating: "a", count: 65)))
        XCTAssertFalse(SpotLink.isValidSpotID("has spaces in it!"))
        XCTAssertFalse(SpotLink.isValidSpotID("../../etc/passwd"))
    }

    func testNewSpotIDsAreValidLinkIDs() {
        for _ in 0..<20 {
            XCTAssertTrue(SpotLink.isValidSpotID(MivoSpot.makeID()))
        }
    }
}

// MARK: - Usage ladder and live state

final class SpotSharedTests: XCTestCase {
    func testEventNamesRoundTrip() {
        let all = SpotUsageLadder.eventName(scope: .all, minutes: 10)
        XCTAssertEqual(SpotUsageLadder.parse(eventName: all)?.scope, .all)
        XCTAssertEqual(SpotUsageLadder.parse(eventName: all)?.minutes, 10)

        let app = SpotUsageLadder.eventName(scope: .app(2), minutes: 25)
        XCTAssertEqual(SpotUsageLadder.parse(eventName: app)?.scope, .app(2))
        XCTAssertEqual(SpotUsageLadder.parse(eventName: app)?.minutes, 25)
    }

    func testForeignOrMalformedEventNamesAreIgnored() {
        for name in ["", "mivo.session.usageLimit", "mivo.spot.u.all", "mivo.spot.u.all.m0", "mivo.spot.u.x9.m5", "mivo.spot.u.a-1.m5"] {
            XCTAssertNil(SpotUsageLadder.parse(eventName: name), name)
        }
    }

    func testTallyKeepsTheHighestThresholdReached() {
        var tally: [String: Int] = [:]
        SpotUsageLadder.record(eventName: SpotUsageLadder.eventName(scope: .all, minutes: 10), into: &tally)
        SpotUsageLadder.record(eventName: SpotUsageLadder.eventName(scope: .all, minutes: 5), into: &tally)
        SpotUsageLadder.record(eventName: SpotUsageLadder.eventName(scope: .app(0), minutes: 3), into: &tally)
        SpotUsageLadder.record(eventName: "not.ours", into: &tally)
        XCTAssertEqual(SpotUsageLadder.minutes(for: .all, in: tally), 10)
        XCTAssertEqual(SpotUsageLadder.minutes(for: .app(0), in: tally), 3)
        XCTAssertEqual(SpotUsageLadder.minutes(for: .app(1), in: tally), 0)
    }

    func testEveryPerAppThresholdIsAlsoAWholeSpotThreshold() {
        // A single app can never read higher than the Spot total, because every
        // per-app step has a matching step on the total.
        XCTAssertTrue(Set(SpotUsageLadder.appMinutes).isSubset(of: Set(SpotUsageLadder.allMinutes)))
    }

    func testEventBudgetStaysSmall() {
        XCTAssertEqual(SpotUsageLadder.eventCount(trackedApps: 0), SpotUsageLadder.allMinutes.count)
        XCTAssertEqual(
            SpotUsageLadder.eventCount(trackedApps: 99),
            SpotUsageLadder.allMinutes.count + SpotUsageLadder.maxTrackedApps * SpotUsageLadder.appMinutes.count
        )
        XCTAssertLessThanOrEqual(SpotUsageLadder.eventCount(trackedApps: 99), 64)
    }

    // MARK: Live state

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "mivo.spots.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func writeLive(_ defaults: UserDefaults, mode: SpotMode, endsAt: Date, liftedUntil: Date? = nil, intentionDone: Bool = false) {
        defaults.set(true, forKey: SpotKeys.liveActive)
        defaults.set("session-1", forKey: SpotKeys.liveSessionID)
        defaults.set("spot-aaaa-1111", forKey: SpotKeys.liveSpotID)
        defaults.set("Study Desk", forKey: SpotKeys.liveName)
        defaults.set(mode.rawValue, forKey: SpotKeys.liveMode)
        defaults.set(endsAt.timeIntervalSince1970, forKey: SpotKeys.liveEndsAt)
        if let liftedUntil { defaults.set(liftedUntil.timeIntervalSince1970, forKey: SpotKeys.liveShieldLiftedUntil) }
        defaults.set(intentionDone, forKey: SpotKeys.liveIntentionDone)
    }

    func testLiveStateReadsWhatTheAppWrote() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        writeLive(defaults, mode: .focus, endsAt: now.addingTimeInterval(600))

        let live = SpotLiveState.read(from: defaults, now: now)
        XCTAssertEqual(live?.name, "Study Desk")
        XCTAssertEqual(live?.mode, .focus)
        XCTAssertEqual(live?.wantsShield(at: now), true)
    }

    func testAnEndedSpotReadsAsNothingEvenIfTheFlagWasNeverCleared() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        writeLive(defaults, mode: .focus, endsAt: now.addingTimeInterval(-1))
        XCTAssertNil(SpotLiveState.read(from: defaults, now: now))

        defaults.set(false, forKey: SpotKeys.liveActive)
        writeLive(defaults, mode: .focus, endsAt: now.addingTimeInterval(600))
        defaults.set(false, forKey: SpotKeys.liveActive)
        XCTAssertNil(SpotLiveState.read(from: defaults, now: now))
    }

    func testShieldRulesPerMode() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let later = now.addingTimeInterval(3600)

        writeLive(defaults, mode: .awareness, endsAt: later)
        XCTAssertEqual(SpotLiveState.read(from: defaults, now: now)?.wantsShield(at: now), false)

        writeLive(defaults, mode: .pause, endsAt: later)
        XCTAssertEqual(SpotLiveState.read(from: defaults, now: now)?.wantsShield(at: now), true)

        // A pause the person chose to continue past lifts the shield until it ends.
        writeLive(defaults, mode: .pause, endsAt: later, liftedUntil: now.addingTimeInterval(300))
        let lifted = SpotLiveState.read(from: defaults, now: now)
        XCTAssertEqual(lifted?.wantsShield(at: now), false)
        XCTAssertEqual(lifted?.wantsShield(at: now.addingTimeInterval(301)), true)

        // An answered intention check lifts it for the rest of the Spot.
        defaults.removeObject(forKey: SpotKeys.liveShieldLiftedUntil)
        writeLive(defaults, mode: .intention, endsAt: later, intentionDone: false)
        XCTAssertEqual(SpotLiveState.read(from: defaults, now: now)?.wantsShield(at: now), true)
        writeLive(defaults, mode: .intention, endsAt: later, intentionDone: true)
        XCTAssertEqual(SpotLiveState.read(from: defaults, now: now)?.wantsShield(at: now), false)
    }

    func testOnlyShieldModesUseAShield() {
        XCTAssertEqual(SpotMode.allCases.filter(\.usesShield), [.pause, .focus, .intention])
    }
}

// MARK: - Insights

final class SpotInsightsTests: XCTestCase {
    private let spotID = "spot-aaaa-1111"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func finished(
        spot: String = "spot-aaaa-1111",
        name: String = "Study Desk",
        minutes: Double,
        distracting: Int?,
        daysAgo: Int = 1
    ) -> SpotSession {
        let begin = start.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        let end = begin.addingTimeInterval(minutes * 60)
        return SpotSession(
            id: UUID().uuidString, spotID: spot, spotName: name, spotIcon: "sf:books.vertical",
            mode: .focus, startDate: begin, plannedEndDate: end, isOpenEnded: false,
            endDate: end, completionReason: .timerCompleted, trigger: .link, trackedApps: [],
            usageTracked: distracting != nil,
            usage: distracting.map { SpotUsageRecord(totalMinutes: $0, perApp: []) },
            intention: nil, pausesContinued: 0, summarySeen: true
        )
    }

    private func history(count: Int = 3, minutes: Double = 60, distracting: Int = 30) -> [SpotSession] {
        (1...count).map { finished(minutes: minutes, distracting: distracting, daysAgo: $0 + 1) }
    }

    // MARK: Stats

    func testStatsCountOnlyRealSessions() {
        let sessions = [
            finished(minutes: 60, distracting: 12),
            finished(minutes: 30, distracting: nil),
            finished(minutes: 0.3, distracting: 0) // a 20-second accidental tap
        ]
        let stats = SpotInsights.stats(for: sessions, spotID: spotID)
        XCTAssertEqual(stats.sessionCount, 2)
        XCTAssertEqual(stats.totalActiveMinutes, 90)
        XCTAssertEqual(stats.averageSessionMinutes, 45)
        XCTAssertEqual(stats.measuredSessionCount, 1)
        XCTAssertEqual(stats.measuredDistractingMinutes, 12)
    }

    func testStatsForNothingAreEmptyNotInvented() {
        XCTAssertEqual(SpotInsights.stats(for: []), .empty)
        XCTAssertNil(SpotInsights.overall(for: []).mostUsedSpotID)
    }

    func testMostUsedSpotAndTieBreak() {
        let a = [finished(spot: "spot-aaaa-1111", name: "Desk", minutes: 20, distracting: nil),
                 finished(spot: "spot-aaaa-1111", name: "Desk", minutes: 20, distracting: nil)]
        let b = [finished(spot: "spot-bbbb-2222", name: "Bedside", minutes: 90, distracting: nil)]
        XCTAssertEqual(SpotInsights.overall(for: a + b).mostUsedSpotName, "Desk")

        // Equal counts: the Spot with more time wins.
        let c = [finished(spot: "spot-bbbb-2222", name: "Bedside", minutes: 90, distracting: nil),
                 finished(spot: "spot-bbbb-2222", name: "Bedside", minutes: 90, distracting: nil)]
        XCTAssertEqual(SpotInsights.overall(for: a + c).mostUsedSpotName, "Bedside")
    }

    // MARK: Comparison

    func testLessThanUsualMatchesTheDocumentedExample() {
        let current = finished(minutes: 60, distracting: 9, daysAgo: 0)
        let comparison = SpotInsights.comparison(for: current, history: history() + [current])
        XCTAssertEqual(comparison, .lessThanUsual(minutes: 21))
        XCTAssertEqual(
            SpotInsights.comparisonText(comparison, spotName: "Study Desk"),
            "21 min less distracting screen time than your usual Study Desk sessions."
        )
    }

    func testComparisonComparesRatesNotTotals() {
        // 30 min of distraction in 60 is the usual rate; doing 120 minutes with
        // 60 of it is the same rate, not "30 minutes worse".
        let current = finished(minutes: 120, distracting: 60, daysAgo: 0)
        XCTAssertEqual(SpotInsights.comparison(for: current, history: history()), .similarToUsual)
    }

    func testMoreThanUsualIsReportedGently() {
        let current = finished(minutes: 60, distracting: 45, daysAgo: 0)
        let comparison = SpotInsights.comparison(for: current, history: history())
        XCTAssertEqual(comparison, .moreThanUsual(minutes: 15))
        let text = SpotInsights.comparisonText(comparison, spotName: "Study Desk") ?? ""
        XCTAssertFalse(text.lowercased().contains("fail"))
        XCTAssertTrue(text.contains("15 min more"))
    }

    func testNoComparisonWithoutEnoughHistory() {
        let current = finished(minutes: 60, distracting: 9, daysAgo: 0)
        XCTAssertEqual(SpotInsights.comparison(for: current, history: history(count: 2)), .notEnoughData)
        XCTAssertEqual(SpotInsights.comparison(for: current, history: []), .notEnoughData)
        XCTAssertNil(SpotInsights.comparisonText(.notEnoughData, spotName: "Study Desk"))
    }

    func testNoComparisonForOtherSpotsUnmeasuredOrShortSessions() {
        let current = finished(minutes: 60, distracting: 9, daysAgo: 0)

        let otherSpot = (1...5).map { finished(spot: "spot-bbbb-2222", minutes: 60, distracting: 30, daysAgo: $0 + 1) }
        XCTAssertEqual(SpotInsights.comparison(for: current, history: otherSpot), .notEnoughData)

        let unmeasured = (1...5).map { finished(minutes: 60, distracting: nil, daysAgo: $0 + 1) }
        XCTAssertEqual(SpotInsights.comparison(for: current, history: unmeasured), .notEnoughData)

        let brief = (1...5).map { finished(minutes: 5, distracting: 2, daysAgo: $0 + 1) }
        XCTAssertEqual(SpotInsights.comparison(for: current, history: brief), .notEnoughData)

        let shortCurrent = finished(minutes: 5, distracting: 0, daysAgo: 0)
        XCTAssertEqual(SpotInsights.comparison(for: shortCurrent, history: history()), .notEnoughData)

        let unmeasuredCurrent = finished(minutes: 60, distracting: nil, daysAgo: 0)
        XCTAssertEqual(SpotInsights.comparison(for: unmeasuredCurrent, history: history()), .notEnoughData)
    }

    func testSummaryReportsUnmeasuredUsageAsNilNeverZero() {
        let session = finished(minutes: 45, distracting: nil, daysAgo: 0)
        let summary = SpotInsights.summary(for: session, history: [])
        XCTAssertEqual(summary.activeMinutes, 45)
        XCTAssertNil(summary.distractingMinutes)
    }

    func testSummarySortsAppsByTimeAndDropsEmptyOnes() {
        var session = finished(minutes: 72, distracting: 21, daysAgo: 0)
        session.usage = SpotUsageRecord(totalMinutes: 21, perApp: [
            SpotAppUsage(index: 0, name: "Instagram", tokenData: nil, minutes: 8),
            SpotAppUsage(index: 1, name: "TikTok", tokenData: nil, minutes: 0),
            SpotAppUsage(index: 2, name: "YouTube", tokenData: nil, minutes: 12)
        ])
        let summary = SpotInsights.summary(for: session, history: [])
        XCTAssertEqual(summary.perApp.map(\.name), ["YouTube", "Instagram"])
        XCTAssertEqual(SpotFormat.compact(minutes: summary.activeMinutes), "1h 12m")
    }
}

// MARK: - Model and persistence

final class SpotModelTests: XCTestCase {
    func testSpotSurvivesEncodingIncludingItsTag() throws {
        var spot = MivoSpot(name: "Gym", icon: SpotIcon.symbol("dumbbell"), mode: .focus, defaultDurationMinutes: 25)
        spot.tag = SpotTagBinding(carrier: .ndefTag, identifier: "04a1b2c3d4e5f6", connectedAt: Date(timeIntervalSince1970: 1_800_000_000), lastScannedAt: nil)
        let decoded = try JSONDecoder().decode(MivoSpot.self, from: JSONEncoder().encode(spot))
        XCTAssertEqual(decoded, spot)
        XCTAssertEqual(decoded.nfcIdentifier, "04a1b2c3d4e5f6")
        XCTAssertEqual(decoded.link, SpotLink.universalURL(for: spot.id))
    }

    func testAppSelectionSummary() {
        XCTAssertEqual(SpotAppSelection.empty.summary, "No apps yet")
        let named = SpotAppSelection(data: nil, appNames: ["Instagram", "TikTok", "YouTube"], applicationCount: 3, categoryCount: 0, webDomainCount: 0)
        XCTAssertEqual(named.summary, "Instagram, TikTok, YouTube")
        let many = SpotAppSelection(data: nil, appNames: ["A", "B", "C", "D", "E"], applicationCount: 5, categoryCount: 0, webDomainCount: 0)
        XCTAssertEqual(many.summary, "A, B, C +2")
        // Apple doesn't always hand over a name: fall back to counts, never guess one.
        let unnamed = SpotAppSelection(data: nil, appNames: ["Instagram"], applicationCount: 3, categoryCount: 1, webDomainCount: 0)
        XCTAssertEqual(unnamed.summary, "3 apps · 1 category")
    }

    func testIconKinds() {
        XCTAssertEqual(SpotIcon.kind(of: "sf:car"), .symbol("car"))
        XCTAssertEqual(SpotIcon.kind(of: "🌙"), .emoji("🌙"))
        XCTAssertEqual(SpotIcon.emoji(from: "  🌙🌙 "), "🌙")
        XCTAssertEqual(SpotIcon.emoji(from: "  "), SpotIcon.defaultIcon)
    }

    func testTemplatesAreUniqueRealAndEndWithCustom() {
        let templates = SpotTemplate.all
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        XCTAssertEqual(templates.last?.id, "custom")
        XCTAssertEqual(templates.count % 2, 0, "the picker is a two-column grid")
        for template in templates where !template.isCustom {
            XCTAssertFalse(template.name.isEmpty)
            guard case .symbol(let name) = SpotIcon.kind(of: template.icon) else {
                XCTFail("\(template.id) should use a symbol"); continue
            }
            XCTAssertNotNil(UIImage(systemName: name), "\(name) is not an SF Symbol")
            XCTAssertTrue(SpotIconChoices.symbols.contains(name), "\(name) is missing from the icon picker")
        }
    }

    func testDurationLabels() {
        XCTAssertEqual(MivoSpot(name: "A", defaultDurationMinutes: 25).durationLabel, "25 min")
        XCTAssertEqual(MivoSpot(name: "A", defaultDurationMinutes: 60).durationLabel, "1 hr")
        XCTAssertEqual(MivoSpot(name: "A", defaultDurationMinutes: 90).durationLabel, "1 hr 30 min")
        XCTAssertEqual(MivoSpot(name: "A", defaultDurationMinutes: nil).durationLabel, "Until I end it")
    }

    func testStoragePersistenceIsPerAccountAndErasable() {
        let email = "spots-test-\(UUID().uuidString)@example.com"
        let other = "spots-other-\(UUID().uuidString)@example.com"
        defer {
            StorageService.removeUserScopedMivoData(email: email)
            StorageService.removeUserScopedMivoData(email: other)
        }
        let store = StorageSpotPersistence(accountEmail: email)
        let spot = MivoSpot(name: "Kitchen")
        store.saveSpots([spot])
        XCTAssertEqual(store.loadSpots(), [spot])
        XCTAssertTrue(StorageSpotPersistence(accountEmail: other).loadSpots().isEmpty)

        store.erase()
        XCTAssertTrue(store.loadSpots().isEmpty)
        XCTAssertNil(store.loadActiveSession())
    }
}

// MARK: - Manager

@MainActor
final class SpotManagerTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var clock = TestClock()
    private var persistence = InMemorySpotPersistence()
    private var screenTime = NoopSpotScreenTime()

    override func setUp() {
        super.setUp()
        clock = TestClock()
        persistence = InMemorySpotPersistence()
        screenTime = NoopSpotScreenTime()
    }

    private func makeManager() -> SpotManager {
        let manager = SpotManager(persistence: persistence, screenTime: screenTime, clock: { [clock] in clock.now })
        manager.setAccount("tester@example.com")
        return manager
    }

    @discardableResult
    private func addSpot(
        _ manager: SpotManager,
        name: String = "Study Desk",
        mode: SpotMode = .focus,
        minutes: Int? = 60
    ) -> MivoSpot {
        let spot = MivoSpot(name: name, mode: mode, defaultDurationMinutes: minutes)
        guard case .success(let saved) = manager.save(spot) else {
            XCTFail("could not save spot")
            return spot
        }
        return saved
    }

    // MARK: Starting

    func testActivatingStartsASessionWithItsTimerAndConfirmation() {
        let manager = makeManager()
        let spot = addSpot(manager)

        let outcome = manager.activate(spotID: spot.id, trigger: .manual)

        guard case .started = outcome else { return XCTFail("expected started, got \(outcome)") }
        XCTAssertEqual(manager.activeSession?.plannedEndDate, clock.now.addingTimeInterval(3600))
        XCTAssertEqual(manager.notice?.title, "Study Desk activated")
        XCTAssertEqual(manager.notice?.message, "Focus for the next hour.")
        XCTAssertEqual(screenTime.started.count, 1)
        XCTAssertNotNil(persistence.loadActiveSession())
    }

    func testConfirmationCopyPerMode() {
        XCTAssertEqual(SpotCopy.activationMessage(mode: .focus, durationMinutes: 25), "Focus for the next 25 min.")
        XCTAssertEqual(SpotCopy.activationMessage(mode: .focus, durationMinutes: nil), "Focus until you end it.")
        XCTAssertEqual(SpotCopy.activationMessage(mode: .pause, durationMinutes: 60), "Mivo will pause you before these apps.")
        XCTAssertEqual(SpotCopy.activationMessage(mode: .intention, durationMinutes: 60), "Mivo will ask what you came to do, once.")
        XCTAssertEqual(SpotCopy.activationMessage(mode: .awareness, durationMinutes: 60), "Mivo will quietly note your time in these apps.")
    }

    func testUnknownAndDisabledSpotsDoNotStart() {
        let manager = makeManager()
        XCTAssertEqual(manager.handleScan(spotID: "spot-zzzz-9999", trigger: .link), .notFound)
        XCTAssertNotNil(manager.notice)
        XCTAssertNil(manager.activeSession)

        let spot = addSpot(manager)
        manager.setEnabled(false, spotID: spot.id)
        XCTAssertEqual(manager.handleScan(spotID: spot.id, trigger: .link), .disabled)
        XCTAssertNil(manager.activeSession)
    }

    func testOpenEndedSpotCarriesASafetyLimit() {
        let manager = makeManager()
        let spot = addSpot(manager, minutes: nil)
        manager.activate(spotID: spot.id, trigger: .manual)
        let session = manager.activeSession
        XCTAssertEqual(session?.isOpenEnded, true)
        XCTAssertEqual(session?.plannedEndDate, clock.now.addingTimeInterval(TimeInterval(SpotKeys.openEndedCapHours * 3600)))
    }

    // MARK: Ending

    func testTappingTheTagAgainEndsTheSpot() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.handleScan(spotID: spot.id, trigger: .link)
        clock.advance(20 * 60)

        let outcome = manager.handleScan(spotID: spot.id, trigger: .link)

        guard case .ended = outcome else { return XCTFail("expected ended, got \(outcome)") }
        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.first?.completionReason, .endedByTag)
        XCTAssertEqual(screenTime.finished.count, 1)
        XCTAssertNil(persistence.loadActiveSession())
        XCTAssertNotNil(manager.summaryToShow)
    }

    func testTheSameTapDeliveredTwiceDoesNotStartThenEndTheSpot() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.handleScan(spotID: spot.id, trigger: .link)
        clock.advance(1.5)

        XCTAssertEqual(manager.handleScan(spotID: spot.id, trigger: .link), .ignoredDuplicate)
        XCTAssertNotNil(manager.activeSession)
    }

    func testTimerCompletionEndsTheSpotOnReconcile() {
        let manager = makeManager()
        let spot = addSpot(manager, minutes: 25)
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(26 * 60)

        manager.reconcile()

        XCTAssertNil(manager.activeSession)
        let finished = manager.sessions.first
        XCTAssertEqual(finished?.completionReason, .timerCompleted)
        XCTAssertEqual(finished?.endDate, finished?.plannedEndDate, "ends when the timer did, not when Mivo noticed")
        XCTAssertEqual(manager.summaryToShow?.activeMinutes, 25)
    }

    func testOpenEndedSpotExpiresAtItsLimit() {
        let manager = makeManager()
        let spot = addSpot(manager, minutes: nil)
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(TimeInterval(SpotKeys.openEndedCapHours * 3600 + 60))

        manager.reconcile()

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.first?.completionReason, .expired)
    }

    func testSpotEndedByTheExtensionIsFinishedWhenMivoOpens() {
        let manager = makeManager()
        let spot = addSpot(manager, minutes: 25)
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(10 * 60)
        _ = screenTime.finish(session: manager.activeSession!) // the live state is gone, as after an extension teardown

        manager.reconcile()

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.count, 1)
    }

    func testStartingAnotherSpotEndsTheFirst() {
        let manager = makeManager()
        let desk = addSpot(manager, name: "Study Desk")
        let bed = addSpot(manager, name: "Bedside", mode: .pause)
        manager.activate(spotID: desk.id, trigger: .manual)
        clock.advance(120)

        manager.activate(spotID: bed.id, trigger: .manual)

        XCTAssertEqual(manager.activeSession?.spotID, bed.id)
        XCTAssertEqual(manager.sessions.first?.completionReason, .replaced)
        XCTAssertEqual(manager.sessions.first?.spotName, "Study Desk")
    }

    func testDeletingOrSwitchingOffARunningSpotEndsIt() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.activate(spotID: spot.id, trigger: .manual)
        manager.setEnabled(false, spotID: spot.id)
        XCTAssertNil(manager.activeSession)

        manager.setEnabled(true, spotID: spot.id)
        manager.activate(spotID: spot.id, trigger: .manual)
        manager.delete(spotID: spot.id)
        XCTAssertNil(manager.activeSession)
        XCTAssertTrue(manager.spots.isEmpty)
        XCTAssertNil(manager.summaryToShow, "a removed Spot has no summary to show")
    }

    func testHistoryKeepsTheSpotNameAfterARename() {
        let manager = makeManager()
        var spot = addSpot(manager, name: "Desk")
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(600)
        manager.end(reason: .endedManually)
        spot.name = "Library"
        manager.save(spot)
        XCTAssertEqual(manager.sessions.first?.spotName, "Desk")
    }

    // MARK: Summary

    func testAnAccidentalTapLeavesNoSummary() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.handleScan(spotID: spot.id, trigger: .link)
        clock.advance(10)
        manager.end(reason: .endedManually)
        XCTAssertNil(manager.summaryToShow)
        XCTAssertTrue(SpotInsights.counted(manager.sessions).isEmpty)
    }

    func testAnUnseenSummaryComesBackOnceAfterARelaunch() {
        let first = makeManager()
        let spot = addSpot(first)
        first.activate(spotID: spot.id, trigger: .manual)
        clock.advance(30 * 60)
        first.end(reason: .endedManually)
        XCTAssertNotNil(first.summaryToShow)

        // Relaunch without ever dismissing it.
        let second = makeManager()
        XCTAssertEqual(second.summaryToShow?.spotName, "Study Desk")
        second.dismissSummary()
        XCTAssertNil(second.summaryToShow)

        let third = makeManager()
        XCTAssertNil(third.summaryToShow)
    }

    // MARK: Saving

    func testSavingValidatesTrimsAndCapsSpots() {
        let manager = makeManager()
        XCTAssertEqual(manager.save(MivoSpot(name: "   ")), .failure(.emptyName))

        let long = MivoSpot(name: "  " + String(repeating: "x", count: 60) + "  ")
        guard case .success(let saved) = manager.save(long) else { return XCTFail("expected success") }
        XCTAssertEqual(saved.name.count, SpotManager.maxNameLength)

        for index in 1..<SpotManager.maxSpots { addSpot(manager, name: "Spot \(index)") }
        XCTAssertEqual(manager.spots.count, SpotManager.maxSpots)
        XCTAssertEqual(manager.save(MivoSpot(name: "One too many")), .failure(.tooManySpots))
    }

    func testSpotsAndTagsPersistAcrossLaunches() {
        let first = makeManager()
        var car = MivoSpot(name: "Car", mode: .awareness)
        car.tag = SpotTagBinding(carrier: .ndefTag, identifier: "04aabbcc", connectedAt: clock.now, lastScannedAt: nil)
        guard case .success(let spot) = first.save(car) else { return XCTFail("could not save spot") }

        let second = makeManager()
        XCTAssertEqual(second.spots.map(\.name), ["Car"])
        XCTAssertEqual(second.spot(id: spot.id)?.nfcIdentifier, "04aabbcc")

        second.disconnectTag(spotID: spot.id)
        XCTAssertNil(makeManager().spot(id: spot.id)?.tag, "forgetting an old sticker never deletes the Spot")
        XCTAssertNotNil(makeManager().spot(id: spot.id))
    }

    func testScanningStampsTheOldStickerButTestingDoesNot() {
        let manager = makeManager()
        var legacy = MivoSpot(name: "Study Desk", mode: .focus, defaultDurationMinutes: 60)
        legacy.tag = SpotTagBinding(carrier: .ndefTag, identifier: nil, connectedAt: clock.now, lastScannedAt: nil)
        guard case .success(let spot) = manager.save(legacy) else { return XCTFail("could not save spot") }

        manager.handleScan(spotID: spot.id, trigger: .test)
        XCTAssertNil(manager.spot(id: spot.id)?.tag?.lastScannedAt)

        clock.advance(10)
        manager.end(reason: .endedManually)
        manager.handleScan(spotID: spot.id, trigger: .link)
        XCTAssertEqual(manager.spot(id: spot.id)?.tag?.lastScannedAt, clock.now)
    }

    // MARK: Modes

    func testAnsweringTheIntentionCheckLiftsTheShieldForTheRestOfTheSpot() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .intention)
        manager.activate(spotID: spot.id, trigger: .manual)

        manager.answerIntention(choice: .shortBreak, note: "   ")

        XCTAssertEqual(manager.activeSession?.intention?.choice, .shortBreak)
        XCTAssertNil(manager.activeSession?.intention?.note, "blank notes are not kept")
        XCTAssertTrue(screenTime.liftedForRest)
    }

    func testIntentionAnswersOnlyApplyToIntentionSpots() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .focus)
        manager.activate(spotID: spot.id, trigger: .manual)
        manager.answerIntention(choice: .notSure, note: nil)
        XCTAssertNil(manager.activeSession?.intention)
        XCTAssertFalse(screenTime.liftedForRest)
    }

    func testContinuingPastAPauseOpensTheAppsForAWhileAndIsCounted() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .pause)
        manager.activate(spotID: spot.id, trigger: .manual)

        manager.continuePastPause(minutes: 10)

        XCTAssertEqual(screenTime.liftedUntil, clock.now.addingTimeInterval(600))
        XCTAssertEqual(manager.activeSession?.pausesContinued, 1)
    }

    func testAPauseNeverOutlastsTheSpot() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .pause, minutes: 5)
        manager.activate(spotID: spot.id, trigger: .manual)
        manager.continuePastPause(minutes: 15)
        XCTAssertEqual(screenTime.liftedUntil, manager.activeSession?.plannedEndDate)
    }

    func testShieldTapsRouteToTheRightPrompt() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .pause)
        manager.activate(spotID: spot.id, trigger: .manual)

        screenTime.pendingRoute = (.pause, "Instagram")
        manager.checkPendingShieldRoute()
        XCTAssertEqual(manager.shieldPrompt?.kind, .pause)
        XCTAssertEqual(manager.shieldPrompt?.appName, "Instagram")

        // A tap that doesn't match the Spot's mode just shows the running Spot.
        manager.declinePause()
        screenTime.pendingRoute = (.intention, nil)
        manager.checkPendingShieldRoute()
        XCTAssertNil(manager.shieldPrompt)
        XCTAssertTrue(manager.showActiveSpotRequested)
    }

    func testIntentionIsNotAskedTwice() {
        let manager = makeManager()
        let spot = addSpot(manager, mode: .intention)
        manager.activate(spotID: spot.id, trigger: .manual)
        manager.answerIntention(choice: .replyToSomeone, note: nil)

        screenTime.pendingRoute = (.intention, "Messages")
        manager.checkPendingShieldRoute()
        XCTAssertNil(manager.shieldPrompt)
    }

    // MARK: Accounts

    func testSwitchingAccountEndsARunningSpot() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(120)

        manager.setAccount("someone-else@example.com")

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.first?.completionReason, .signedOut)
    }

    func testSignOutEndsTheSpotButKeepsTheSavedSpots() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.activate(spotID: spot.id, trigger: .manual)
        clock.advance(120)

        manager.signOut()

        XCTAssertNil(manager.activeSession)
        XCTAssertTrue(manager.spots.isEmpty, "nothing is shown to the next person")
        XCTAssertEqual(persistence.loadSpots().count, 1, "the account's Spots stay saved")
    }

    func testDeletingTheAccountErasesEverything() {
        let manager = makeManager()
        let spot = addSpot(manager)
        manager.activate(spotID: spot.id, trigger: .manual)

        manager.eraseAllData()

        XCTAssertNil(manager.activeSession)
        XCTAssertTrue(persistence.loadSpots().isEmpty)
        XCTAssertTrue(persistence.loadSessions().isEmpty)
        XCTAssertNil(persistence.loadActiveSession())
    }

    // MARK: Links

    func testHandleURLActivatesFromEitherLinkShape() {
        let manager = makeManager()
        let spot = addSpot(manager)

        XCTAssertTrue(manager.handle(url: SpotLink.universalURL(for: spot.id)))
        XCTAssertEqual(manager.activeSession?.spotID, spot.id)
        XCTAssertEqual(manager.activeSession?.trigger, .link)
        manager.end(reason: .endedManually)

        XCTAssertTrue(manager.handle(url: SpotLink.customSchemeURL(for: spot.id)))
        XCTAssertEqual(manager.activeSession?.spotID, spot.id)
    }

    func testHandleURLLeavesEveryOtherLinkAlone() {
        let manager = makeManager()
        XCTAssertFalse(manager.handle(url: URL(string: "https://usemivo.app/accountability?token=x")!))
        XCTAssertFalse(manager.handle(url: URL(string: "mivo://companion")!))
        XCTAssertNil(manager.activeSession)
    }
}


// MARK: - Official Mivo Spots (physical product)

final class PhysicalSpotLinkTests: XCTestCase {
    func testOfficialURLRoundTrips() {
        let url = SpotLink.physicalURL(for: "A7K92X")
        XCTAssertEqual(url.absoluteString, "https://usemivo.app/s/A7K92X")
        XCTAssertEqual(SpotLink.physicalSpotID(from: url), "A7K92X")
        XCTAssertEqual(SpotLink.target(from: url), .physical("A7K92X"))
    }

    func testIDIsCaseInsensitiveAndAlsoOpensFromTheCustomScheme() {
        XCTAssertEqual(SpotLink.physicalSpotID(from: URL(string: "https://usemivo.app/s/a7k92x")!), "A7K92X")
        XCTAssertEqual(SpotLink.physicalSpotID(from: URL(string: "mivo://s/A7K92X")!), "A7K92X")
    }

    func testOtherShapesAreNotOfficialSpots() {
        let rejected = [
            "https://example.com/s/A7K92X",
            "http://usemivo.app/s/A7K92X",
            "https://usemivo.app/s/A7K92X/extra",
            "https://usemivo.app/s",
            "https://usemivo.app/s/ABC",
            "https://usemivo.app/s/ABCDEFGHIJKLM",
            "https://usemivo.app/s/A7K-92X",
            "https://usemivo.app/spot/A7K92X",
            "mivo://s",
            "mivo://s/A7K92X/extra",
            "mivo://spot/A7K92X"
        ]
        for string in rejected {
            XCTAssertNil(SpotLink.physicalSpotID(from: URL(string: string)!), string)
        }
    }

    func testFirstVersionLinksAreStillLegacyTargets() {
        let id = "3f2a9c1e-7b4d-4e0a-9d3c-1a2b3c4d5e6f"
        XCTAssertEqual(SpotLink.target(from: SpotLink.universalURL(for: id)), .legacy(id))
        XCTAssertNil(SpotLink.physicalSpotID(from: SpotLink.universalURL(for: id)))
        XCTAssertNil(SpotLink.target(from: URL(string: "https://usemivo.app/accountability?token=x")!))
    }

    func testIDNormalisation() {
        XCTAssertEqual(PhysicalSpotID.normalize(" a7k92x "), "A7K92X")
        XCTAssertNil(PhysicalSpotID.normalize("A7K9"))
        XCTAssertNil(PhysicalSpotID.normalize("A7K 92X"))
        XCTAssertNil(PhysicalSpotID.normalize("../../etc"))
        XCTAssertNil(PhysicalSpotID.normalize(String(repeating: "A", count: 13)))
    }
}

final class PhysicalSpotModelTests: XCTestCase {
    func testSpotsSavedBeforeMivoSpotsExistedStillLoadAsDigitalSpots() throws {
        var old = MivoSpot(name: "Study", mode: .focus, defaultDurationMinutes: 60)
        old.tag = SpotTagBinding(carrier: .ndefTag, identifier: "04aa", connectedAt: Date(timeIntervalSince1970: 1_800_000_000), lastScannedAt: nil)
        let data = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("physical"), "this is the first version's shape")

        let decoded = try JSONDecoder().decode(MivoSpot.self, from: data)
        XCTAssertEqual(decoded, old)
        XCTAssertNil(decoded.physical)
        XCTAssertEqual(decoded.kindLabel, "Digital Spot")
        XCTAssertEqual(decoded.link, SpotLink.universalURL(for: old.id), "an old sticker's link is unchanged")
        XCTAssertTrue(decoded.isConnected)
    }

    func testAMivoSpotKeepsItsLinkAcrossEncodingAndEdits() throws {
        let physical = PhysicalSpotLink(
            spotID: "A7K92X", ownerUserID: "user-1", status: .claimed,
            claimedAt: Date(timeIntervalSince1970: 1_800_000_000), lastScannedAt: nil, lastVerifiedAt: nil
        )
        var spot = MivoSpot(name: "Study", physical: physical)
        let decoded = try JSONDecoder().decode(MivoSpot.self, from: JSONEncoder().encode(spot))
        XCTAssertEqual(decoded, spot)
        XCTAssertEqual(decoded.kindLabel, "Mivo Spot")
        XCTAssertEqual(decoded.link.absoluteString, "https://usemivo.app/s/A7K92X")

        let before = spot.link
        spot.name = "Sleep"
        spot.mode = .pause
        spot.defaultDurationMinutes = nil
        XCTAssertEqual(spot.link, before, "what a Spot does can change without touching the Mivo Spot")
        XCTAssertEqual(physical.shortID, "…K92X")
    }

    func testBackendDatesWithMicrosecondsParse() {
        XCTAssertNotNil(MivoBackendService.parseSpotDate("2026-10-19T12:34:56.789012+00:00"))
        XCTAssertNotNil(MivoBackendService.parseSpotDate("2026-10-19T12:34:56+00:00"))
        XCTAssertNil(MivoBackendService.parseSpotDate(nil))
    }

    func testRegistryErrorsAreMappedToWhatThePersonReads() {
        XCTAssertEqual(BackendSpotRegistry.map(MivoBackendError.unavailable), .offline)
        XCTAssertEqual(BackendSpotRegistry.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(BackendSpotRegistry.map(MivoBackendError.authenticationRequired), .signedOut)
        XCTAssertEqual(BackendSpotRegistry.map(MivoBackendError.server("rate_limited")), .rateLimited)
        XCTAssertEqual(BackendSpotRegistry.map(MivoBackendError.server("JWT expired")), .signedOut)
        XCTAssertEqual(BackendSpotRegistry.map(MivoBackendError.server("boom")), .failed)
    }

    func testManufacturingExportIsOneRowPerSpot() {
        let csv = AdminSpotsView.csv(
            [("A7K92X", "https://usemivo.app/s/A7K92X", "unclaimed"), ("M3P82Q", "https://usemivo.app/s/M3P82Q", "claimed")],
            batch: "Launch \"run\" 1"
        )
        XCTAssertEqual(csv, """
        spot_id,url,status,batch
        A7K92X,https://usemivo.app/s/A7K92X,unclaimed,"Launch ""run"" 1"
        M3P82Q,https://usemivo.app/s/M3P82Q,claimed,"Launch ""run"" 1"

        """)
    }

    func testNewBatchesNameThemselvesWithoutTyping() {
        let day = Date(timeIntervalSince1970: 1_792_000_000)   // 2026-10-14 UTC
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(AdminSpotsView.defaultBatchLabel(on: day, timeZone: utc, existing: []), "Batch 14 Oct")
        XCTAssertEqual(
            AdminSpotsView.defaultBatchLabel(on: day, timeZone: utc, existing: ["Batch 14 Oct", "Launch"]),
            "Batch 14 Oct (2)"
        )
        XCTAssertEqual(
            AdminSpotsView.defaultBatchLabel(on: day, timeZone: utc, existing: ["Batch 14 Oct", "Batch 14 Oct (2)"]),
            "Batch 14 Oct (3)"
        )
    }

    func testBatchKnowsHowManyStickersAreLeft() {
        func batch(_ count: Int, programmed: Int?) -> AdminPhysicalSpotBatch {
            AdminPhysicalSpotBatch(
                id: "b", label: "B", spotCount: count, createdAt: "", claimedCount: 0,
                disabledCount: 0, programmedCount: programmed
            )
        }
        XCTAssertEqual(batch(100, programmed: 40).remainingToProgram, 60)
        XCTAssertEqual(batch(100, programmed: nil).remainingToProgram, 100)
        XCTAssertEqual(batch(10, programmed: 12).remainingToProgram, 0)
    }
}

@MainActor
final class PhysicalSpotManagerTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var clock = TestClock()
    private var persistence = InMemorySpotPersistence()
    private var registry = InMemorySpotRegistry()
    private static let suite = "mivo.spots.tests"
    private var defaults = UserDefaults(suiteName: PhysicalSpotManagerTests.suite)!
    private let studyID = "A7K92X"
    private let newID = "M3P82Q"

    override func setUp() {
        super.setUp()
        clock = TestClock()
        persistence = InMemorySpotPersistence()
        registry = InMemorySpotRegistry(unclaimed: [newID])
        defaults.removePersistentDomain(forName: Self.suite)
        defaults = UserDefaults(suiteName: Self.suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    private func makeManager(account: String? = "tester@example.com", attach: Bool = true) -> SpotManager {
        let manager = SpotManager(
            persistence: persistence,
            screenTime: NoopSpotScreenTime(),
            registry: registry,
            defaults: defaults,
            clock: { [clock] in clock.now }
        )
        manager.setAccount(account)
        if attach { manager.attachUI { } }
        return manager
    }

    /// A Study Spot this account already set up on a Mivo Spot.
    @discardableResult
    private func addMivoSpot(_ manager: SpotManager, id: String? = nil, name: String = "Study Desk") -> MivoSpot {
        let id = id ?? studyID
        registry.entries[id] = InMemorySpotRegistry.Entry(ownerID: registry.currentUserID, disabled: false, claimedAt: clock.now)
        let link = PhysicalSpotLink(
            spotID: id, ownerUserID: registry.currentUserID, status: .claimed,
            claimedAt: clock.now, lastScannedAt: nil, lastVerifiedAt: nil
        )
        guard case .success(let saved) = manager.save(MivoSpot(name: name, mode: .focus, defaultDurationMinutes: 60, physical: link)) else {
            XCTFail("could not save spot")
            return MivoSpot(name: name)
        }
        return saved
    }

    @discardableResult
    private func addDigitalSpot(_ manager: SpotManager, name: String = "Study Desk") -> MivoSpot {
        guard case .success(let saved) = manager.save(MivoSpot(name: name, mode: .focus, defaultDurationMinutes: 60)) else {
            XCTFail("could not save spot")
            return MivoSpot(name: name)
        }
        return saved
    }

    private func settle() async {
        for _ in 0..<12 { await Task.yield() }
    }

    // MARK: Everyday use

    func testATapStartsTheConfiguredSpotWithoutAskingAnythingOrNeedingTheInternet() {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        registry.failure = .offline

        XCTAssertTrue(manager.handle(url: SpotLink.physicalURL(for: studyID)))

        XCTAssertEqual(manager.activeSession?.spotID, spot.id)
        XCTAssertEqual(manager.activeSession?.trigger, .link)
        XCTAssertNil(manager.claimRequest, "no setup, no app picker, no timer")
        XCTAssertEqual(manager.notice?.title, "Study Desk activated")
        XCTAssertEqual(registry.resolveCalls, 0)
        XCTAssertEqual(registry.claimCalls, 0)
    }

    func testAnotherTapEndsItButARapidDoubleDeliveryDoesNot() {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        let url = SpotLink.physicalURL(for: studyID)

        manager.handle(url: url)
        clock.advance(1)
        manager.handle(url: url)   // iOS handed the same tap over twice
        manager.handle(target: .physical(studyID), trigger: .link)
        XCTAssertEqual(manager.activeSession?.spotID, spot.id, "the double delivery must not end it")

        clock.advance(10)
        manager.handle(url: url)
        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.first?.completionReason, .endedByTag)

        clock.advance(1)
        manager.handle(url: url)   // and the double delivery of the second tap must not restart it
        XCTAssertNil(manager.activeSession)
    }

    func testAScanStampsTheMivoSpotButATestDoesNot() {
        let manager = makeManager()
        let spot = addMivoSpot(manager)

        manager.handleScan(spotID: spot.id, trigger: .test)
        XCTAssertNil(manager.spot(id: spot.id)?.physical?.lastScannedAt)

        clock.advance(10)
        manager.end(reason: .endedManually)
        manager.handle(url: SpotLink.physicalURL(for: studyID))
        XCTAssertEqual(manager.spot(id: spot.id)?.physical?.lastScannedAt, clock.now)
    }

    func testAMivoSpotSwitchedOffByMivoCannotStart() {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        var off = spot
        off.physical?.status = .disabled
        _ = manager.save(off)

        manager.handle(url: SpotLink.physicalURL(for: studyID))

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.notice?.title, "This Mivo Spot is switched off")
        XCTAssertEqual(manager.notice?.isError, true)
    }

    func testSpotsFromTheFirstVersionKeepWorking() {
        let manager = makeManager()
        var legacy = MivoSpot(name: "Desk", mode: .focus, defaultDurationMinutes: 60)
        legacy.tag = SpotTagBinding(carrier: .ndefTag, identifier: nil, connectedAt: clock.now, lastScannedAt: nil)
        guard case .success(let spot) = manager.save(legacy) else { return XCTFail("could not save spot") }

        XCTAssertTrue(manager.handle(url: SpotLink.universalURL(for: spot.id)))
        XCTAssertEqual(manager.activeSession?.spotID, spot.id)
        XCTAssertEqual(manager.spot(id: spot.id)?.kindLabel, "Digital Spot")
    }

    // MARK: First scan

    func testAnUnclaimedMivoSpotOpensSetupAndClaimsNothingYet() async {
        let manager = makeManager()

        await manager.presentPhysicalSpot(newID)

        XCTAssertEqual(manager.claimRequest?.physicalID, newID)
        XCTAssertEqual(manager.claimRequest?.alreadyYours, false)
        XCTAssertEqual(registry.claimCalls, 0, "leaving setup must leave the Mivo Spot unclaimed")
        XCTAssertNil(registry.entries[newID]?.ownerID)
        XCTAssertTrue(manager.spots.isEmpty)
    }

    func testTappingAnUnknownMivoSpotLinkReachesSetup() async {
        let manager = makeManager()
        manager.handle(url: SpotLink.physicalURL(for: newID))
        await settle()
        XCTAssertEqual(manager.claimRequest?.physicalID, newID)
    }

    func testAMivoSpotAlreadyYoursButNotOnThisPhoneIsSetUpAgainNotClaimedAgain() async {
        registry.entries[newID] = InMemorySpotRegistry.Entry(ownerID: registry.currentUserID, disabled: false, claimedAt: clock.now)
        let manager = makeManager()

        await manager.presentPhysicalSpot(newID)

        XCTAssertEqual(manager.claimRequest?.alreadyYours, true)
    }

    func testAMivoSpotOwnedByAnotherAccountIsRefusedWithoutSayingWho() async {
        registry.entries[newID] = InMemorySpotRegistry.Entry(ownerID: "someone-else", disabled: false, claimedAt: clock.now)
        let manager = makeManager()

        await manager.presentPhysicalSpot(newID)

        XCTAssertNil(manager.claimRequest)
        XCTAssertEqual(manager.notice?.title, "This Mivo Spot is already connected to another account.")
        XCTAssertNil(manager.notice?.message)
        XCTAssertEqual(manager.notice?.isError, true)
        XCTAssertNil(manager.activeSession)
    }

    func testSwitchedOffAndUnknownMivoSpotsAreExplained() async {
        registry.entries["OFF2345"] = InMemorySpotRegistry.Entry(ownerID: nil, disabled: true, claimedAt: nil)
        let manager = makeManager()

        await manager.presentPhysicalSpot("OFF2345")
        XCTAssertEqual(manager.notice?.title, PhysicalSpotError.disabled.message)
        XCTAssertNil(manager.claimRequest)

        await manager.presentPhysicalSpot("ZZZZ999")
        XCTAssertEqual(manager.notice?.title, PhysicalSpotError.invalid.message)
        XCTAssertNil(manager.claimRequest)
    }

    func testNoConnectionIsReportedNotMistakenForAnInvalidSpot() async {
        let manager = makeManager()
        registry.failure = .offline

        await manager.presentPhysicalSpot(newID)

        XCTAssertEqual(manager.notice?.title, PhysicalSpotError.offline.message)
        XCTAssertNil(manager.claimRequest)
    }

    // MARK: Claiming

    func testClaimingSavesTheSetupAndTiesItToTheMivoSpot() async {
        let manager = makeManager()
        let setup = MivoSpot(name: "  Study  ", mode: .focus, defaultDurationMinutes: 25)

        let result = await manager.claimPhysicalSpot(physicalID: newID, configuring: setup)

        guard case .success(let saved) = result else { return XCTFail("expected success") }
        XCTAssertEqual(saved.name, "Study")
        XCTAssertEqual(saved.physical?.spotID, newID)
        XCTAssertEqual(saved.physical?.ownerUserID, "user-1")
        XCTAssertEqual(saved.physical?.status, .claimed)
        XCTAssertEqual(registry.entries[newID]?.ownerID, "user-1")
        XCTAssertEqual(makeManager().spot(id: saved.id)?.physical?.spotID, newID, "it survives a relaunch")

        // From now on a tap is all it takes.
        manager.handle(url: SpotLink.physicalURL(for: newID))
        XCTAssertEqual(manager.activeSession?.spotID, saved.id)
        XCTAssertEqual(manager.activeSession?.mode, .focus)
    }

    func testTheFirstPersonToClaimWins() async {
        let first = makeManager()
        let second = SpotManager(
            persistence: InMemorySpotPersistence(), screenTime: NoopSpotScreenTime(),
            registry: registry, defaults: defaults, clock: { [clock] in clock.now }
        )
        second.setAccount("other@example.com")

        let win = await first.claimPhysicalSpot(physicalID: newID, configuring: MivoSpot(name: "Study"))
        registry.currentUserID = "user-2"
        let lose = await second.claimPhysicalSpot(physicalID: newID, configuring: MivoSpot(name: "Mine now"))

        guard case .success = win else { return XCTFail("the first claim should win") }
        XCTAssertEqual(lose, .failure(.taken))
        XCTAssertTrue(second.spots.isEmpty, "a lost claim leaves no Spot behind")
        XCTAssertEqual(registry.entries[newID]?.ownerID, "user-1")
    }

    func testAFailedClaimLeavesNothingHalfDone() async {
        let manager = makeManager()
        registry.failure = .offline

        let result = await manager.claimPhysicalSpot(physicalID: newID, configuring: MivoSpot(name: "Study"))

        XCTAssertEqual(result, .failure(.offline))
        XCTAssertTrue(manager.spots.isEmpty)
        XCTAssertNil(registry.entries[newID]?.ownerID)
    }

    func testSetupIsValidatedBeforeAnythingIsClaimed() async {
        let manager = makeManager()

        let unnamed = await manager.claimPhysicalSpot(physicalID: newID, configuring: MivoSpot(name: "  "))
        XCTAssertEqual(unnamed, .failure(.emptyName))

        for index in 0..<SpotManager.maxSpots { addDigitalSpot(manager, name: "Spot \(index)") }
        let full = await manager.claimPhysicalSpot(physicalID: newID, configuring: MivoSpot(name: "One too many"))
        XCTAssertEqual(full, .failure(.tooManySpots))

        XCTAssertEqual(registry.claimCalls, 0)
        XCTAssertNil(registry.entries[newID]?.ownerID)
    }

    func testConnectingToAnExistingSetupKeepsItsConfigurationAndHistory() async {
        let manager = makeManager()
        let study = addDigitalSpot(manager)
        manager.activate(spotID: study.id, trigger: .manual)
        clock.advance(600)
        manager.end(reason: .endedManually)
        let before = manager.sessions(for: study.id).count

        let result = await manager.claimPhysicalSpot(physicalID: newID, configuring: manager.spot(id: study.id)!)

        guard case .success(let saved) = result else { return XCTFail("expected success") }
        XCTAssertEqual(saved.id, study.id, "the same Spot, not a copy")
        XCTAssertEqual(saved.mode, study.mode)
        XCTAssertEqual(saved.defaultDurationMinutes, study.defaultDurationMinutes)
        XCTAssertEqual(saved.selectedApplications, study.selectedApplications)
        XCTAssertEqual(manager.spots.count, 1)
        XCTAssertEqual(manager.sessions(for: study.id).count, before)
        XCTAssertEqual(saved.kindLabel, "Mivo Spot")
    }

    func testChangingWhatASpotDoesNeverChangesItsMivoSpot() {
        let manager = makeManager()
        var spot = addMivoSpot(manager)
        let link = spot.link

        spot.name = "Sleep"
        spot.icon = SpotIcon.symbol("bed.double")
        spot.mode = .pause
        spot.defaultDurationMinutes = nil
        guard case .success(let saved) = manager.save(spot) else { return XCTFail("could not save") }

        XCTAssertEqual(saved.link, link)
        XCTAssertEqual(saved.physical?.spotID, studyID)
        manager.handle(url: link)
        XCTAssertEqual(manager.activeSession?.mode, .pause, "the same Mivo Spot now runs the new setup")
    }

    // MARK: Logged out

    func testAScanWhileLoggedOutWaitsForSignIn() async {
        let manager = makeManager(account: nil, attach: false)

        manager.handle(url: SpotLink.physicalURL(for: newID))
        await settle()
        XCTAssertNil(manager.claimRequest)
        XCTAssertEqual(registry.resolveCalls, 0)

        manager.setAccount("tester@example.com")
        manager.attachUI { }
        await settle()

        XCTAssertEqual(manager.claimRequest?.physicalID, newID, "the ID survived signing in")
    }

    func testAScanBeforeTheUIIsUpIsKeptToo() async {
        let manager = makeManager(attach: false)

        manager.handle(url: SpotLink.physicalURL(for: newID))
        XCTAssertNil(manager.claimRequest)

        manager.attachUI { }
        await settle()
        XCTAssertEqual(manager.claimRequest?.physicalID, newID)
    }

    func testAnOldPendingScanIsForgotten() async {
        let manager = makeManager(account: nil, attach: false)
        manager.handle(url: SpotLink.physicalURL(for: newID))

        clock.advance(SpotManager.pendingLinkLifetime + 1)
        manager.setAccount("tester@example.com")
        manager.attachUI { }
        await settle()

        XCTAssertNil(manager.claimRequest)
    }

    func testAPendingScanIsUsedOnce() async {
        let manager = makeManager(account: nil, attach: false)
        manager.handle(url: SpotLink.physicalURL(for: newID))
        manager.setAccount("tester@example.com")
        manager.attachUI { }
        await settle()
        manager.claimRequest = nil

        manager.attachUI { }
        await settle()
        XCTAssertNil(manager.claimRequest)
    }

    // MARK: Staying in step with the backend

    func testASpotMivoSwitchedOffStopsWorkingAndEndsWhatWasRunning() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        manager.activate(spotID: spot.id, trigger: .link)
        clock.advance(120)
        registry.entries[studyID]?.disabled = true

        await manager.syncPhysicalSpots(force: true)

        XCTAssertEqual(manager.spot(id: spot.id)?.physical?.status, .disabled)
        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.sessions.first?.completionReason, .spotRemoved)
    }

    func testASpotReleasedElsewhereBecomesADigitalSpotWithItsSetupIntact() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        registry.entries[studyID]?.ownerID = nil

        await manager.syncPhysicalSpots(force: true)

        let after = manager.spot(id: spot.id)
        XCTAssertNil(after?.physical)
        XCTAssertEqual(after?.name, spot.name)
        XCTAssertEqual(after?.mode, spot.mode)
        XCTAssertEqual(after?.kindLabel, "Digital Spot")
    }

    func testAFailedCheckChangesNothing() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        registry.failure = .offline

        await manager.syncPhysicalSpots(force: true)

        XCTAssertEqual(manager.spot(id: spot.id)?.physical?.status, .claimed)
    }

    func testTheBackendIsNotAskedOnEveryTap() async {
        let manager = makeManager()
        await settle()   // let the check made on attaching finish before counting
        addMivoSpot(manager)
        await manager.syncPhysicalSpots(force: true)
        let calls = registry.mineCalls

        await manager.syncPhysicalSpots()
        XCTAssertEqual(registry.mineCalls, calls)

        clock.advance(SpotManager.physicalSyncInterval + 1)
        await manager.syncPhysicalSpots()
        XCTAssertEqual(registry.mineCalls, calls + 1)
    }

    // MARK: Letting go

    func testDisconnectingFreesTheMivoSpotAndKeepsTheSetup() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)

        let result = await manager.disconnectPhysicalSpot(spotID: spot.id)

        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertNil(manager.spot(id: spot.id)?.physical)
        XCTAssertNil(registry.entries[studyID]?.ownerID, "it can be claimed again")
    }

    func testDisconnectingNeedsTheInternetSoBothSidesAgree() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)
        registry.failure = .offline

        let result = await manager.disconnectPhysicalSpot(spotID: spot.id)

        guard case .failure(let error) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(error, .offline)
        XCTAssertNotNil(manager.spot(id: spot.id)?.physical)
    }

    func testDeletingASpotFreesItsMivoSpot() async {
        let manager = makeManager()
        let spot = addMivoSpot(manager)

        await manager.deleteSpot(spotID: spot.id)

        XCTAssertNil(manager.spot(id: spot.id))
        XCTAssertNil(registry.entries[studyID]?.ownerID)
    }

    func testDeletingTheAccountForgetsAPendingScan() async {
        let manager = makeManager(account: nil, attach: false)
        manager.handle(url: SpotLink.physicalURL(for: newID))

        manager.eraseAllData()
        manager.setAccount("tester@example.com")
        manager.attachUI { }
        await settle()

        XCTAssertNil(manager.claimRequest)
    }
}

// MARK: - Programming a batch of stickers (staff)

@MainActor
final class SpotBatchProgrammerTests: XCTestCase {
    private final class FakeBackend: SpotProgrammingBackend {
        let codes: [String]
        var done: Set<String> = []
        var marks: [String] = []
        var markFailures = 0

        init(_ codes: [String]) { self.codes = codes }

        func next(batchID: String) async throws -> SpotProgrammingNext {
            SpotProgrammingNext(spotID: codes.first { !done.contains($0) }, programmed: done.count, total: codes.count)
        }

        func markProgrammed(_ spotID: String) async throws {
            if markFailures > 0 {
                markFailures -= 1
                throw URLError(.notConnectedToInternet)
            }
            done.insert(spotID)
            marks.append(spotID)
        }
    }

    @MainActor
    private final class FakeWriter: SpotStickerWriting {
        /// One entry per sticker held to the phone; an empty script means every sticker works.
        var script: [SpotNFCError?] = []
        var written: [String] = []

        func program(_ spotID: String, prompt: String) async throws {
            if !script.isEmpty, let failure = script.removeFirst() { throw failure }
            written.append(spotID)
        }
    }

    private let codes = ["AAAA2222", "BBBB3333", "CCCC4444"]

    private func make(_ backend: FakeBackend, _ writer: FakeWriter) -> SpotBatchProgrammer {
        SpotBatchProgrammer(batchID: "batch-1", backend: backend, writer: writer, pause: {})
    }

    func testEveryCodeGoesOntoAStickerInOrderThenItFinishes() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(writer.written, codes)
        XCTAssertEqual(backend.marks, codes)
        XCTAssertTrue(programmer.isFinished)
        XCTAssertEqual(programmer.programmed, 3)
        XCTAssertEqual(programmer.lastProgrammed, "CCCC4444")
        XCTAssertEqual(programmer.message, "All 3 stickers are programmed.")
        XCTAssertFalse(programmer.isRunning)
    }

    func testAStickerThatAlreadyHasACodeIsRefusedAndNoCodeIsUsedUp() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        writer.script = [.alreadyProgrammed("ZZZZ9999")]   // the first sticker is not blank
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(writer.written, codes, "the first code still went onto the next, blank sticker")
        XCTAssertEqual(backend.marks, codes)
        XCTAssertTrue(programmer.isFinished)
    }

    func testACodeIsNeverHandedOutTwiceWhenSavingItFails() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        backend.markFailures = SpotBatchProgrammer.recordAttempts   // offline right after the first sticker
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(writer.written, ["AAAA2222"])
        XCTAssertEqual(programmer.unrecorded, "AAAA2222")
        XCTAssertTrue(backend.marks.isEmpty)
        XCTAssertFalse(programmer.isFinished)
        XCTAssertTrue(programmer.message?.contains("couldn't be saved") == true)

        // Back online: that code is saved first, and is not written to a second sticker.
        await programmer.run()

        XCTAssertEqual(writer.written, codes)
        XCTAssertEqual(backend.marks, codes)
        XCTAssertNil(programmer.unrecorded)
        XCTAssertTrue(programmer.isFinished)
    }

    func testABriefOutageWhileSavingIsRetried() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        backend.markFailures = 1
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(backend.marks, codes)
        XCTAssertTrue(programmer.isFinished)
    }

    func testDismissingTheScanSheetStopsCleanly() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        writer.script = [nil, .cancelled]   // one sticker done, then the sheet is dismissed
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(writer.written, ["AAAA2222"])
        XCTAssertEqual(backend.marks, ["AAAA2222"])
        XCTAssertEqual(programmer.message, "Stopped.")
        XCTAssertFalse(programmer.isFinished)
        XCTAssertNil(programmer.unrecorded)
    }

    func testAnUnwritableStickerStopsWithAReadableMessageAndUsesNoCode() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        writer.script = [.notWritable]
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertEqual(programmer.message, SpotNFCError.notWritable.message)
        XCTAssertTrue(backend.marks.isEmpty)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testAFinishedBatchWritesNothing() async {
        let backend = FakeBackend(codes), writer = FakeWriter()
        backend.done = Set(codes)
        let programmer = make(backend, writer)

        await programmer.run()

        XCTAssertTrue(programmer.isFinished)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testTheRefusalNamesTheCodeAlreadyOnTheSticker() {
        XCTAssertEqual(
            SpotNFCError.alreadyProgrammed("ZZZZ9999").message,
            "That sticker is already programmed as ZZZZ9999. Use a blank one."
        )
    }
}
