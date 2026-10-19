import SwiftUI

/// A dot bounces down through a peg field into six signed-time slots. Four
/// remove time from the next planned session and two add time that can be used
/// immediately. The genuine five-flip binomial path makes removal outcomes
/// 68.75% likely because the highest-probability center slots are negative.
struct DropPathGameView: View {
    let onFinished: (IntentGameResult) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let slots = DropPathSlot.allCases
    private static let pegRows = 5

    @State private var currentStep = 0
    @State private var xOffset: CGFloat = 0
    @State private var dropped = false
    @State private var finished = false
    @State private var landedSlot: DropPathSlot = .minusThreeLeft
    @State private var boardWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            oddsSummary
                .padding(.top, 18)
            Spacer(minLength: 14)
            board
                .frame(height: 244)
            slotRow
                .padding(.top, 10)
            Spacer(minLength: 24)
            if finished {
                resultPanel
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: prepareDrop) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            MivoEyebrow(text: "DROP PATH")
            Text("Where will your time land?")
                .font(.system(size: 24, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 24))
                .foregroundColor(MivoColors.ink)
            Text("Most paths trim your next planned session. A gain is ready to use as soon as it lands.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
        }
        .padding(.top, 4)
    }

    private var oddsSummary: some View {
        HStack(spacing: 10) {
            oddsItem(icon: "minus", title: "4 remove", detail: "Next session", color: MivoColors.ink)
            Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 34)
            oddsItem(icon: "plus", title: "2 add", detail: "Available now", color: MivoColors.kept)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MivoColors.surfaceV2)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }

    private func oddsItem(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "\(icon).circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var board: some View {
        GeometryReader { geo in
            ZStack {
                pegField
                Circle()
                    .fill(MivoColors.accent)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2))
                    .shadow(color: MivoColors.ink.opacity(0.22), radius: 7, y: 3)
                    .position(
                        x: geo.size.width / 2 + xOffset,
                        y: dropped ? rowY(currentStep, in: geo.size.height) : 14
                    )
            }
            .padding(.horizontal, 6)
            .background(
                LinearGradient(
                    colors: [MivoColors.surfaceRaised.opacity(0.72), MivoColors.surfaceV2.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
            .onAppear { boardWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, newValue in boardWidth = newValue }
        }
    }

    private var pegField: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<Self.pegRows, id: \.self) { row in
                    HStack(spacing: 28) {
                        ForEach(0...row, id: \.self) { _ in
                            Circle()
                                .fill(MivoColors.ink.opacity(0.22))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 30)
        }
    }

    private func rowY(_ step: Int, in height: CGFloat) -> CGFloat {
        let usable = height - 30
        return 14 + usable * CGFloat(step) / CGFloat(Self.pegRows)
    }

    private var slotRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.slots.enumerated()), id: \.offset) { index, slot in
                let isLanded = finished && slot == landedSlot
                VStack(spacing: 3) {
                    Text(slot.shortLabel)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(isLanded ? .white : (slot.isGain ? MivoColors.kept : MivoColors.inkBody))
                    Text(slot.isGain ? "NOW" : "NEXT")
                        .font(.system(size: 7.5, weight: .heavy))
                        .tracking(0.7)
                        .foregroundColor(isLanded ? .white.opacity(0.82) : MivoColors.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isLanded ? (slot.isGain ? MivoColors.kept : MivoColors.ink) : MivoColors.ink.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(slot.isGain && !isLanded ? MivoColors.kept.opacity(0.35) : .clear, lineWidth: 1)
                )
                .animation(MivoMotion.standard(0.25), value: finished)
                .accessibilityLabel("\(slot.isGain ? "Add" : "Remove") \(abs(slot.minutes)) minutes \(slot.isGain ? "now" : "from the next session")")
            }
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((landedSlot.isGain ? MivoColors.kept : MivoColors.ink).opacity(0.11))
                        .frame(width: 44, height: 44)
                    Image(systemName: landedSlot.isGain ? "plus" : "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(landedSlot.isGain ? MivoColors.kept : MivoColors.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(landedSlot.shortLabel)
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(landedSlot.isGain ? MivoColors.kept : MivoColors.ink)
                    Text(landedSlot.isGain ? "Available immediately" : "Applied to your next planned session")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
                Spacer()
            }
            MivoPrimaryButton(label: landedSlot.isGain ? "Use \(landedSlot.minutes) minutes now" : "Apply to next session") {
                onFinished(IntentGameResult.make(
                    gameType: .dropPath,
                    awardedMinutes: landedSlot.minutes,
                    outcomeLabel: landedSlot.label
                ))
            }
        }
        .padding(14)
        .background(MivoColors.surfaceRaised.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.hairline, lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func prepareDrop() {
        let steps = (0..<Self.pegRows).map { _ in Bool.random() ? 1 : -1 }
        let sum = steps.reduce(0, +)
        let index = (sum + Self.pegRows) / 2
        landedSlot = Self.slots[min(max(index, 0), Self.slots.count - 1)]
        animateDrop()
    }

    private func animateDrop() {
        dropped = true
        let slotWidth = boardWidth / CGFloat(Self.slots.count)
        let landedIndex = Self.slots.firstIndex(of: landedSlot) ?? 2
        let finalX = slotWidth * (CGFloat(landedIndex) + 0.5) - boardWidth / 2

        var xs: [CGFloat] = (1..<Self.pegRows).map { step in
            finalX * CGFloat(step) / CGFloat(Self.pegRows) + CGFloat.random(in: -16...16)
        }
        xs.append(finalX)

        for (offsetIndex, x) in xs.enumerated() {
            let step = offsetIndex + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.22) {
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 15)) {
                    currentStep = step
                    xOffset = x
                }
                HapticsService.impact(style: .light)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(xs.count) * 0.22 + 0.2) {
            if landedSlot.isGain {
                HapticsService.success()
            } else {
                HapticsService.impact(style: .medium)
            }
            withAnimation(MivoMotion.standard(0.3)) { finished = true }
        }
    }
}
