import WidgetKit
import SwiftUI

// The Companion widget. It only ever shows what the app published to the App
// Group (`CompanionSharedSnapshot`) — the widget computes nothing, reads no
// Screen Time data, and degrades to a neutral state when the snapshot is
// missing, from another day, or too old to trust.
//
// Compiled together with CompanionState, CompanionType, CompanionSchedule,
// CompanionSharedSnapshot and MeerkatArt (all Foundation/SwiftUI-only).

private enum CompanionWidgetPalette {
    static let ink = Color(red: 0.36, green: 0.2, blue: 0.09)
    static let body = Color(red: 0.71, green: 0.38, blue: 0.12)
    static let ground = Color(red: 0.95, green: 0.91, blue: 0.86)
}

// MARK: - Timeline

private struct CompanionWidgetEntry: TimelineEntry {
    let date: Date
    /// `nil`: the companion isn't set up (or was turned off).
    let snapshot: CompanionSharedSnapshot?

    private var dayKey: String { CompanionDay.key(date) }

    var isSetUp: Bool { snapshot?.isActive == true }

    /// A stale snapshot reads as a neutral companion rather than a claim about
    /// what it's doing right now.
    private var trusted: CompanionSharedSnapshot? {
        guard let snapshot, snapshot.isActive, snapshot.isFresh(at: date) else { return nil }
        return snapshot
    }

    var name: String { snapshot?.name ?? CompanionType.meerkat.defaultName }

    var state: CompanionState {
        trusted.flatMap { CompanionState(rawValue: $0.state) } ?? .idle
    }

    /// Words go stale faster than posture does.
    var message: String? {
        guard let snapshot, snapshot.isActive, snapshot.isFresh(at: date, maxAge: 2 * 60 * 60) else { return nil }
        return snapshot.message
    }

    var pausesToday: Int { snapshot?.pausesCount(on: dayKey) ?? 0 }

    var focusEndsAt: Date? {
        guard let trusted, trusted.focusActive, let end = trusted.focusEndsAt, end > date else { return nil }
        return end
    }

    var focusActive: Bool { trusted?.focusActive ?? false }

    var line: String {
        if focusActive { return "Focused" }
        if let message { return message }
        return pausesToday > 0
            ? "\(pausesToday) intentional pause\(pausesToday == 1 ? "" : "s") today"
            : state.label
    }
}

private struct CompanionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompanionWidgetEntry {
        CompanionWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CompanionWidgetEntry) -> Void) {
        completion(CompanionWidgetEntry(date: Date(), snapshot: CompanionSharedStore().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = CompanionSharedStore().read()
        var entries = [CompanionWidgetEntry(date: now, snapshot: snapshot)]

        // When a focus session ends, the next entry shows the companion at rest.
        if let end = snapshot?.focusEndsAt, end > now, end.timeIntervalSince(now) < 4 * 60 * 60 {
            entries.append(CompanionWidgetEntry(date: end, snapshot: snapshot))
        }
        // The app reloads this timeline whenever something visible changes;
        // the periodic refresh only keeps staleness checks honest.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - Views

private struct CompanionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CompanionWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: accessory
            default: small
            }
        }
        .widgetURL(URL(string: "mivo://companion"))
    }

    private var figure: some View {
        MeerkatCanvas(pose: MeerkatMotion.staticPose(for: entry.state))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(CompanionWidgetPalette.ink)
                    Text(entry.isSetUp ? entry.state.label : "Not set up")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(CompanionWidgetPalette.body.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            figure
                .frame(maxWidth: .infinity)
            if entry.isSetUp { focusOrLine(font: .caption2.weight(.semibold)) }
        }
        .padding(14)
        .widgetBackground(CompanionWidgetPalette.ground)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            figure
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(CompanionWidgetPalette.ink)
                Text(entry.isSetUp ? entry.state.label : "Not set up")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CompanionWidgetPalette.body.opacity(0.8))
                if entry.isSetUp {
                    focusOrLine(font: .callout.weight(.semibold))
                    if !entry.focusActive, entry.message != nil {
                        Text("\(entry.pausesToday) pause\(entry.pausesToday == 1 ? "" : "s") today")
                            .font(.caption)
                            .foregroundColor(CompanionWidgetPalette.body.opacity(0.7))
                    }
                } else {
                    Text("Open Mivo → Settings → Companion")
                        .font(.caption)
                        .foregroundColor(CompanionWidgetPalette.body)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .widgetBackground(CompanionWidgetPalette.ground)
    }

    @ViewBuilder
    private func focusOrLine(font: Font) -> some View {
        if let end = entry.focusEndsAt {
            HStack(spacing: 4) {
                Text("Focused")
                Text(end, style: .timer)
                    .monospacedDigit()
            }
            .font(font)
            .foregroundColor(CompanionWidgetPalette.ink)
        } else {
            Text(entry.line)
                .font(font)
                .foregroundColor(CompanionWidgetPalette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.name) · \(entry.isSetUp ? entry.state.label : "Not set up")")
                .font(.headline)
            if entry.isSetUp {
                if let end = entry.focusEndsAt {
                    (Text("Focused ") + Text(end, style: .timer)).monospacedDigit()
                } else {
                    Text(entry.line).lineLimit(2)
                }
            }
        }
    }
}

struct MivoCompanionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CompanionSharedKeys.widgetKind, provider: CompanionWidgetProvider()) { entry in
            CompanionWidgetView(entry: entry)
        }
        .configurationDisplayName("Companion")
        .description("Your companion's mood, today's intentional pauses and whether a focus session is running.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
