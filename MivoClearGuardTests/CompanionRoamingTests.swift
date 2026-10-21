import XCTest
@testable import Mivo

/// Where Milo walks, when he stays put, and the walk cycle. All plain values, so
/// none of it needs a view or a clock.
final class CompanionRoamingTests: XCTestCase {
    /// Deterministic, so a failing run can be replayed.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private let bounds = CGRect(x: 37, y: 119, width: 283, height: 500)
    private let now = Date(timeIntervalSince1970: 1_000)

    private var planner: CompanionRoamPlanner { CompanionRoamPlanner(bounds: bounds) }

    private func contains(_ point: CGPoint) -> Bool {
        point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY
    }

    // MARK: - Planning

    func testEveryLegStaysInsideTheBounds() {
        var rng = SeededGenerator(state: 7)
        var here = planner.home
        for _ in 0..<500 {
            let leg = planner.nextLeg(from: here, speed: 40, now: now, using: &rng)
            XCTAssertTrue(contains(leg.to), "\(leg.to) left \(bounds)")
            here = leg.to
        }
    }

    func testLegsFromAnywhereAreLongEnoughToReadAsWalks() {
        var rng = SeededGenerator(state: 11)
        for _ in 0..<500 {
            let start = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX, using: &rng),
                y: CGFloat.random(in: bounds.minY...bounds.maxY, using: &rng)
            )
            let leg = planner.nextLeg(from: start, speed: 40, now: now, using: &rng)
            let distance = hypot(leg.to.x - leg.from.x, leg.to.y - leg.from.y)
            XCTAssertGreaterThanOrEqual(distance, CompanionRoamPlanner.minimumLeg - 0.5, "from \(start)")
        }
    }

    func testTheSameSeedWalksTheSameRoute() {
        func route() -> [CGPoint] {
            var rng = SeededGenerator(state: 99)
            var here = planner.home
            return (0..<20).map { _ in
                let leg = planner.nextLeg(from: here, speed: 40, now: now, using: &rng)
                here = leg.to
                return leg.to
            }
        }
        XCTAssertEqual(route(), route())
    }

    func testSlowerSpeedTakesLonger() {
        let a = CGPoint(x: 50, y: 300), b = CGPoint(x: 250, y: 300)
        XCTAssertEqual(planner.leg(from: a, to: b, speed: 40, now: now).duration, 5, accuracy: 0.001)
        XCTAssertEqual(planner.leg(from: a, to: b, speed: 20, now: now).duration, 10, accuracy: 0.001)
    }

    func testHomeIsTheBottomRightCorner() {
        XCTAssertEqual(planner.home, CGPoint(x: bounds.maxX, y: bounds.maxY))
    }

    func testRestingClipsOnlyVaryForRelaxedStates() {
        var rng = SeededGenerator(state: 3)
        XCTAssertEqual(
            planner.restClip(for: .tired, restDuration: 5, stretchUnlocked: true, using: &rng), .tired
        )
        XCTAssertEqual(
            planner.restClip(for: .sleeping, restDuration: 5, stretchUnlocked: true, using: &rng), .sleeping
        )
        let relaxed = (0..<200).map { _ in
            planner.restClip(for: .idle, restDuration: 5, stretchUnlocked: false, using: &rng)
        }
        XCTAssertFalse(relaxed.contains(.stretching), "a locked stretch never plays")
        XCTAssertGreaterThan(Set(relaxed).count, 1)
    }

    func testShortRestsSkipTheStretch() {
        var rng = SeededGenerator(state: 5)
        let clips = (0..<200).map { _ in
            planner.restClip(for: .idle, restDuration: 2.6, stretchUnlocked: true, using: &rng)
        }
        XCTAssertFalse(clips.contains(.stretching))
    }

    // MARK: - Legs and phases

    func testLegInterpolatesAndClampsAtItsEnds() {
        let leg = RoamLeg(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50), start: now, duration: 10)
        XCTAssertEqual(leg.position(at: now.addingTimeInterval(-5)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(leg.position(at: now.addingTimeInterval(5)), CGPoint(x: 50, y: 25))
        XCTAssertEqual(leg.position(at: now.addingTimeInterval(99)), CGPoint(x: 100, y: 50))
        XCTAssertEqual(leg.facing, .right)
        XCTAssertEqual(leg.end, now.addingTimeInterval(10))
    }

    func testFacingFollowsTheDirectionOfTravel() {
        let left = RoamLeg(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 10, y: 0), start: now, duration: 2)
        XCTAssertEqual(left.facing, .left)
        XCTAssertEqual(RoamPhase.walking(left).facing, .left)
    }

    func testAMidWalkPhaseReportsWhereHeIsNotWhereHeIsGoing() {
        let leg = RoamLeg(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), start: now, duration: 4)
        XCTAssertEqual(RoamPhase.walking(leg).position(at: now.addingTimeInterval(1)).x, 50, accuracy: 0.001)
    }

    func testRestingAndReactingStayWhereTheyAre() {
        let spot = CGPoint(x: 12, y: 34)
        let resting = RoamPhase.resting(at: spot, since: now, clip: .idleBreathing, facing: .left)
        let reacting = RoamPhase.reacting(at: spot, since: now, facing: .right)
        XCTAssertEqual(resting.position(at: now.addingTimeInterval(60)), spot)
        XCTAssertEqual(reacting.position(at: now.addingTimeInterval(1)), spot)
        XCTAssertEqual(reacting.facing, .right)
    }

    // MARK: - Modes

    func testSleepingAndHeadsDownStatesStayParked() {
        for state in [CompanionState.sleeping, .focused, .resting, .intervening] {
            XCTAssertEqual(CompanionRoamMode.mode(for: state), .parked, "\(state)")
        }
    }

    func testEveryOtherStateWalksAndTiredWalksSlowest() {
        var speeds: [CompanionState: CGFloat] = [:]
        for state in CompanionState.allCases {
            guard case .walking(let speed) = CompanionRoamMode.mode(for: state) else { continue }
            XCTAssertGreaterThan(speed, 0)
            speeds[state] = speed
        }
        XCTAssertEqual(
            Set(speeds.keys),
            [.idle, .happy, .curious, .watching, .tired, .concerned, .celebrating]
        )
        XCTAssertEqual(speeds.values.min(), speeds[.tired])
    }

    // MARK: - Walk cycle

    func testWalkEasesInAndOutSoLegsJoinTheRestingPose() {
        let base = MeerkatMotion.staticPose(for: .idle)
        let atStart = MeerkatWalk.pose(base: base, elapsed: 0, duration: 5, speed: 40)
        let atEnd = MeerkatWalk.pose(base: base, elapsed: 5, duration: 5, speed: 40)
        XCTAssertEqual(atStart, base)
        XCTAssertEqual(atEnd, base)
        XCTAssertEqual(MeerkatWalk.ramp(elapsed: 2.5, duration: 5), 1)
    }

    func testWalkHopsNeverGoBelowTheGround() {
        let base = MeerkatMotion.staticPose(for: .idle)
        for step in 0..<200 {
            let p = MeerkatWalk.pose(base: base, elapsed: Double(step) * 0.05, duration: 10, speed: 40)
            XCTAssertGreaterThanOrEqual(p.lift, 0)
            XCTAssertLessThanOrEqual(p.lift, 9.001)
        }
    }

    func testWalkLooksAheadAndIsMirroredByTheView() {
        let base = MeerkatMotion.staticPose(for: .idle)
        let p = MeerkatWalk.pose(base: base, elapsed: 2, duration: 5, speed: 40)
        XCTAssertEqual(p.eyeLookX, -0.9, accuracy: 0.001, "mirrored art makes 'left' the way he's heading")
    }

    // MARK: - Layout and preference

    func testThereIsNoRoomToWanderInAnEmptyOrTinyContainer() {
        XCTAssertNil(CompanionRoamingOverlay.bounds(in: .zero))
        XCTAssertNil(CompanionRoamingOverlay.bounds(in: CGSize(width: 120, height: 300)))
    }

    func testPhoneScreenBoundsSitAboveTheTabBarAndInsideTheEdges() throws {
        let size = CGSize(width: 393, height: 759)
        let rect = try XCTUnwrap(CompanionRoamingOverlay.bounds(in: size))
        let figure = CompanionRoamingOverlay.figureSize
        XCTAssertGreaterThanOrEqual(rect.minX - figure.width / 2, CompanionRoamingOverlay.edgeMargin - 0.001)
        XCTAssertLessThanOrEqual(rect.maxX + figure.width / 2, size.width - CompanionRoamingOverlay.edgeMargin + 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, size.height - CompanionRoamingOverlay.tabBarClearance + 0.001)
        XCTAssertGreaterThanOrEqual(rect.minY - figure.height, CompanionRoamingOverlay.topClearance - 0.001)
    }

    func testRoamingIsOnByDefaultAndOlderSavedPreferencesGetIt() throws {
        XCTAssertTrue(CompanionPreferences().roamingEnabled)
        let old = #"{"schemaVersion":1,"isEnabled":true,"hasCompletedOnboarding":true,"name":"Milo"}"#
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.roamingEnabled)
    }

    func testTurningRoamingOffSurvivesASaveAndLoad() throws {
        var prefs = CompanionPreferences()
        prefs.roamingEnabled = false
        let data = try JSONEncoder().encode(prefs)
        XCTAssertFalse(try JSONDecoder().decode(CompanionPreferences.self, from: data).roamingEnabled)
    }

    func testResettingPreferencesTurnsRoamingBackOn() {
        var prefs = CompanionPreferences()
        prefs.roamingEnabled = false
        XCTAssertTrue(prefs.resetToDefaults().roamingEnabled)
    }

    @MainActor
    func testTheGateIsHeldUntilEveryHolderReleases() {
        let gate = CompanionRoamingGate()
        let a = UUID(), b = UUID()
        gate.hold(a); gate.hold(b)
        XCTAssertTrue(gate.isHeld)
        gate.release(a)
        XCTAssertTrue(gate.isHeld)
        gate.release(a) // a stray second release changes nothing
        gate.release(b)
        XCTAssertFalse(gate.isHeld)
    }
}
