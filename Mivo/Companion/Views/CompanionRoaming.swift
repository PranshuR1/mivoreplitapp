import SwiftUI

// The companion wandering around inside Mivo. iOS has no way to draw over other
// apps, so this only exists while Mivo is open and on screen.
//
// Everything that decides *where* Milo goes is plain values (`RoamLeg`,
// `RoamPhase`, `CompanionRoamPlanner`, `MeerkatWalk`) so it can be tested
// without a view. `CompanionRoamer` just runs those decisions on a timer, and
// the view samples position and pose from the current phase every frame.

// MARK: - Planning

/// Direction of travel. The artwork faces the viewer with its tail on the
/// right, so this only decides whether to mirror it to keep the tail behind.
enum RoamFacing: Equatable {
    case left
    case right
}

/// One straight walk between two standing spots, at constant speed.
struct RoamLeg: Equatable {
    var from: CGPoint
    var to: CGPoint
    var start: Date
    var duration: TimeInterval

    var end: Date { start.addingTimeInterval(duration) }
    var facing: RoamFacing { to.x >= from.x ? .right : .left }
    var speed: Double {
        duration > 0 ? Double(hypot(to.x - from.x, to.y - from.y)) / duration : 0
    }

    func position(at date: Date) -> CGPoint {
        guard duration > 0 else { return to }
        let t = min(1, max(0, date.timeIntervalSince(start) / duration))
        return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }
}

/// What Milo is doing right now. Position is a function of time, so a tap or a
/// mode change can read exactly where he is mid-walk instead of snapping.
enum RoamPhase: Equatable {
    case resting(at: CGPoint, since: Date, clip: CompanionAnimation, facing: RoamFacing)
    case walking(RoamLeg)
    case reacting(at: CGPoint, since: Date, facing: RoamFacing)

    func position(at date: Date) -> CGPoint {
        switch self {
        case .resting(let point, _, _, _), .reacting(let point, _, _): return point
        case .walking(let leg): return leg.position(at: date)
        }
    }

    var facing: RoamFacing {
        switch self {
        case .resting(_, _, _, let facing), .reacting(_, _, let facing): return facing
        case .walking(let leg): return leg.facing
        }
    }
}

/// Whether Milo strolls or stays put for a given companion state.
enum CompanionRoamMode: Equatable {
    case walking(speed: CGFloat)
    /// Settled at the home spot, in the state's own pose (asleep, heads-down).
    case parked

    static func mode(for state: CompanionState) -> CompanionRoamMode {
        switch state {
        case .sleeping, .focused, .resting, .intervening: return .parked
        case .tired: return .walking(speed: 22)
        case .concerned, .watching: return .walking(speed: 32)
        case .idle: return .walking(speed: 40)
        case .curious, .happy, .celebrating: return .walking(speed: 50)
        }
    }
}

/// Picks where Milo goes next. `bounds` is where his feet may land.
struct CompanionRoamPlanner {
    static let minimumLeg: CGFloat = 70
    static let maximumLeg: CGFloat = 240
    /// Sideways strolls drift a little up or down, so he covers the whole screen over time.
    static let maximumDrift: CGFloat = 110

    var bounds: CGRect

    /// Bottom-right, on top of the tab bar: where he settles to sleep.
    var home: CGPoint { CGPoint(x: bounds.maxX, y: bounds.maxY) }

    func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    func leg(from: CGPoint, to: CGPoint, speed: CGFloat, now: Date) -> RoamLeg {
        let distance = hypot(to.x - from.x, to.y - from.y)
        return RoamLeg(from: from, to: to, start: now, duration: max(0.3, Double(distance / max(speed, 1))))
    }

    func nextLeg<G: RandomNumberGenerator>(
        from point: CGPoint, speed: CGFloat, now: Date, using rng: inout G
    ) -> RoamLeg {
        let start = clamped(point)
        var direction: CGFloat = Bool.random(using: &rng) ? 1 : -1
        // Near a wall, head for open space so every walk is long enough to read as one.
        if start.x + Self.minimumLeg > bounds.maxX {
            direction = -1
        } else if start.x - Self.minimumLeg < bounds.minX {
            direction = 1
        }
        let reach = CGFloat.random(in: Self.minimumLeg...Self.maximumLeg, using: &rng)
        let drift = CGFloat.random(in: -Self.maximumDrift...Self.maximumDrift, using: &rng)
        let destination = clamped(CGPoint(x: start.x + direction * reach, y: start.y + drift))
        return leg(from: start, to: destination, speed: speed, now: now)
    }

    func restDuration<G: RandomNumberGenerator>(using rng: inout G) -> TimeInterval {
        TimeInterval.random(in: 2.5...7, using: &rng)
    }

