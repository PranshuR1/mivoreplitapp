import WidgetKit
import SwiftUI
import ActivityKit

private let appGroup = "group.com.mivo.mivoapp"
private let widgetSummaryKey = "mivo_widget_shared_summary"
private let experimentEnforcedKey = "mivo.experiment.enforced"
private let experimentTypeKey = "mivo.experiment.type"
private let experimentEndsAtKey = "mivo.experiment.endsAt"

private func activeExperimentBlocksExtensions() -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroup),
          defaults.bool(forKey: experimentEnforcedKey),
          defaults.string(forKey: experimentTypeKey) == "reduce_extensions" else { return false }
    let endsAt = defaults.double(forKey: experimentEndsAtKey)
    return endsAt <= 0 || endsAt > Date().timeIntervalSince1970
}

// Must match the WidgetSharedSummary in Models.swift
struct WidgetSharedSummary: Codable {
    let recoveredMinutesToday: Int
    let screenTimeMinutesToday: Int?
    let nextScrollWindow: String
    let planState: String
    let streakText: String
    let updatedAt: String
    let appVersion: String?
    let focusedMinutesToday: Int?
}

// MARK: - Live Activity attributes
// MivoSessionLiveAttributes is defined in Mivo/Constants/MivoLiveActivityAttributes.swift.
// That file must be added to the MivoWidgets target membership in Xcode.
// See the comment in that file for setup instructions.

// MARK: - Home screen widget

private struct MivoWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSharedSummary
    let hasData: Bool
}

private struct MivoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MivoWidgetEntry {
        MivoWidgetEntry(date: Date(), summary: fallbackSummary, hasData: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MivoWidgetEntry) -> Void) {
        let (summary, hasData) = loadSummary()
        completion(MivoWidgetEntry(date: Date(), summary: summary, hasData: hasData))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MivoWidgetEntry>) -> Void) {
        let (summary, hasData) = loadSummary()
        let entry = MivoWidgetEntry(date: Date(), summary: summary, hasData: hasData)
        let refreshInterval = hasData ? 5 : 1
        let next = Calendar.current.date(byAdding: .minute, value: refreshInterval, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSummary() -> (WidgetSharedSummary, Bool) {
        if let defaults = UserDefaults(suiteName: appGroup),
           let data = defaults.data(forKey: widgetSummaryKey),
           let summary = try? JSONDecoder().decode(WidgetSharedSummary.self, from: data) {
            return (summary, true)
        }
        return (fallbackSummary, false)
    }

    private var fallbackSummary: WidgetSharedSummary {
        WidgetSharedSummary(
            recoveredMinutesToday: 0,
            screenTimeMinutesToday: 0,
            nextScrollWindow: "Open Mivo to start",
            planState: "Tap to open Mivo",
            streakText: "No data yet",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: nil,
            focusedMinutesToday: 0
        )
    }
}

private struct MivoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MivoWidgetEntry

    private var focusedMinutesToday: Int {
        entry.summary.focusedMinutesToday ?? 0
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
            Text(formatMinutes(focusedMinutesToday))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
            Text(entry.hasData ? "focused today" : "no data yet")
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
                Text(formatMinutes(focusedMinutesToday))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.36, green: 0.2, blue: 0.09))
                Text(entry.hasData ? "focused today" : "no data yet")
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
        Gauge(value: Double(min(focusedMinutesToday, 360)), in: 0...360) {
            Text("Mivo")
        } currentValueLabel: {
            Text("\(focusedMinutesToday)m")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading) {
            Text("Mivo: \(formatMinutes(focusedMinutesToday)) focused")
            Text(entry.summary.nextScrollWindow)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }
}

// MARK: - Live Activity views

private struct MivoSessionLiveActivityView: View {
    let context: ActivityViewContext<MivoSessionLiveAttributes>
    private var endsAt: Date { context.state.sessionEndsAt }
    private var planSeconds: Double { Double(context.state.planMinutes) * 60 }
    private var startedAt: Date { context.attributes.sessionStartedAt }
    private var isFocus: Bool { context.attributes.kind == "focus" }

