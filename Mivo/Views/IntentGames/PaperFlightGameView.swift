import SwiftUI

/// A screen-time flight inspired by Aviamasters' altitude-changing modifier
/// path. Signed circles scroll into the plane, update its onboard minutes, and
/// visibly bend the trajectory up or down. One uniformly seeded round in six
/// reaches the carrier; the remaining paths end in a rocket or water loss.
struct PaperFlightGameView: View {
    let onFinished: (IntentGameResult) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let flightDuration: TimeInterval = 8.7
    private static let eventTimes: [TimeInterval] = [1.0, 2.15, 3.3, 4.45, 5.6, 6.75]
    private static let startingAltitude = 0.18

    @State private var phase: PaperFlightPhase = .ready
    @State private var elapsed: TimeInterval = 0
    @State private var accumulatedMinutes = PaperFlightRewards.startingMinutes
    @State private var altitude = Self.startingAltitude
    @State private var nextEventIndex = 0
    @State private var flightEvents: [PaperFlightEvent] = []
    @State private var hitEventIDs: Set<UUID> = []
    @State private var latestModifier: PaperFlightModifier?
    @State private var modifierPulse = false
    @State private var lastAltitudeDelta = 0.0
    @State private var roundWillLand = false
    @State private var loss: PaperFlightLoss = .rocketStrike
    @State private var crashTime: TimeInterval = 6.2
    @State private var outcome: PaperFlightOutcome?

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var progress: Double {
        min(1, max(0, elapsed / Self.flightDuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            oddsStrip
                .padding(.top, 12)
            flightConsole
                .padding(.top, 14)
            statusLine
                .padding(.top, 12)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 14)
            bottomPanel
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .onReceive(timer) { _ in tick() }
        .onAppear(perform: prepareRound)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .disabled(phase == .flying)
                .opacity(phase == .flying ? 0.3 : 1)
                Spacer()
                MivoBadge(
                    text: "1 IN 6 WIN",
                    background: MivoColors.info.opacity(0.13),
                    foreground: MivoColors.info,
                    size: 8.5
                )
            }
            MivoEyebrow(text: "PAPER FLIGHT · ALTITUDE RUN")
            Text("Catch boosts. Climb higher.")
                .font(.system(size: 24, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 24))
                .foregroundColor(MivoColors.ink)
            Text("Every circle changes your screen time and flight height. Stay above the water to reach the carrier.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }

    private var oddsStrip: some View {
        HStack(spacing: 9) {
            legend(value: "+5–10m", label: "Land", color: MivoColors.kept)
            Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 28)
            legend(value: "−3m", label: "Rocket", color: MivoColors.inkBody)
            Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 28)
            legend(value: "−5m", label: "Water", color: MivoColors.ink)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(MivoColors.surfaceV2)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(RoundedRectangle(cornerRadius: MivoMetrics.radius).strokeBorder(MivoColors.hairline, lineWidth: 1))
    }

    private func legend(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var flightConsole: some View {
        VStack(spacing: 0) {
            consoleHeader
            flightScene
            distanceTrack
        }
        .background(Color(hex: "#10263B"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: MivoColors.ink.opacity(0.18), radius: 16, y: 9)
    }

    private var consoleHeader: some View {
        HStack(spacing: 0) {
            consoleStat(label: "ONBOARD", value: "\(accumulatedMinutes)m", alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 30)
            consoleStat(label: "ALTITUDE", value: "\(Int(altitude * 100))", alignment: .center)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 30)
            consoleStat(label: "DISTANCE", value: "\(Int(progress * 100))%", alignment: .trailing)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    private func consoleStat(label: String, value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.white.opacity(0.53))
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center)
    }

    private var flightScene: some View {
        GeometryReader { geo in
            let planeX = min(88.0, geo.size.width * 0.25)
            let speed = max(58.0, (geo.size.width - planeX + 46) / 3.25)
            let currentPlaneY = sceneY(for: altitude, height: geo.size.height)
            let carrierX = planeX + (Self.flightDuration - elapsed) * speed

            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#153955"), Color(hex: "#4C8297")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                altitudeGrid(height: geo.size.height)
                movingClouds(width: geo.size.width, height: geo.size.height)
                trajectory(toX: planeX, toY: currentPlaneY, height: geo.size.height)

                ForEach(flightEvents) { event in
                    let eventX = planeX + (event.time - elapsed) * speed
                    if eventX > -40, eventX < geo.size.width + 40, !hitEventIDs.contains(event.id) {
                        modifierCircle(event.modifier, isNear: abs(eventX - planeX) < 36)
                            .position(
                                x: eventX,
                                y: sceneY(for: event.approachAltitude, height: geo.size.height)
                            )
                    }
                }

                if loss == .rocketStrike, !roundWillLand, phase == .flying {
                    let rocketX = planeX + (crashTime - elapsed) * speed
                    if rocketX > -35, rocketX < geo.size.width + 40 {
                        rocket
                            .position(x: rocketX, y: currentPlaneY + 3)
                    }
                }

                if carrierX > -80, carrierX < geo.size.width + 100 {
                    carrier
                        .position(x: carrierX, y: geo.size.height - 24)
                }

                plane
                    .position(x: planeX, y: planeY(in: geo.size.height))

                if modifierPulse, let latestModifier {
                    hitEffect(latestModifier)
                        .position(x: planeX + 5, y: planeY(in: geo.size.height) - 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.75)))
                }

                water
            }
            .clipped()
        }
        .frame(height: 250)
    }

    private func altitudeGrid(height: CGFloat) -> some View {
        ZStack {
            ForEach(1..<4, id: \.self) { row in
                let y = height * CGFloat(row) / 4
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: 1000, y: y))
                }
                .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 7]))
                Text("\((4 - row) * 25)")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.25))
                    .position(x: 17, y: y - 8)
            }
        }
    }

    private func movingClouds(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            cloud(size: 34, opacity: 0.14)
                .position(x: wrappedX(width * 0.28 - CGFloat(progress) * width * 1.3, width: width), y: height * 0.24)
            cloud(size: 48, opacity: 0.10)
                .position(x: wrappedX(width * 0.75 - CGFloat(progress) * width * 1.7, width: width), y: height * 0.46)
            cloud(size: 28, opacity: 0.12)
                .position(x: wrappedX(width * 1.12 - CGFloat(progress) * width, width: width), y: height * 0.17)
        }
    }

    private func cloud(size: CGFloat, opacity: Double) -> some View {
        Image(systemName: "cloud.fill")
            .font(.system(size: size))
            .foregroundColor(.white.opacity(opacity))
    }

    private func wrappedX(_ value: CGFloat, width: CGFloat) -> CGFloat {
        let span = width + 90
        var x = value.truncatingRemainder(dividingBy: span)
        if x < -45 { x += span }
        return x
    }

    private func trajectory(toX: CGFloat, toY: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let startY = sceneY(for: Self.startingAltitude, height: height)
            path.move(to: CGPoint(x: -10, y: startY))
            path.addCurve(
                to: CGPoint(x: toX, y: toY),
                control1: CGPoint(x: toX * 0.30, y: startY),
                control2: CGPoint(x: toX * 0.72, y: toY)
            )
        }
        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
    }

    private func modifierCircle(_ modifier: PaperFlightModifier, isNear: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: modifier.isPositive
                            ? [Color(hex: "#79A66F"), Color(hex: "#3E7050")]
                            : [Color(hex: "#D36B58"), Color(hex: "#923E36")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 7).padding(4)
            Text(modifier.label)
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .frame(width: 53, height: 53)
        .scaleEffect(isNear ? 1.10 : 1)
        .shadow(color: modifier.color.opacity(0.45), radius: isNear ? 12 : 6)
        .animation(.easeInOut(duration: 0.16), value: isNear)
    }

    private var plane: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#10263B").opacity(0.42))
                .frame(width: 62, height: 62)
            Circle()
                .strokeBorder(.white.opacity(0.17), lineWidth: 1)
                .frame(width: 62, height: 62)
            Image(systemName: "airplane")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(planePitch))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
        }
        .scaleEffect(phase == .crashed ? 0.82 : 1)
        .animation(MivoMotion.standard(0.32), value: altitude)
        .animation(MivoMotion.standard(0.30), value: phase)
    }

    private var planePitch: Double {
        if phase == .crashed { return 48 }
        if phase == .landed { return 0 }
        if lastAltitudeDelta > 0.01 { return -16 }
        if lastAltitudeDelta < -0.01 { return 18 }
        return -4
    }

    private func hitEffect(_ modifier: PaperFlightModifier) -> some View {
        HStack(spacing: 5) {
            Image(systemName: modifier.isPositive ? "arrow.up.right" : "arrow.down.right")
            Text("\(modifier.label) · \(modifier.isPositive ? "CLIMB" : "DROP")")
        }
        .font(.system(size: 10, weight: .heavy))
        .monospacedDigit()
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(modifier.color)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: modifier.color.opacity(0.45), radius: 8)
    }

    private var rocket: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#F6C35B"))
                .offset(x: 20)
            Image(systemName: "capsule.portrait.fill")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(Color(hex: "#E7644E"))
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: Color(hex: "#E7644E").opacity(0.55), radius: 8)
    }

    private var carrier: some View {
        VStack(spacing: -2) {
            HStack(spacing: 3) {
                Text("LAND")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.white.opacity(0.8))
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#F1C15B"))
            }
            .offset(x: 13)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "#313C45"))
                .frame(width: 82, height: 11)
                .overlay(Rectangle().fill(.white.opacity(0.65)).frame(width: 35, height: 1))
            Trapezoid()
                .fill(Color(hex: "#1B252D"))
                .frame(width: 61, height: 14)
        }
    }

    private var water: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.28)).frame(height: 1)
            LinearGradient(
                colors: [Color(hex: "#2A6A86"), Color(hex: "#17445F")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 28)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var distanceTrack: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(phase == .landed ? MivoColors.kept : Color(hex: "#F1C15B"))
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: 6)
            HStack {
                Text("TAKEOFF")
                Spacer()
                Text("CARRIER")
            }
            .font(.system(size: 8, weight: .bold))
            .tracking(1)
            .foregroundColor(.white.opacity(0.48))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .ready:
            Text("Green circles climb · red circles drop")
                .foregroundColor(MivoColors.inkBody)
        case .flying:
            HStack(spacing: 8) {
                Circle().fill(MivoColors.kept).frame(width: 7, height: 7)
                Text("Automatic flight · watch the altitude path")
                    .foregroundColor(MivoColors.inkBody)
            }
        case .landed:
            Text("Carrier reached · onboard time secured")
                .foregroundColor(MivoColors.kept)
        case .crashed:
            Text(loss == .rocketStrike ? "Rocket impact forced the plane down" : "The plane dropped below the landing path")
                .foregroundColor(MivoColors.inkBody)
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if let outcome, phase == .landed || phase == .crashed {
            resultPanel(outcome)
        } else {
            MivoPrimaryButton(label: phase == .flying ? "Flight in progress…" : "Launch flight") {
                launch()
            }
            .disabled(phase == .flying)
            .opacity(phase == .flying ? 0.55 : 1)
        }
    }

    private func resultPanel(_ outcome: PaperFlightOutcome) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((outcome.playerWon ? MivoColors.kept : MivoColors.ink).opacity(0.11))
                        .frame(width: 44, height: 44)
                    Image(systemName: outcome.playerWon ? "airplane.arrival" : "calendar.badge.minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(outcome.playerWon ? MivoColors.kept : MivoColors.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(outcome.label)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text(outcome.playerWon ? "Flight time is available now" : "Removed from your next session")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
                Spacer()
                Text(outcome.minutes > 0 ? "+\(outcome.minutes)m" : "\(outcome.minutes)m")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(outcome.playerWon ? MivoColors.kept : MivoColors.ink)
            }

            MivoPrimaryButton(label: outcome.playerWon ? "Use time now" : "Apply to next session") {
                onFinished(
                    IntentGameResult.make(
                        gameType: .paperFlight,
                        awardedMinutes: outcome.minutes,
                        outcomeLabel: outcome.label
                    )
                )
            }
        }
        .padding(14)
        .background(MivoColors.surfaceRaised.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.hairline, lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func prepareRound() {
        roundWillLand = Int.random(in: 0..<6) == 0
        loss = PaperFlightLoss.allCases.randomElement() ?? .rocketStrike
        crashTime = loss == .rocketStrike ? 6.25 : Self.flightDuration
        elapsed = 0
        accumulatedMinutes = PaperFlightRewards.startingMinutes
        altitude = Self.startingAltitude
        nextEventIndex = 0
        hitEventIDs = []
        latestModifier = nil
        modifierPulse = false
        lastAltitudeDelta = 0
        outcome = nil
        phase = .ready
        flightEvents = makeFlightEvents()
    }

    private func launch() {
        guard phase == .ready else { return }
        HapticsService.impact(style: .medium)
        withAnimation(MivoMotion.standard(0.24)) { phase = .flying }
    }

    private func tick() {
        guard phase == .flying else { return }
        elapsed = min(Self.flightDuration, elapsed + 0.05)

        while nextEventIndex < flightEvents.count,
              elapsed >= flightEvents[nextEventIndex].time,
              (roundWillLand || flightEvents[nextEventIndex].time < crashTime) {
            apply(flightEvents[nextEventIndex])
            nextEventIndex += 1
        }

        if !roundWillLand, elapsed >= crashTime {
            finishFlight(landedSafely: false)
        } else if roundWillLand, elapsed >= Self.flightDuration {
            finishFlight(landedSafely: true)
        }
    }

    private func apply(_ event: PaperFlightEvent) {
        guard !hitEventIDs.contains(event.id) else { return }
        hitEventIDs.insert(event.id)
        accumulatedMinutes = event.modifier.apply(to: accumulatedMinutes)
        latestModifier = event.modifier
        lastAltitudeDelta = event.modifier.altitudeDelta

        withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
            altitude = clampedAltitude(altitude + event.modifier.altitudeDelta)
            modifierPulse = true
        }
        HapticsService.impact(style: event.modifier.isPositive ? .medium : .heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(MivoMotion.standard(0.18)) { modifierPulse = false }
        }
    }

    private func finishFlight(landedSafely: Bool) {
        let resolved = PaperFlightRewards.outcome(
            landedSafely: landedSafely,
            accumulatedMinutes: accumulatedMinutes,
            loss: loss
        )
        outcome = resolved
        withAnimation(.spring(response: 0.58, dampingFraction: 0.76)) {
            elapsed = landedSafely ? Self.flightDuration : crashTime
            if !landedSafely { altitude = 0.01 }
            phase = landedSafely ? .landed : .crashed
        }
        if landedSafely {
            HapticsService.success()
        } else {
            HapticsService.impact(style: .heavy)
        }
    }

    private func makeFlightEvents() -> [PaperFlightEvent] {
        let modifiers: [PaperFlightModifier]
        if roundWillLand {
            modifiers = [
                [.plusFive, .plusTwo, .minusThree, .plusFive, .minusFive, .plusFive],
                [.plusTwo, .plusFive, .plusFive, .minusFive, .plusTwo, .plusFive],
                [.plusFive, .minusThree, .plusTwo, .plusFive, .minusFive, .plusFive]
            ].randomElement() ?? [.plusFive, .plusTwo, .minusThree, .plusFive, .minusFive, .plusFive]
        } else if loss == .waterCrash {
            modifiers = [
                [.plusTwo, .minusFive, .plusFive, .minusThree, .minusFive, .plusTwo],
                [.plusFive, .minusFive, .plusTwo, .minusThree, .minusFive, .plusTwo]
            ].randomElement() ?? [.plusTwo, .minusFive, .plusFive, .minusThree, .minusFive, .plusTwo]
        } else {
            modifiers = [.plusTwo, .plusFive, .minusThree, .plusFive, .minusFive, .plusTwo]
        }

        var simulatedAltitude = Self.startingAltitude
        return zip(Self.eventTimes, modifiers).map { time, modifier in
            let event = PaperFlightEvent(
                time: time,
                modifier: modifier,
                approachAltitude: simulatedAltitude
            )
            simulatedAltitude = clampedAltitude(simulatedAltitude + modifier.altitudeDelta)
            return event
        }
    }

    private func clampedAltitude(_ value: Double) -> Double {
        min(0.91, max(0.05, value))
    }

    private func sceneY(for altitude: Double, height: CGFloat) -> CGFloat {
        let skyHeight = max(1, height - 38)
        return 15 + skyHeight * CGFloat(1 - altitude)
    }

    private func planeY(in height: CGFloat) -> CGFloat {
        if phase == .landed { return height - 47 }
        if phase == .crashed { return height - 27 }
        return sceneY(for: altitude, height: height)
    }
}

