import SwiftUI

// Vector meerkat, drawn with SwiftUI `Canvas`. Pure SwiftUI with no Mivo
// dependencies, so the widget target compiles this same file.
//
// Replacing the artwork later: either drop images named
// `companion_meerkat_<state>` into Assets.xcassets (they win automatically —
// see `CompanionArtworkRegistry`), or swap `MeerkatPainter.draw`.

// MARK: - Pose

/// Every adjustable part of the figure. Poses are plain values, which is what
/// makes the animation layer a pure function of (state, clip, time).
struct MeerkatPose: Equatable {
    var eyeOpen = 1.0        // 0 closed … 1 open
    var eyeLookX = 0.0       // -1 … 1
    var eyeLookY = 0.0
    var smile = 0.3          // -0.4 frown … 1 grin
    var browLift = 0.0       // -1 worried … 1 raised
    var headTilt = 0.0       // degrees
    var headDrop = 0.0       // 0 upright … 1 chin on chest
    var bodyLean = 0.0       // degrees
    var bodyStretch = 1.0    // torso height: 0.7 hunched … 1.12 stretched
    var armRaise = 0.0       // 0 paws on belly … 1 overhead
    var armOut = 0.0         // 0 … 1 spread wide
    var earBack = 0.0        // 0 … 1 ears flattened
    var tailSwing = 0.0      // degrees
    var lift = 0.0           // hop height in design units
    var sleepZ = 0.0         // 0 … 1 opacity of the z's

    func blended(to other: MeerkatPose, fraction f: Double) -> MeerkatPose {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return MeerkatPose(
            eyeOpen: mix(eyeOpen, other.eyeOpen), eyeLookX: mix(eyeLookX, other.eyeLookX),
            eyeLookY: mix(eyeLookY, other.eyeLookY), smile: mix(smile, other.smile),
            browLift: mix(browLift, other.browLift), headTilt: mix(headTilt, other.headTilt),
            headDrop: mix(headDrop, other.headDrop), bodyLean: mix(bodyLean, other.bodyLean),
            bodyStretch: mix(bodyStretch, other.bodyStretch), armRaise: mix(armRaise, other.armRaise),
            armOut: mix(armOut, other.armOut), earBack: mix(earBack, other.earBack),
            tailSwing: mix(tailSwing, other.tailSwing), lift: mix(lift, other.lift),
            sleepZ: mix(sleepZ, other.sleepZ)
        )
    }
}

// MARK: - Motion

/// Maps (state, clip, time) to a pose. No timers, no state — the view samples
/// it from a `TimelineView`, and tests call it directly.
enum MeerkatMotion {
    /// The resting posture for a state — also what Reduce Motion shows.
    static func staticPose(for state: CompanionState) -> MeerkatPose {
        var p = MeerkatPose()
        switch state {
        case .idle:
            p.smile = 0.35; p.browLift = 0.1
        case .happy:
            p.smile = 0.9; p.browLift = 0.5; p.headTilt = 4; p.armRaise = 0.15; p.tailSwing = 6
        case .curious:
            p.headTilt = 10; p.browLift = 0.7; p.eyeLookX = 0.35; p.eyeLookY = -0.1
            p.bodyStretch = 1.06; p.smile = 0.25
        case .watching:
            p.bodyStretch = 1.1; p.smile = 0.1; p.browLift = 0.2
        case .tired:
            p.eyeOpen = 0.4; p.smile = 0.1; p.headDrop = 0.5; p.bodyStretch = 0.88
            p.headTilt = -6; p.browLift = -0.2
        case .concerned:
            p.browLift = -0.7; p.smile = -0.2; p.headTilt = 6; p.earBack = 0.6; p.bodyLean = 2
        case .focused:
            p.eyeOpen = 0.7; p.smile = 0.05; p.bodyStretch = 1.04; p.eyeLookY = 0.1; p.browLift = -0.1
        case .celebrating:
            p.armRaise = 1; p.armOut = 0.6; p.smile = 1; p.browLift = 0.9; p.bodyStretch = 1.06
        case .intervening:
            p.bodyStretch = 1.04; p.smile = 0.35; p.browLift = 0.2; p.armRaise = 0.1
        case .resting:
            p.eyeOpen = 0.55; p.smile = 0.5; p.headDrop = 0.25; p.bodyStretch = 0.92
        case .sleeping:
            p.eyeOpen = 0; p.smile = 0.2; p.headDrop = 1; p.bodyStretch = 0.7; p.sleepZ = 1
        }
        return p
    }

