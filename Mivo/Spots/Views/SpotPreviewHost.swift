#if DEBUG
import SwiftUI

/// Launch-argument previews for the Spots screens, in the same spirit as the
/// `-MivoPreview…` hosts in `RootView`. Fixtures only; nothing is saved.
///
///     -MivoPreviewSpots            the list, with a Spot running
///     -MivoPreviewSpotsEmpty       the list with no Spots yet
///     -MivoPreviewSpotDetail       one Spot's detail page
///     -MivoPreviewSpotSetup        the create flow
///     -MivoPreviewSpotConnect      connecting a Mivo Spot to an existing Spot
///     -MivoPreviewSpotClaim        "Meet your new Mivo Spot" (first scan, with existing Spots)
///     -MivoPreviewSpotActive       the running Spot
///     -MivoPreviewSpotSummary      a finished session, with a comparison
///     -MivoPreviewSpotPause        the Mivo pause for a Pause-mode Spot
///     -MivoPreviewSpotIntention    "What did you come here to do?"
///     -MivoPreviewSpotNotice       the tap confirmation
struct SpotPreviewHost: View {
    enum Screen: String, CaseIterable {
        case list = "-MivoPreviewSpots"
        case empty = "-MivoPreviewSpotsEmpty"
        case detail = "-MivoPreviewSpotDetail"
        case setup = "-MivoPreviewSpotSetup"
        case connect = "-MivoPreviewSpotConnect"
        case claim = "-MivoPreviewSpotClaim"
        case active = "-MivoPreviewSpotActive"
        case summary = "-MivoPreviewSpotSummary"
        case pause = "-MivoPreviewSpotPause"
        case intention = "-MivoPreviewSpotIntention"
        case notice = "-MivoPreviewSpotNotice"
    }

    static func screen(from arguments: [String]) -> Screen? {
        Screen.allCases.first { arguments.contains($0.rawValue) }
    }

    let screen: Screen

    private static let now = Date()

    private static let desk = MivoSpot(
        id: "11111111-aaaa-4bbb-8ccc-000000000001",
        name: "Study Desk", icon: SpotIcon.symbol("books.vertical"),
        selectedApplications: SpotAppSelection(
            data: nil, appNames: ["Instagram", "TikTok", "YouTube"],
            applicationCount: 3, categoryCount: 0, webDomainCount: 0
        ),
        mode: .focus, defaultDurationMinutes: 60,
        physical: PhysicalSpotLink(
            spotID: "A7K92X", ownerUserID: nil, status: .claimed,
            claimedAt: now.addingTimeInterval(-3 * 86_400), lastScannedAt: now.addingTimeInterval(-2 * 3600), lastVerifiedAt: nil
        )
    )
    private static let bedside = MivoSpot(
        id: "11111111-aaaa-4bbb-8ccc-000000000002",
        name: "Bedside", icon: SpotIcon.symbol("bed.double"),
        selectedApplications: SpotAppSelection(
            data: nil, appNames: ["Instagram", "Reddit"],
            applicationCount: 2, categoryCount: 0, webDomainCount: 0
        ),
        mode: .pause, defaultDurationMinutes: 120
    )
    private static let car = MivoSpot(
        id: "11111111-aaaa-4bbb-8ccc-000000000003",
        name: "Car", icon: "🚗",
        selectedApplications: SpotAppSelection(
            data: nil, appNames: [], applicationCount: 2, categoryCount: 1, webDomainCount: 0
        ),
        mode: .awareness, defaultDurationMinutes: nil, isEnabled: true
    )