    /// States with a relaxed posture look around, breathe or stretch between
    /// walks; the others keep their own clip (a sleepy Milo stays sleepy).
    func restClip<G: RandomNumberGenerator>(
        for state: CompanionState, restDuration: TimeInterval, stretchUnlocked: Bool, using rng: inout G
    ) -> CompanionAnimation {
        switch state {
        case .idle, .happy, .curious, .watching:
            var options: [CompanionAnimation] = [.lookingAround, .idleBreathing, .curious]
            if stretchUnlocked, restDuration >= 3 { options.append(.stretching) }
            return options.randomElement(using: &rng) ?? .idleBreathing
        default:
            return state.defaultAnimation
        }
    }
}

// MARK: - Walking pose

/// Layers a walk cycle over any base pose: a hop per step, a sway, a swinging
/// tail, and eyes on the way ahead. Eases in and out so legs join the resting
/// pose without a jump.
enum MeerkatWalk {
    static let easeSeconds = 0.3

    static func ramp(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, elapsed / easeSeconds, (duration - elapsed) / easeSeconds))
    }

    static func pose(base: MeerkatPose, elapsed: TimeInterval, duration: TimeInterval, speed: Double) -> MeerkatPose {
        let rate = max(1.2, speed / 18) // steps per second
        let beat = Double.pi * rate * elapsed
        let amount = ramp(elapsed: elapsed, duration: duration)
        var p = base
        p.lift += 9 * amount * abs(sin(beat))
        p.bodyLean += 5 * amount * sin(beat)
        p.tailSwing += 16 * amount * sin(beat + 1)
        p.headTilt += 3 * amount * sin(beat)
        // The art is mirrored when heading right, so "left" here is always forward.
        p.eyeLookX += (-0.9 - p.eyeLookX) * amount
        return p
    }
}

// MARK: - Running it

@MainActor
final class CompanionRoamer: ObservableObject {
    struct Configuration: Equatable {
        var bounds: CGRect
        var mode: CompanionRoamMode
        var state: CompanionState
        var stretchUnlocked: Bool
    }

    static let reactionDuration: TimeInterval = 2.6

    @Published private(set) var phase: RoamPhase

