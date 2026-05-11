import WidgetKit
import SwiftUI

private let appGroup = "group.com.mivo.mivoapp"
private let widgetSummaryKey = "mivo_widget_shared_summary"

private struct WidgetSharedSummary: Codable {
    let recoveredMinutesToday: Int
    let screenTimeMinutesToday: Int?
    let nextScrollWindow: String
    let planState: String
    let streakText: String
    let updatedAt: String
}

private struct MivoWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSharedSummary
}

private struct MivoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MivoWidgetEntry {
        MivoWidgetEntry(date: Date(), summary: fallbackSummary)
    }

    func getSnapshot(in context: Context, completion: @escaping (MivoWidgetEntry) -> Void) {
        completion(MivoWidgetEntry(date: Date(), summary: loadSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MivoWidgetEntry>) -> Void) {
        let entry = MivoWidgetEntry(date: Date(), summary: loadSummary())
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSummary() -> WidgetSharedSummary {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: widgetSummaryKey),
              let summary = try? JSONDecoder().decode(WidgetSharedSummary.self, from: data) else {
            return fallbackSummary
        }
        return summary
    }

    private var fallbackSummary: WidgetSharedSummary {
        WidgetSharedSummary(
            recoveredMinutesToday: 0,
            screenTimeMinutesToday: nil,
            nextScrollWindow: "Open Mivo",
            planState: "Learning mode",
            streakText: "No sessions today",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

private struct MivoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MivoWidgetEntry
    
    private var scrolledMinutesToday: Int {
        entry.summary.screenTimeMinutesToday ?? 0
    }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mivo")
                .font(.headline)
            Text(formatMinutes(scrolledMinutesToday))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("scrolled today")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.summary.planState)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .containerBackground(Color(red: 0.95, green: 0.91, blue: 0.86), for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mivo")
                    .font(.headline)
                Text(formatMinutes(scrolledMinutesToday))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("scrolled today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.summary.nextScrollWindow, systemImage: "clock")
                Label(entry.summary.planState, systemImage: "target")
                Label(entry.summary.streakText, systemImage: "checkmark.seal")
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        }
        .containerBackground(Color(red: 0.95, green: 0.91, blue: 0.86), for: .widget)
    }

    private var accessoryCircular: some View {
        Gauge(value: Double(min(scrolledMinutesToday, 360)), in: 0...360) {
            Text("Mivo")
        } currentValueLabel: {
            Text("\(scrolledMinutesToday)m")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading) {
            Text("Mivo: \(formatMinutes(scrolledMinutesToday)) scrolled")
            Text(entry.summary.nextScrollWindow)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }
}

@main
struct MivoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MivoStatusWidget()
    }
}

struct MivoStatusWidget: Widget {
    let kind = "MivoStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MivoWidgetProvider()) { entry in
            MivoWidgetView(entry: entry)
        }
        .configurationDisplayName("Mivo")
        .description("Today's scroll time, next scroll window, and adaptive plan state.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
