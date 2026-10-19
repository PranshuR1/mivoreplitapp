import Foundation

/// A completed or abandoned Still session. Deliberately not a `Session` —
/// `Session.actualDuration` means minutes spent *in* a protected app, and this
/// is the opposite: minutes the phone was successfully left alone. Mixing the
/// two would corrupt every existing scrolling total that sums `sessions`.
struct MivoStillSession: Codable, Identifiable, Equatable {
    let id: String
    /// `MivoDay` key for the day the session started.
    let date: String
    let startedAt: String
    var endedAt: String?
    let plannedSeconds: Int
    var actualSeconds: Int
    /// 0 if the phone stayed face-down and still for the whole session, 1 if
    /// it was picked up and that ended the session early. Never higher —
    /// there is no grace period, so the first confirmed pickup is the only
    /// one that can ever happen.
    var pickupCount: Int
    var outcome: MivoStillOutcome
    /// Optional so sessions saved before Lock Mode existed still decode —
    /// a non-optional field with a default is not enough, since synthesized
    /// `Decodable` still requires the key to be present.
    var lockModeUsed: Bool? = nil
}

enum MivoStillOutcome: String, Codable {
    case completed
    /// No longer produced. Kept so sessions saved by earlier App Store builds
    /// still decode instead of failing to load.
    case chancesExhausted = "chances_exhausted"
    /// Ended immediately because the phone was picked up before the timer
    /// finished — there is no grace period to put it back and continue.
    case notReturned = "not_returned"
    /// The user backed out before the settle period ever completed — never
    /// really started, so it is not counted as an attempt.
    case abandoned
}

/// One reading from the motion monitor: gravity's z-component in the device's
/// own frame (≈ +1 when the screen faces straight down, ≈ −1 face up), and the
/// magnitude of acceleration with gravity removed (near 0 at rest, spikes on
/// any pickup or slide).
struct MivoStillSample: Equatable {
    let gravityZ: Double
    let userAccelerationMagnitude: Double
}

/// The full lifecycle of one attempt, from placing the phone down to a result.
///
/// There is deliberately no failure case. A session ends exactly one way —
/// the countdown reaching zero. Picking the phone up, moving it, or leaving
/// it face-up cannot end it early; those only change what the screen says.
enum MivoStillPhase: Equatable {
    /// Waiting for the phone to be face-down and still for `settleDuration`
    /// before the timer starts, so bumping it into place doesn't itself read
    /// as movement.
    case waitingToSettle(stillElapsed: TimeInterval)
    case active(remainingSeconds: Double, pickups: Int)
    /// Movement detected. Purely a nudge state — the countdown keeps running
    /// and the session keeps going. `counted` marks that this disturbance has
    /// already survived `violationDebounce` and been added to the pickup
    /// tally, so one long pickup counts once rather than once per sample.
    case disturbed(remainingSeconds: Double, pickups: Int, disturbedElapsed: TimeInterval, counted: Bool)
    case completed

    var isTerminal: Bool {
        if case .completed = self { return true }
        return false
    }

    var remainingSeconds: Double? {
        switch self {
        case .active(let remaining, _): return remaining
        case .disturbed(let remaining, _, _, _): return remaining
        case .waitingToSettle, .completed: return nil
        }
    }
}

/// Pure state machine driving a Still session from motion samples. Holds no
/// timers or device APIs itself, so every threshold and transition here is
/// exercised directly with synthetic samples rather than trusted on faith.
enum MivoStillEngine {
    /// Gravity's z-component above this reads as "face down." ~35° of tilt
    /// tolerance for a phone resting on an uneven surface.
    static let faceDownGravityThreshold = 0.82
    /// User-acceleration magnitude below this reads as "at rest."
    static let movementThreshold = 0.12
    static let settleDuration: TimeInterval = 2.0
    static let violationDebounce: TimeInterval = 1.2

    static func isStillFaceDown(_ sample: MivoStillSample) -> Bool {
        sample.gravityZ > faceDownGravityThreshold
            && sample.userAccelerationMagnitude < movementThreshold
    }

    /// Advances the phase by one motion sample. `dt` is wall-clock seconds
    /// since the previous call. `plannedSeconds` only takes effect at the
    /// moment settling completes; it is ignored afterward so a session's own
    /// remaining time is the source of truth.
    ///
    /// The countdown itself only moves while the phone is flat and still —
    /// picking it up freezes `remainingSeconds` exactly where it was, rather
    /// than continuing to burn planned time the phone spent in the air. It
    /// resumes the instant the phone is back down. Either way, nothing ever
    /// cuts a session short: the only way out is the frozen clock eventually
    /// reaching zero while flat.
    static func advance(
        phase: MivoStillPhase,
        sample: MivoStillSample,
        dt: TimeInterval,
        plannedSeconds: Double
    ) -> MivoStillPhase {
        guard dt > 0, !phase.isTerminal else { return phase }
        let stillNow = isStillFaceDown(sample)

        switch phase {
        case .waitingToSettle(let elapsed):
            guard stillNow else { return .waitingToSettle(stillElapsed: 0) }
            let newElapsed = elapsed + dt
            guard newElapsed >= settleDuration else {
                return .waitingToSettle(stillElapsed: newElapsed)
            }
            return .active(remainingSeconds: plannedSeconds, pickups: 0)

        case .active(let remaining, let pickups):
            guard stillNow else {
                // The clock freezes on the exact value it had the instant
                // stillness broke — dt from here on only measures how long
                // the phone has been up, not time taken off the timer.
                return .disturbed(
                    remainingSeconds: remaining,
                    pickups: pickups,
                    disturbedElapsed: dt,
                    counted: false
                )
            }
            let newRemaining = remaining - dt
            if newRemaining <= 0 { return .completed }
            return .active(remainingSeconds: newRemaining, pickups: pickups)

        case .disturbed(let remaining, let pickups, let disturbedElapsed, let counted):
            if stillNow {
                // Resumes from the frozen value — nothing was lost while it
                // was up, and nothing is refunded either.
                return .active(remainingSeconds: remaining, pickups: pickups)
            }
            let newDisturbedElapsed = disturbedElapsed + dt
            // Crossing the debounce is what turns a knock on the desk into a
            // recorded pickup. It still does not end anything, and the clock
            // stays frozen regardless of which side of the debounce this is.
            let crossed = !counted && newDisturbedElapsed >= violationDebounce
            return .disturbed(
                remainingSeconds: remaining,
                pickups: crossed ? pickups + 1 : pickups,
                disturbedElapsed: newDisturbedElapsed,
                counted: counted || crossed
            )

        case .completed:
            return phase
        }
    }
}