private enum PaperFlightPhase: Equatable {
    case ready, flying, landed, crashed
}

private struct PaperFlightEvent: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let modifier: PaperFlightModifier
    let approachAltitude: Double
}

private enum PaperFlightModifier: Equatable {
    case plusTwo, plusFive, minusThree, minusFive

    var label: String {
        switch self {
        case .plusTwo: return "+2"
        case .plusFive: return "+5"
        case .minusThree: return "−3"
        case .minusFive: return "−5"
        }
    }

    var isPositive: Bool {
        switch self {
        case .plusTwo, .plusFive: return true
        case .minusThree, .minusFive: return false
        }
    }

    var altitudeDelta: Double {
        switch self {
        case .plusTwo: return 0.09
        case .plusFive: return 0.18
        case .minusThree: return -0.11
        case .minusFive: return -0.18
        }
    }

    var color: Color {
        isPositive ? Color(hex: "#4F8059") : Color(hex: "#A94A3C")
    }

    func apply(to value: Int) -> Int {
        switch self {
        case .plusTwo: return min(PaperFlightRewards.maximumLandingReward, value + 2)
        case .plusFive: return min(PaperFlightRewards.maximumLandingReward, value + 5)
        case .minusThree: return max(1, value - 3)
        case .minusFive: return max(1, value - 5)
        }
    }
}

private struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