    private static func session(
        _ spot: MivoSpot, daysAgo: Int, minutes: Int, distracting: Int?,
        running: Bool = false, intention: SpotIntentionAnswer? = nil
    ) -> SpotSession {
        let start = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400 - (running ? minutes * 60 : 0)))
        let planned = running ? now.addingTimeInterval(TimeInterval((spot.defaultDurationMinutes ?? 60) * 60 - minutes * 60)) : start.addingTimeInterval(TimeInterval(minutes * 60))
        return SpotSession(
            id: UUID().uuidString.lowercased(), spotID: spot.id, spotName: spot.name, spotIcon: spot.icon,
            mode: spot.mode, startDate: start, plannedEndDate: planned, isOpenEnded: spot.defaultDurationMinutes == nil,
            endDate: running ? nil : planned, completionReason: running ? nil : .timerCompleted, trigger: .link,
            trackedApps: [], usageTracked: distracting != nil,
            usage: distracting.map {
                SpotUsageRecord(totalMinutes: $0, perApp: [
                    SpotAppUsage(index: 0, name: "Instagram", tokenData: nil, minutes: min($0, 8)),
                    SpotAppUsage(index: 1, name: "YouTube", tokenData: nil, minutes: max(0, $0 - 8))
                ])
            },
            intention: intention, pausesContinued: 0, summarySeen: true
        )
    }

    private static func seed(running: Bool, withHistory: Bool = true, mode: SpotMode? = nil) {
        var desk = desk
        if let mode { desk.mode = mode }
        let history = withHistory ? [
            session(desk, daysAgo: 2, minutes: 60, distracting: 30),
            session(desk, daysAgo: 3, minutes: 60, distracting: 28),
            session(desk, daysAgo: 5, minutes: 45, distracting: 22),
            session(desk, daysAgo: 6, minutes: 60, distracting: 34),
            session(bedside, daysAgo: 1, minutes: 25, distracting: nil)
        ] : []
        let active = running ? session(desk, daysAgo: 0, minutes: 18, distracting: nil, running: true) : nil
        SpotManager.shared.loadPreviewState(spots: [desk, bedside, car], sessions: history, active: active)
    }

    var body: some View {
        content
            .onAppear { configure() }
    }

    private func configure() {
        switch screen {
        case .list, .detail, .active, .notice: Self.seed(running: screen != .detail)
        case .empty: SpotManager.shared.loadPreviewState(spots: [], sessions: [], active: nil)
        case .setup, .connect, .claim: Self.seed(running: false)
        case .summary, .pause, .intention: Self.seed(running: false)
        }
        if screen == .notice {
            SpotManager.shared.notice = SpotNotice(
                title: "Study Desk activated", message: "Focus for the next hour.",
                caveat: nil, spotID: Self.desk.id, icon: Self.desk.icon
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .list, .empty:
            NavigationStack { SpotsHomeView() }
        case .detail:
            NavigationStack { SpotDetailView(spotID: Self.desk.id) }
        case .setup:
            SpotSetupFlowView(editing: nil)
        case .connect:
            SpotPairSheet(spotID: Self.bedside.id)
        case .claim:
            SpotSetupFlowView(editing: nil, claim: PhysicalSpotClaimRequest(physicalID: "M3P82Q"))
        case .active:
            SpotActiveView()
        case .notice:
            ZStack {
                MivoColors.background.ignoresSafeArea()
                SpotNoticeOverlay()
            }
        case .summary:
            let history = [
                Self.session(Self.desk, daysAgo: 2, minutes: 60, distracting: 30),
                Self.session(Self.desk, daysAgo: 3, minutes: 60, distracting: 28),
                Self.session(Self.desk, daysAgo: 5, minutes: 45, distracting: 22)
            ]
            let current = Self.session(Self.desk, daysAgo: 0, minutes: 72, distracting: 21)
            SpotSummaryView(summary: SpotInsights.summary(for: current, history: history + [current]))
        case .pause:
            SpotPauseView(prompt: SpotShieldPrompt(kind: .pause, spotName: "Bedside", appName: "Instagram"))
        case .intention:
            SpotIntentionView(prompt: SpotShieldPrompt(kind: .intention, spotName: "Kitchen", appName: "TikTok"))
        }
    }
}
#endif
