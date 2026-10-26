import SwiftUI

/// Time words used across the Lock-in screens.
enum LockInFormat {
    /// "1h 12m", "45m", "under a minute".
    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = Int(ceil(max(0, seconds) / 60))
        if minutes <= 0 { return "under a minute" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "4:30 PM".
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func durationChoice(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    static func outcome(_ reason: LockInReleaseReason) -> String {
        switch reason {
        case .miloConvinced: return "Done"
        case .keyholderApproved: return "Approved"
        case .timeRanOut: return "Time ran out"
        case .cancelledEarly: return "Undone"
        }
    }
}

/// The heading style every Lock-in step shares.
struct LockInTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }
}

/// Small body copy under a control.
struct LockInFootnote: View {
    let text: String
    var tone: Color = MivoColors.inkMuted

    init(_ text: String, tone: Color = MivoColors.inkMuted) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(tone)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A numbered instruction, used by the how-it-works and Screen Time guides.
struct LockInStepRow: View {
    let number: Int
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.deep)
                .frame(width: 28, height: 28)
                .background(MivoColors.surfaceV2)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A one-line status chip ("Active", "Waiting").
struct LockInStatusPill: View {
    enum Tone { case neutral, good, warning }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return MivoColors.inkBody
        case .good: return MivoColors.keptInk
        case .warning: return MivoColors.deep
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return MivoColors.surfaceV2
        case .good: return MivoColors.kept.opacity(0.18)
        case .warning: return MivoColors.accent.opacity(0.18)
        }
    }
}

/// The apps a lock covers, as a short readable line.
struct LockInAppsLabel: View {
    let apps: SpotAppSelection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.badge")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.deep)
                .accessibilityHidden(true)
            Text(apps.summary)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MivoColors.surfaceV2)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
    }
}

/// Milo, sized for a header. Reads the person's own Companion settings so the name
/// and look match the rest of the app.
struct LockInMiloFigure: View {
    var state: CompanionState = .idle
    var height: CGFloat = 120
    @ObservedObject private var companion = CompanionStateManager.shared

    var body: some View {
        CompanionFigureView(
            type: companion.preferences.companionType,
            state: state,
            animated: companion.preferences.animationsEnabled,
            stretchUnlocked: companion.progress.isUnlocked(.stretching),
            accessibilityName: companion.preferences.name
        )
        .frame(height: height)
    }
}

extension CompanionStateManager {
    /// What the chat and the lock screens call Milo.
    var miloName: String {
        let trimmed = preferences.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Milo" : trimmed
    }
}