    private var configuration = Configuration(bounds: .zero, mode: .parked, state: .idle, stretchUnlocked: true)
    private var planner = CompanionRoamPlanner(bounds: .zero)
    private var task: Task<Void, Never>?
    private var hasPlaced = false
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        phase = .resting(at: .zero, since: clock(), clip: .idleBreathing, facing: .left)
    }

    func configure(_ new: Configuration) {
        let old = configuration
        configuration = new
        planner = CompanionRoamPlanner(bounds: new.bounds)

        if !hasPlaced {
            hasPlaced = true
            phase = .resting(at: planner.home, since: clock(), clip: new.state.defaultAnimation, facing: .left)
            restart()
            return
        }
        // A reaction finishes first; its follow-up already reads the latest configuration.
        if case .reacting = phase { return }
        if new.mode != old.mode || (new.mode == .parked && new.bounds != old.bounds) || task == nil {
            restart()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// A tap: stop where he is, hop, then carry on.
    func react() {
        if case .reacting = phase { return }
        let now = clock()
        task?.cancel()
        phase = .reacting(at: planner.clamped(phase.position(at: now)), since: now, facing: phase.facing)
        task = Task { [weak self] in
            await Self.pause(Self.reactionDuration)
            guard !Task.isCancelled, let self else { return }
            self.phase = .resting(
                at: self.phase.position(at: self.clock()), since: self.clock(),
                clip: .idleBreathing, facing: self.phase.facing
            )
            self.restart()
        }
    }

    private func restart() {
        task?.cancel()
        task = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        var rng = SystemRandomNumberGenerator()
        // Carry on from wherever he is now, so a mode change never teleports him.
        var here = planner.clamped(phase.position(at: clock()))
        var facing = phase.facing

        switch configuration.mode {
        case .parked:
            let home = planner.home
            if hypot(home.x - here.x, home.y - here.y) > 1 {
                let leg = planner.leg(from: here, to: home, speed: 60, now: clock())
                phase = .walking(leg)
                await Self.pause(leg.duration)
                guard !Task.isCancelled else { return }
                facing = leg.facing
            }
            phase = .resting(at: home, since: clock(), clip: configuration.state.defaultAnimation, facing: facing)

        case .walking(let speed):
            while !Task.isCancelled {
                let rest = planner.restDuration(using: &rng)
                let clip = planner.restClip(
                    for: configuration.state, restDuration: rest,
                    stretchUnlocked: configuration.stretchUnlocked, using: &rng
                )
                phase = .resting(at: here, since: clock(), clip: clip, facing: facing)
                await Self.pause(rest)
                guard !Task.isCancelled else { return }

                let leg = planner.nextLeg(from: here, speed: speed, now: clock(), using: &rng)
                phase = .walking(leg)
                await Self.pause(leg.duration)
                guard !Task.isCancelled else { return }
                here = leg.to
                facing = leg.facing
            }
        }
    }

    private static func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

// MARK: - Hiding him on screens that already show him

/// Screens that draw the companion themselves (its own page and settings) hold
/// this while visible, so two Milos never share a screen. Keyed by token so a
/// missed disappear can't leave him hidden for good.
@MainActor
final class CompanionRoamingGate: ObservableObject {
    static let shared = CompanionRoamingGate()
    @Published private(set) var holders: Set<UUID> = []

    var isHeld: Bool { !holders.isEmpty }
    func hold(_ token: UUID) { holders.insert(token) }
    func release(_ token: UUID) { holders.remove(token) }
}

private struct HidesRoamingCompanion: ViewModifier {
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { CompanionRoamingGate.shared.hold(token) }
            .onDisappear { CompanionRoamingGate.shared.release(token) }
    }
}

extension View {
    /// Use on any screen that already shows the companion large.
    func hidesRoamingCompanion() -> some View {
        modifier(HidesRoamingCompanion())
    }
}

// MARK: - View

/// Sits above Mivo's tabs. Empty space passes touches straight through; only
/// Milo himself is tappable.
struct CompanionRoamingOverlay: View {
    /// True while something else owns the screen (the first-run tutorial).
    var isSuppressed = false

    @ObservedObject private var companion = CompanionStateManager.shared
    @ObservedObject private var gate = CompanionRoamingGate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var roamer = CompanionRoamer()

    static let figureSize = CGSize(width: 58, height: 75)
    /// Hairline, 5pt padding and the 49pt tab row, plus a little air.
    static let tabBarClearance: CGFloat = 62
    static let topClearance: CGFloat = 44
    static let edgeMargin: CGFloat = 8

    /// Where his feet may land inside a container of `size`; `nil` when it's too small to wander in.
    static func bounds(in size: CGSize) -> CGRect? {
        // Measured before building the rect: `CGRect.width` is always positive, which would hide a container that's too small.
        let width = size.width - figureSize.width - edgeMargin * 2
        let height = size.height - tabBarClearance - figureSize.height - topClearance
        guard width >= figureSize.width, height >= figureSize.height else { return nil }
        return CGRect(x: figureSize.width / 2 + edgeMargin, y: figureSize.height + topClearance, width: width, height: height)
    }

    private var isRoaming: Bool {
        let prefs = companion.preferences
        return prefs.isActive && prefs.roamingEnabled && prefs.animationsEnabled
            && !reduceMotion && scenePhase == .active && !isSuppressed && !gate.isHeld
    }

    var body: some View {
        GeometryReader { proxy in
            if isRoaming, let bounds = Self.bounds(in: proxy.size) {
                RoamingMilo(
                    roamer: roamer,
                    type: companion.preferences.companionType,
                    configuration: CompanionRoamer.Configuration(
                        bounds: bounds,
                        mode: CompanionRoamMode.mode(for: companion.presentation.state),
                        state: companion.presentation.state,
                        stretchUnlocked: companion.progress.isUnlocked(.stretching)
                    )
                )
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

private struct RoamingMilo: View {
    @ObservedObject var roamer: CompanionRoamer
    var type: CompanionType
    var configuration: CompanionRoamer.Configuration

    private var size: CGSize { CompanionRoamingOverlay.figureSize }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let now = timeline.date
            let position = clamped(roamer.phase.position(at: now))
            CompanionArtworkRegistry.figure(type: type, state: renderState, pose: pose(at: now))
                .scaleEffect(x: roamer.phase.facing == .right ? -1 : 1, y: 1)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticsService.selection()
                    roamer.react()
                }
                .offset(x: position.x - size.width / 2, y: position.y - size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { roamer.configure(configuration) }
        .onChange(of: configuration) { _, new in roamer.configure(new) }
        .onDisappear { roamer.stop() }
        .accessibilityHidden(true)
    }

    private var frameInterval: TimeInterval {
        switch roamer.phase {
        case .walking, .reacting: return 1.0 / 30
        case .resting: return configuration.mode == .parked ? 1.0 / 10 : 1.0 / 15
        }
    }

    /// Asleep or heads-down states don't walk, so a Milo heading to bed is awake until he gets there.
    private var renderState: CompanionState {
        if case .walking = roamer.phase, configuration.state.isSilent { return .idle }
        if case .reacting = roamer.phase { return .happy }
        return configuration.state
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CompanionRoamPlanner(bounds: configuration.bounds).clamped(point)
    }

    private func pose(at now: Date) -> MeerkatPose {
        let stretch = configuration.stretchUnlocked
        switch roamer.phase {
        case .resting(_, let since, let clip, _):
            return MeerkatMotion.pose(
                state: renderState, clip: clip, elapsed: now.timeIntervalSince(since), stretchUnlocked: stretch
            )
        case .walking(let leg):
            let elapsed = now.timeIntervalSince(leg.start)
            let base = MeerkatMotion.pose(
                state: renderState, clip: renderState.defaultAnimation, elapsed: elapsed, stretchUnlocked: false
            )
            return MeerkatWalk.pose(base: base, elapsed: elapsed, duration: leg.duration, speed: leg.speed)
        case .reacting(_, let since, _):
            return MeerkatMotion.pose(
                state: .happy, clip: .celebration, elapsed: now.timeIntervalSince(since), stretchUnlocked: stretch
            )
        }
    }
}