    /// `elapsed` is seconds since the clip started. Looping clips are periodic;
    /// one-shots (`blink`, `stretching`, `celebration`) settle back to the base
    /// posture when they finish.
    static func pose(
        state: CompanionState,
        clip: CompanionAnimation,
        elapsed t: TimeInterval,
        stretchUnlocked: Bool = true
    ) -> MeerkatPose {
        var p = staticPose(for: state)
        let tau = 2 * Double.pi

        func breathe(period: Double, amount: Double) {
            p.bodyStretch += amount * sin(tau * t / period)
            p.headDrop += amount * 2 * sin(tau * t / period)
        }
        func blink(period: Double, offset: Double) {
            let phase = (t + offset).truncatingRemainder(dividingBy: period)
            if phase < 0.16 { p.eyeOpen *= 1 - sin(Double.pi * phase / 0.16) }
        }
        func glance(period: Double, duration: Double, amount: Double) {
            let phase = t.truncatingRemainder(dividingBy: period)
            guard phase < duration else { return }
            p.eyeLookX = amount * sin(Double.pi * phase / duration) * (Int(t / period) % 2 == 0 ? 1 : -1)
        }
        func eased(_ x: Double) -> Double { x * x * (3 - 2 * x) }

        switch clip {
        case .idleBreathing:
            breathe(period: 4, amount: 0.012)
            blink(period: 4.7, offset: 1.3)
            glance(period: 11, duration: 2.2, amount: 0.8)
            if stretchUnlocked, state == .idle {
                let phase = t.truncatingRemainder(dividingBy: 34)
                if phase > 28, phase < 30.6 { return stretch(p, at: phase - 28) }
            }
        case .blink:
            let phase = t.truncatingRemainder(dividingBy: 1.6)
            if phase < 0.18 { p.eyeOpen *= 1 - sin(Double.pi * phase / 0.18) }
        case .stretching:
            return stretch(p, at: t)
        case .lookingAround:
            breathe(period: 4.4, amount: 0.008)
            p.eyeLookX = 0.9 * sin(tau * t / 6)
            p.headTilt += 4 * sin(tau * t / 6 + 0.6)
            blink(period: 5.3, offset: 0.8)
        case .curious:
            p.headTilt += 4 * sin(tau * t / 3.2)
            p.browLift += 0.15 * sin(tau * t / 3.2)
            p.eyeLookX = 0.4 * sin(tau * t / 5)
            breathe(period: 3.6, amount: 0.01)
            blink(period: 4.1, offset: 0.4)
        case .tired:
            breathe(period: 6, amount: 0.02)
            p.eyeOpen = max(0.15, p.eyeOpen + 0.18 * sin(tau * t / 7))
            p.headDrop = min(1, max(0, p.headDrop + 0.18 * sin(tau * t / 9)))
        case .sleeping:
            breathe(period: 5, amount: 0.018)
            p.sleepZ = 0.55 + 0.45 * (0.5 + 0.5 * sin(tau * t / 3.4))
        case .focused:
            breathe(period: 5, amount: 0.005)
            blink(period: 7, offset: 2)
        case .celebration:
            let settle = 2.6
            if t < settle {
                let decay = 1 - t / settle
                p.lift = 18 * decay * abs(sin(Double.pi * t / 0.55))
                p.armOut = 0.45 + 0.25 * sin(tau * t * 1.8)
                p.tailSwing = 14 * sin(tau * t * 1.4)
            } else {
                p = staticPose(for: .happy)
                breathe(period: 4, amount: 0.01)
            }
        case .intervention:
            breathe(period: 4.2, amount: 0.01)
            p.headTilt += 2.5 * sin(tau * t / 6)
            blink(period: 5.5, offset: 1.1)
        }

        if state == .celebrating, clip != .celebration { p.armOut = 0.45 + 0.2 * sin(tau * t * 1.8) }
        return p
    }

    private static func stretch(_ base: MeerkatPose, at t: Double) -> MeerkatPose {
        var p = base
        let duration = 2.6
        guard t < duration else { return p }
        let x = t / duration
        let envelope = sin(Double.pi * x)                // 0 → 1 → 0
        let e = envelope * envelope * (3 - 2 * envelope) // eased
        p.armRaise = e
        p.armOut = 0.35 * e
        p.bodyStretch += 0.1 * e
        p.eyeOpen *= 1 - 0.85 * e
        p.headDrop -= 0.25 * e
        p.smile += 0.3 * e
        return p
    }
}

// MARK: - Painter

struct MeerkatCanvas: View {
    var pose: MeerkatPose