    var body: some View {
        HStack(spacing: 16) {
            if let companionState = context.state.companionState {
                // Companion on: the character stands in for the timer glyph.
                CompanionLiveBadge(rawState: companionState, size: 52, background: cream)
                    .accessibilityLabel("\(context.state.companionName ?? "Your companion")")
            } else {
                // Timer circle
                VStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brown)
                    Text(timerText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(brown)
                }
                .frame(width: 52, height: 52)
                .background(cream)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isFocus ? "Focus session" : "Mivo session active")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(brown)
                Text(context.attributes.intentionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(brown.opacity(0.72))
                // Live countdown
                Text(endsAt, style: .timer)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(brown)
                    .monospacedDigit()
            }

            Spacer()

            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(cream, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(brown, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 40, height: 40)

                // Finish / Add time act on a Mivo scroll session, not a Still run.
                if !isFocus {
                    HStack(spacing: 6) {
                        Link(destination: URL(string: "mivo://session/finish")!) {
                            Image(systemName: "checkmark")
                                .frame(width: 26, height: 24)
                        }
                        .accessibilityLabel("Finish session")

                        if !activeExperimentBlocksExtensions() {
                            Link(destination: URL(string: "mivo://session/addTime")!) {
                                Image(systemName: "plus")
                                    .frame(width: 26, height: 24)
                            }
                            .accessibilityLabel("Add time")
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(brown)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(bgColor)
    }

    private var timerText: String {
        let remaining = max(0, endsAt.timeIntervalSinceNow)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var progress: CGFloat {
        guard planSeconds > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(startedAt)
        return CGFloat(min(elapsed / planSeconds, 1.0))
    }

    private let bgColor = Color(red: 0.91, green: 0.84, blue: 0.76)
    private let cream   = Color(red: 0.96, green: 0.93, blue: 0.88)
    private let brown   = Color(red: 0.35, green: 0.19, blue: 0.09)
}

/// The meerkat's face in a round badge, for the Lock Screen and Dynamic Island.
/// A Live Activity can't animate custom drawing, so this is the state's resting pose.
private struct CompanionLiveBadge: View {
    let rawState: String
    let size: CGFloat
    var background: Color = Color(red: 0.96, green: 0.93, blue: 0.88)

    var body: some View {
        MeerkatHeadBadge(pose: MeerkatMotion.staticPose(for: CompanionState(rawValue: rawState) ?? .idle))
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
    }
}

// Compact leading: timer countdown text
private struct CompactLeadingView: View {
    let context: ActivityViewContext<MivoSessionLiveAttributes>
    var body: some View {
        Image(systemName: "timer")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
    }
}

// Compact trailing: remaining time
private struct CompactTrailingView: View {
    let context: ActivityViewContext<MivoSessionLiveAttributes>
    var body: some View {
        Text(context.state.sessionEndsAt, style: .timer)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
    }
}

// MARK: - Widget bundle

@main
struct MivoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MivoStatusWidget()
        MivoCompanionWidget()
        MivoSessionLiveActivityWidget()
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

struct MivoSessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MivoSessionLiveAttributes.self) { context in
            // Lock screen / notification banner view
            MivoSessionLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press) – full timer
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if let companionState = context.state.companionState {
                            CompanionLiveBadge(rawState: companionState, size: 26)
                        } else {
                            Image(systemName: "timer")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(context.attributes.kind == "focus" ? "Focus" : "Session")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.sessionEndsAt, style: .timer)
                        .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        if context.attributes.kind != "focus" {
                            Link(destination: URL(string: "mivo://session/finish")!) {
                                Label("Finish", systemImage: "checkmark")
                            }
                            if !activeExperimentBlocksExtensions() {
                                Link(destination: URL(string: "mivo://session/addTime")!) {
                                    Label("Add time", systemImage: "plus")
                                }
                            }
                        }
                        Spacer()
                        Text("ends \(context.state.sessionEndsAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                    .padding(.top, 4)
                }
            } compactLeading: {
                if let companionState = context.state.companionState {
                    CompanionLiveBadge(rawState: companionState, size: 22)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                }
            } compactTrailing: {
                Text(context.state.sessionEndsAt, style: .timer)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                    .frame(width: 42)
            } minimal: {
                if let companionState = context.state.companionState {
                    CompanionLiveBadge(rawState: companionState, size: 20)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.19, blue: 0.09))
                }
            }
            .widgetURL(URL(string: context.attributes.kind == "focus" ? "mivo://focus" : "mivo://session/finish"))
        }
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
