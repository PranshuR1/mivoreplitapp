import WidgetKit
import SwiftUI

private let appGroup = "group.com.mivo.mivoapp"
private let widgetSummaryKey = "mivo_widget_shared_summary"

// Must match the WidgetSharedSummary in Models.swift
struct WidgetSharedSummary: Codable {
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
    let hasData: Bool
}

private struct MivoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MivoWidgetEntry {
        when the timer ends, the app NEEDS TO CLOSE THAT SECOND, or automatically open mivo on your own, and lock it there. u cannot get out of it until you finish the session n        MivoWidgetEntry(date: Date(), summary: fallbackSummary, hasData: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MivoWidgetEntry) -> Void) {
        let (summary, hasData) = loadSummary()
        completion(MivoWidgetEntry(date: Date(), summary: summary, hasData: hasData))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MivoWidgetEntry>) -> Void) {
        let (summary, hasData) = loadSummary()
        let entry = MivoWidgetEntry(date: Date(), summary: summary, hasData: hasData)
        
        // Request more frequent updates if we have no data
        let refreshInterval = hasData ? 5 : 1
        let next = Calendar.current.date(byAdding: .minute, value: refreshInterval, to: Date()) ?? Date()
        
        print("[MivoWidget] Timeline update - hasData: \(hasData), next refresh: \(refreshInterval)m")
        
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSummary() -> (WidgetSharedSummary, Bool) {
        // Try app group first
        if let defaults = UserDefaults(suiteName: appGroup) {
            print("[MivoWidget] App group defaults loaded")
            
            if let data = defaults.data(forKey: widgetSummaryKey) {
                print("[MivoWidget] Found data in app group, size: \(data.count) bytes")
                
                if let summary = try? JSONDecoder().decode(WidgetSharedSummary.self, from: data) {
                    print("[MivoWidget] Successfully decoded: \(summary.screenTimeMinutesToday ?? 0)m scrolled")
                    return (summary, true)
                } else {
                    print("[MivoWidget] Failed to decode data")
                }
            } else {
                print("[MivoWidget] No data found in app group for key: \(widgetSummaryKey)")
                
                // Debug: print all keys in the app group
                let allKeys = defaults.dictionaryRepresentation().keys
                print("[MivoWidget] Available keys in app group: \(allKeys)")
            }
        } else {
            print("[MivoWidget] Failed to load app group UserDefaults: \(appGroup)")
        }
        
        print("[MivoWidget] Using fallback data")
        return (fallbackSummary, false)
    }

    private var fallbackSummary: WidgetSharedSummary {
        WidgetSharedSummary(
            recoveredMinutesToday: 0,
            screenTimeMinutesToday: 0,
            nextScrollWindow: "Open Mivo to start",
            planState: "Tap to open Mivo",
            streakText: "No data yet",
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
        Group {
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
        .widgetURL(URL(string: "mivo://home"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mivo")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
                Spacer()
                if !entry.hasData {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Text(formatMinutes(scrolledMinutesToday))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
            
            Text(entry.hasData ? "scrolled today" : "no data yet")
                .font(.caption)
                .foregroundColor(Color(red: 0.71, green: 0.38, blue: 0.12).opacity(0.7))
            
            Spacer()
            
            Text(entry.summary.planState)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color(red: 0.71, green: 0.38, blue: 0.12))
                .lineLimit(1)
        }
        .padding(16)
        .widgetBackground(Color(red: 0.95, green: 0.91, blue: 0.86))
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mivo")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
                    if !entry.hasData {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                Text(formatMinutes(scrolledMinutesToday))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
                
                Text(entry.hasData ? "scrolled today" : "no data yet")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.71, green: 0.38, blue: 0.12).opacity(0.7))
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.summary.nextScrollWindow, systemImage: "clock")
                Label(entry.summary.planState, systemImage: "target")
                Label(entry.summary.streakText, systemImage: "checkmark.seal")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(Color(red: 0.71, green: 0.38, blue: 0.12))
            .lineLimit(1)
        }
        .padding(16)
        .widgetBackground(Color(red: 0.95, green: 0.91, blue: 0.86))
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
// MARK: - Widget Background Helper
extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

