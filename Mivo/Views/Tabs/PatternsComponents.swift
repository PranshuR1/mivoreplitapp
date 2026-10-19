import SwiftUI

/// One day's bar in the Patterns bar chart.
struct PatternsBarPoint: Identifiable {
    let id: String
    let label: String
    let minutes: Int
    let isToday: Bool
}

/// §2.2 bar chart. Equal-width bars, gap 10 at 7 days / 3 at 30, heights relative
/// to the tallest bar in the range so the shape stays honest.
struct PatternsBarChart: View {
    let points: [PatternsBarPoint]
    let range: PatternsRange
    private let height: CGFloat = 132

    var body: some View {
        HStack(alignment: .bottom, spacing: range == .week ? 10 : 3) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(point.isToday ? MivoColors.accent : MivoColors.barTrack)
                        .frame(height: barHeight(point.minutes))
                        .frame(maxHeight: height, alignment: .bottom)
                    if showsLabel(index: index) {
                        Text(point.label)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(MivoColors.inkMuted)
                            .fixedSize()
                    } else {
                        Text(" ")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(MivoMotion.progressFill, value: points.map(\.minutes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scrolling by day")
        .accessibilityValue(points.last.map { "Today \(formatDuration($0.minutes))" } ?? "")
    }

    private func barHeight(_ minutes: Int) -> CGFloat {
        let peak = max(points.map(\.minutes).max() ?? 1, 1)
        return max(3, height * CGFloat(minutes) / CGFloat(peak))
    }

    /// 7-day labels show every weekday; 30-day labels only every 7th day and the
    /// last, so they don't collide at 3pt bar gaps.
    private func showsLabel(index: Int) -> Bool {
        guard range == .month else { return true }
        return index == points.count - 1 || index % 7 == 0
    }
}

enum PatternsRange: Int, CaseIterable {
    case week = 7
    case month = 30

    var label: String { self == .week ? "7 days" : "30 days" }
}

/// §2.4 "What Mivo noticed" — a coloured dot plus a sentence with the key figure
/// at Semibold weight.
struct PatternsNoticedRow: View {
    let dotColor: Color
    let text: AttributedString

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .lineSpacing(0.55 * 13.5)
        }
    }
}
