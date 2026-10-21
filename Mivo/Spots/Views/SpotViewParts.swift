import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif

// Small pieces shared by the Spots screens. Everything here is built from the
// existing design system (MivoColors, MivoMetrics, MivoEyebrow, MivoHairline…) —
// no new colours, radii or type styles.

/// A Spot's icon on a quiet tile.
struct SpotIconView: View {
    let icon: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .fill(MivoColors.surfaceV2)
            switch SpotIcon.kind(of: icon) {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundColor(MivoColors.ink)
            case .emoji(let value):
                Text(value)
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "ACTIVE" in the house badge style. Calm green, never an alert colour.
struct SpotActiveBadge: View {
    var body: some View {
        MivoBadge(
            text: "Active",
            background: MivoColors.kept.opacity(0.15),
            foreground: Color(hex: "#4A6A4E")
        )
    }
}

/// The apps a Spot covers, as Apple renders them (icon + name). Names come from
/// the tokens themselves, so this works even when Apple gave Mivo no text name.
struct SpotAppLabels: View {
    let selection: SpotAppSelection
    var limit: Int = 8

    var body: some View {
        #if canImport(FamilyControls)
        let activity = selection.activitySelection
        let apps = Array(activity.applicationTokens)
        let categories = Array(activity.categoryTokens)
        let sites = Array(activity.webDomainTokens)
        let total = apps.count + categories.count + sites.count
        // No tokens to draw (they only exist on the device that picked them), but
        // Mivo kept the names — show those rather than claiming nothing is chosen.
        if total == 0, !selection.appNames.isEmpty {
            Text(selection.summary)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
        } else {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(apps.prefix(limit)), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }
            ForEach(Array(categories.prefix(max(0, limit - apps.count))), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }
            ForEach(Array(sites.prefix(max(0, limit - apps.count - categories.count))), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }
            if total > limit {
                Text("+ \(total - limit) more")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
            if total == 0 {
                Text("No apps yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
        }
        }
        #else
        Text(selection.summary)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(MivoColors.inkBody)
        #endif
    }
}

/// One app's icon and name from stored token data (used in summaries).
struct SpotTokenLabel: View {
    let tokenData: Data?
    let fallbackName: String?

    var body: some View {
        #if canImport(FamilyControls)
        if let tokenData, let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
        } else {
            Text(fallbackName ?? "An app")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
        }
        #else
        Text(fallbackName ?? "An app")
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundColor(MivoColors.ink)
        #endif
    }
}

/// Live "41 min left" text. Updates itself; no timer is owned by the view.
struct SpotRemainingText: View {
    let session: SpotSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(Self.text(for: session, now: context.date))
        }
    }

    static func text(for session: SpotSession, now: Date) -> String {
        if session.isOpenEnded { return "Until you end it" }
        let remaining = session.remainingSeconds(now: now)
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes <= 0 { return "Wrapping up" }
        return "\(SpotFormat.duration(minutes: minutes)) left"
    }
}

/// The running Spot, as a quiet row. Tapping it opens the full active screen.
struct SpotActiveBanner: View {
    @ObservedObject private var manager = SpotManager.shared
    /// Applied only while a Spot is running, so an idle banner takes no space.
    var topPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        if let session = manager.activeSession {
            Button {
                HapticsService.selection()
                action()
            } label: {
                HStack(spacing: 12) {
                    SpotIconView(icon: session.spotIcon, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(session.spotName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                            SpotActiveBadge()
                        }
                        HStack(spacing: 5) {
                            Text(session.mode.cardLabel)
                            Text("·")
                            SpotRemainingText(session: session)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.cardRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(MivoPressStyle())
            .padding(.top, topPadding)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(session.spotName) is active. Open it.")
        }
    }
}

/// Home's entry into Mivo Spots: a tile in the Explore grid.
struct SpotsEntryRow: View {
    @ObservedObject private var manager = SpotManager.shared
    let action: () -> Void

    var body: some View {
        MivoToolTile(icon: "mappin.and.ellipse", title: "Mivo Spots", subtitle: meta, action: action)
    }

    private var meta: String {
        if let session = manager.activeSession {
            return "\(session.spotName) is on · \(SpotRemainingText.text(for: session, now: Date()))"
        }
        switch manager.spots.count {
        case 0: return "Places become reminders"
        case 1: return "1 Spot"
        default: return "\(manager.spots.count) Spots"
        }
    }
}

/// Section header + body used on the detail screens.
struct SpotSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: title)
                .padding(.top, MivoMetrics.sectionSpacing)
                .padding(.bottom, 12)
            content()
                .padding(.bottom, MivoMetrics.sectionSpacing)
            MivoHairline()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label / value line.
struct SpotFact: View {
    let label: String
    let value: String
    var valueColor: Color = MivoColors.inkBody

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }
}
