import SwiftUI

/// A one-shot burst of confetti from both sides of the screen. Draws itself
/// for a few seconds, then goes quiet. Never takes touches.
struct MivoConfettiView: View {
    var duration: TimeInterval = 4.0

    private struct Piece {
        let fromLeft: Bool
        let originY: CGFloat
        let speed: CGFloat
        let angle: CGFloat
        let size: CGSize
        let spin: Double
        let phase: Double
        let color: Color
        let isRound: Bool
        let delay: TimeInterval
    }

    private static let palette: [Color] = [
        MivoColors.accent,
        Color(hex: "#F2C46D"),
        Color(hex: "#FAF3E8"),
        MivoColors.kept,
        MivoColors.blue,
        Color(hex: "#E29A50"),
        Color(hex: "#D46A4A")
    ]

    private let pieces: [Piece]
    private let start = Date()

    init(duration: TimeInterval = 4.0) {
        self.duration = duration
        pieces = (0..<110).map { index in
            let fromLeft = index.isMultiple(of: 2)
            // Straight up is -90°; each side leans in toward the middle.
            let lean = CGFloat.random(in: 12...48)
            let angle = fromLeft ? -(90 - lean) : -(90 + lean)
            let side = CGFloat.random(in: 5...10)
            return Piece(
                fromLeft: fromLeft,
                originY: CGFloat.random(in: 0.50...0.70),
                speed: CGFloat.random(in: 520...980),
                angle: angle * .pi / 180,
                size: CGSize(width: side, height: Bool.random() ? side : side * 1.8),
                spin: Double.random(in: -9...9),
                phase: Double.random(in: 0...(2 * .pi)),
                color: Self.palette[index % Self.palette.count],
                isRound: index % 5 == 0,
                delay: TimeInterval.random(in: 0...0.35)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < duration else { return }

                let gravity: CGFloat = 820
                let drag: CGFloat = 1.7

                for piece in pieces {
                    let t = CGFloat(elapsed - piece.delay)
                    guard t > 0 else { continue }

                    // Velocity decays with drag; gravity keeps pulling down.
                    let travel = (1 - exp(-drag * t)) / drag
                    var x = (piece.fromLeft ? 0 : size.width) + cos(piece.angle) * piece.speed * travel
                    let y = size.height * piece.originY + sin(piece.angle) * piece.speed * travel + 0.5 * gravity * t * t
                    x += CGFloat(sin(Double(t) * 3 + piece.phase)) * 14 * min(t, 1.5)

                    guard y < size.height + 40 else { continue }

                    let fade = min(1, max(0, (duration - elapsed) / 0.8))
                    var layer = context
                    layer.opacity = fade
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(piece.spin * Double(t) + piece.phase))
                    // Flip as it tumbles so pieces flicker like paper.
                    let flip = CGFloat(cos(Double(t) * 6 + piece.phase))
                    layer.scaleBy(x: 1, y: max(0.15, abs(flip)))

                    let rect = CGRect(
                        x: -piece.size.width / 2, y: -piece.size.height / 2,
                        width: piece.size.width, height: piece.size.height
                    )
                    let path = piece.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    layer.fill(path, with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
