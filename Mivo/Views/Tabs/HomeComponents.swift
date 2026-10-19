import SwiftUI

/// A day-over-day change in total device Screen Time.
///
/// Down is `kept` and up is `inkBody` rather than red — going over is not a
/// failure, and the palette has no alarm colour by design.
struct HomeScreenTimeComparison {
    let isDown: Bool
    let magnitudeText: String
    let referenceText: String

    var tint: Color { isDown ? MivoColors.kept : MivoColors.inkBody }
}

/// The seven-bar Screen Time sparkline. Bar heights are proportional to the
/// largest day in the window, so the shape is honest even when the week is flat.
///
/// Hidden below 393pt of width rather than compressed, per the accessibility
/// note in the handoff.
struct HomeSparkline: View {
    let values: [Int]

    private let barWidth: CGFloat = 7
    private let spacing: CGFloat = 4
    private let height: CGFloat = 52

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bars
            EmptyView()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screen time, last 7 days")
        .accessibilityValue(accessibilityValue)
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? MivoColors.accent : MivoColors.barTrack)
                    .frame(width: barWidth, height: barHeight(value))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func barHeight(_ value: Int) -> CGFloat {
        let peak = max(values.max() ?? 1, 1)
        // A floor of 6 keeps a zero day visible as a mark rather than nothing.
        return max(6, height * CGFloat(value) / CGFloat(peak))
    }

    private var accessibilityValue: String {
        guard let today = values.last else { return "" }
        return "Today \(formatDuration(today))"
    }
}

/// The vertical timeline of today's scrolling windows.
///
/// The rail is drawn behind the rows and each dot carries a `background`-coloured
/// ring so it masks the line rather than sitting on top of it.
struct HomePlanTimeline<Window: Identifiable>: View {
    enum WindowState {
        case done, next, later
    }

    let windows: [Window]
    let state: (Int) -> WindowState
    let title: (Window) -> String
    let meta: (Window) -> String
    var trailing: ((Int, Window) -> String)?

    private let railInset: CGFloat = 26
    private let dotSize: CGFloat = 11
    private let rowSpacing: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                row(index: index, window: window)
            }
        }
        .background(alignment: .topLeading) { rail }
    }

    private var rail: some View {
        Rectangle()
            .fill(MivoColors.hairline)
            .frame(width: 1.5)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .offset(x: 5)
    }

    private func row(index: Int, window: Window) -> some View {
        let windowState = state(index)
        return HStack(alignment: .top, spacing: 12) {
            dot(windowState)
                .frame(width: dotSize, height: dotSize)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title(window))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text(meta(window))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }

            Spacer(minLength: 8)

            trailingLabel(index: index, window: window, state: windowState)
        }
        .padding(.leading, railInset - dotSize - 10)
        .opacity(windowState == .later ? 0.68 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func dot(_ state: WindowState) -> some View {
        ZStack {
            if state == .next {
                Circle()
                    .fill(MivoColors.accent.opacity(0.18))
                    .frame(width: dotSize + 7, height: dotSize + 7)
            }
            Circle()
                .fill(fill(state))
                .overlay {
                    if state == .later {
                        Circle().strokeBorder(MivoColors.ink.opacity(0.28), lineWidth: 1.5)
                    }
                }
                // Masks the rail behind the dot.
                .overlay {
                    Circle().strokeBorder(MivoColors.background, lineWidth: 3)
                }
        }
    }

    private func fill(_ state: WindowState) -> Color {
        switch state {
        case .done: return MivoColors.kept
        case .next: return MivoColors.accent
        case .later: return MivoColors.background
        }
    }

    @ViewBuilder
    private func trailingLabel(index: Int, window: Window, state: WindowState) -> some View {
        if let trailing, case let text = trailing(index, window), !text.isEmpty {
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.kept)
                .fixedSize()
        } else {
            switch state {
            case .done:
                Text("Kept")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.kept)
                    .fixedSize()
            case .next:
                Text("NEXT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(Font.mivoTracking(0.09, at: 11))
                    .foregroundColor(MivoColors.deep)
                    .fixedSize()
            case .later:
                Text("Later")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize()
            }
        }
    }
}