    var body: some View {
        Canvas { context, size in
            MeerkatPainter.draw(pose, in: context, size: size)
        }
        .aspectRatio(MeerkatPainter.designSize.width / MeerkatPainter.designSize.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum MeerkatPainter {
    static let designSize = CGSize(width: 200, height: 260)

    private enum Palette {
        static let fur = Color(meerkat: 0xCFA970)
        static let furShade = Color(meerkat: 0xB08650)
        static let face = Color(meerkat: 0xF3E6C8)
        static let belly = Color(meerkat: 0xF0DFBB)
        static let bellyPatch = Color(meerkat: 0xB89468)
        static let mask = Color(meerkat: 0x4A3322)
        static let ink = Color(meerkat: 0x140D07)
        static let nose = Color(meerkat: 0x2A1B10)
        static let earInner = Color(meerkat: 0x8A6847)
    }

    private static let floorY = 240.0

    static func draw(_ pose: MeerkatPose, in context: GraphicsContext, size: CGSize) {
        let scale = min(size.width / designSize.width, size.height / designSize.height)
        var root = context
        root.translateBy(x: (size.width - designSize.width * scale) / 2, y: (size.height - designSize.height * scale) / 2)
        root.scaleBy(x: scale, y: scale)

        let s = pose.bodyStretch
        let xs = 1 + (1 - s) * 0.35
        let torso = CGAffineTransform(translationX: 100, y: floorY).scaledBy(x: xs, y: s).translatedBy(x: -100, y: -floorY)
        func tp(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(torso) }

        // Contact shadow stays on the ground while the body hops.
        let shadowWidth = 96 - pose.lift * 1.2
        root.fill(
            Path(ellipseIn: CGRect(x: 100 - shadowWidth / 2, y: floorY - 2, width: shadowWidth, height: 12)),
            with: .color(.black.opacity(0.13 - min(pose.lift, 18) * 0.002))
        )

        var body = root
        body.translateBy(x: 0, y: -pose.lift)
        body.translateBy(x: 100, y: floorY)
        body.rotate(by: .degrees(pose.bodyLean))
        body.translateBy(x: -100, y: -floorY)

        // Tail
        var tail = body
        tail.translateBy(x: 126, y: 232)
        tail.rotate(by: .degrees(pose.tailSwing))
        tail.translateBy(x: -126, y: -232)
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: 126, y: 232))
        tailPath.addQuadCurve(to: CGPoint(x: 174, y: 198), control: CGPoint(x: 170, y: 240))
        tail.stroke(tailPath, with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        tail.fill(Path(ellipseIn: CGRect(x: 169.5, y: 193.5, width: 9, height: 9)), with: .color(Palette.mask))

        // Feet
        for x in [79.0, 121.0] {
            body.fill(Path(ellipseIn: CGRect(x: x - 16, y: floorY - 8, width: 32, height: 15)), with: .color(Palette.furShade))
        }

        // Torso + belly
        var torsoPath = Path()
        torsoPath.move(to: CGPoint(x: 84, y: 104))
        torsoPath.addCurve(to: CGPoint(x: 60, y: 170), control1: CGPoint(x: 70, y: 112), control2: CGPoint(x: 58, y: 140))
        torsoPath.addCurve(to: CGPoint(x: 74, y: 238), control1: CGPoint(x: 62, y: 200), control2: CGPoint(x: 62, y: 226))
        torsoPath.addLine(to: CGPoint(x: 126, y: 238))
        torsoPath.addCurve(to: CGPoint(x: 140, y: 170), control1: CGPoint(x: 138, y: 226), control2: CGPoint(x: 138, y: 200))
        torsoPath.addCurve(to: CGPoint(x: 116, y: 104), control1: CGPoint(x: 142, y: 140), control2: CGPoint(x: 130, y: 112))
        torsoPath.closeSubpath()
        body.fill(torsoPath.applying(torso), with: .color(Palette.fur))
        body.fill(Path(ellipseIn: CGRect(x: 75, y: 128, width: 50, height: 100)).applying(torso), with: .color(Palette.belly))
        body.fill(Path(ellipseIn: CGRect(x: 84, y: 176, width: 32, height: 42)).applying(torso), with: .color(Palette.bellyPatch.opacity(0.55)))

        // Head position follows the torso top.
        let headY = floorY - 162 * s + 16 * pose.headDrop

        // Arms
        let up = pose.armRaise
        for side in [-1.0, 1.0] {
            let shoulder = tp(100 + side * 29, 130)
            let rest = tp(100 + side * 11, 172)
            let raised = CGPoint(x: 100 + side * 40, y: headY - 6)
            var paw = CGPoint(x: rest.x + (raised.x - rest.x) * up, y: rest.y + (raised.y - rest.y) * up)
            paw.x += side * 22 * pose.armOut
            var arm = Path()
            arm.move(to: shoulder)
            arm.addQuadCurve(
                to: paw,
                control: CGPoint(x: (shoulder.x + paw.x) / 2 + side * (10 + 8 * up), y: (shoulder.y + paw.y) / 2)
            )
            body.stroke(arm, with: .color(Palette.fur), style: StrokeStyle(lineWidth: 13, lineCap: .round))
            body.fill(Path(ellipseIn: CGRect(x: paw.x - 6.5, y: paw.y - 6, width: 13, height: 12)), with: .color(Palette.mask))
        }

        drawHead(pose, in: body, center: CGPoint(x: 100, y: headY))

        if pose.sleepZ > 0.01 {
            let sizes: [(CGFloat, CGFloat, CGFloat, Double)] = [(150, -40, 19, 1), (163, -58, 14, 0.7), (173, -72, 10, 0.45)]
            for (x, dy, fontSize, weight) in sizes {
                body.draw(
                    Text("z").font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundColor(Palette.furShade.opacity(pose.sleepZ * weight)),
                    at: CGPoint(x: x, y: headY + dy)
                )
            }
        }
    }

    private static func drawHead(_ pose: MeerkatPose, in body: GraphicsContext, center: CGPoint) {
        var head = body
        head.translateBy(x: center.x, y: center.y)
        head.translateBy(x: 0, y: 34)
        head.rotate(by: .degrees(pose.headTilt))
        head.translateBy(x: 0, y: -34)

        // Ears
        for side in [-1.0, 1.0] {
            var ear = head
            ear.translateBy(x: side * (37 + pose.earBack * 3), y: -14 + pose.earBack * 7)
            ear.rotate(by: .degrees(side * (18 + pose.earBack * 22)))
            ear.fill(Path(ellipseIn: CGRect(x: -8.5, y: -12, width: 17, height: 24)), with: .color(Palette.mask))
            ear.fill(Path(ellipseIn: CGRect(x: -4.5, y: -7, width: 9, height: 15)), with: .color(Palette.earInner.opacity(0.8)))
        }

        head.fill(Path(ellipseIn: CGRect(x: -37, y: -33, width: 74, height: 66)), with: .color(Palette.fur))
        head.fill(Path(ellipseIn: CGRect(x: -30, y: -14, width: 60, height: 50)), with: .color(Palette.face))

        // Eye patches and eyes
        let lookX = pose.eyeLookX * 3, lookY = pose.eyeLookY * 2.5
        for side in [-1.0, 1.0] {
            var patch = head
            patch.translateBy(x: side * 20, y: -2)
            patch.rotate(by: .degrees(side * -14))
            patch.fill(Path(ellipseIn: CGRect(x: -11, y: -14, width: 22, height: 28)), with: .color(Palette.mask))

            let open = max(0, min(1, pose.eyeOpen))
            if open < 0.12 {
                var lid = Path()
                lid.move(to: CGPoint(x: side * 20 - 6, y: 0))
                lid.addQuadCurve(to: CGPoint(x: side * 20 + 6, y: 0), control: CGPoint(x: side * 20, y: 4))
                head.stroke(lid, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            } else {
                let h = 12 * open
                let eye = CGRect(x: side * 20 + lookX - 6, y: lookY - h / 2, width: 12, height: h)
                head.fill(Path(ellipseIn: eye), with: .color(Palette.ink))
                if open > 0.45 {
                    head.fill(
                        Path(ellipseIn: CGRect(x: eye.minX + 6.5, y: eye.minY + h * 0.2, width: 3.6, height: 3.6)),
                        with: .color(.white.opacity(0.92))
                    )
                }
            }

            // Brows: worried slants up toward the nose, raised arches higher.
            let worry = max(0, -pose.browLift), raise = max(0, pose.browLift)
            var brow = Path()
            let baseY = -19 - raise * 4
            brow.move(to: CGPoint(x: side * 20 + side * 8, y: baseY + worry * 3))
            brow.addQuadCurve(
                to: CGPoint(x: side * 20 - side * 8, y: baseY - worry * 4.5),
                control: CGPoint(x: side * 20, y: baseY - 2 - raise * 2)
            )
            head.stroke(brow, with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }

        // Snout, nose, mouth
        head.fill(Path(ellipseIn: CGRect(x: -13, y: 7, width: 26, height: 21)), with: .color(Palette.face))
        var nose = Path()
        nose.move(to: CGPoint(x: -6.5, y: 10))
        nose.addQuadCurve(to: CGPoint(x: 6.5, y: 10), control: CGPoint(x: 0, y: 7))
        nose.addQuadCurve(to: CGPoint(x: 0, y: 19), control: CGPoint(x: 6.5, y: 16))
        nose.addQuadCurve(to: CGPoint(x: -6.5, y: 10), control: CGPoint(x: -6.5, y: 16))
        head.fill(nose, with: .color(Palette.nose))

        let smile = max(-0.4, min(1, pose.smile))
        var mouth = Path()
        mouth.move(to: CGPoint(x: -8, y: 24))
        mouth.addQuadCurve(to: CGPoint(x: 8, y: 24), control: CGPoint(x: 0, y: 24 + 9 * smile))
        head.stroke(mouth, with: .color(Palette.nose.opacity(0.85)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }
}

private extension Color {
    init(meerkat hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
