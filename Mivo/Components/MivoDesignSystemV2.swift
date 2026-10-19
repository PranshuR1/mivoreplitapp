import SwiftUI

// MARK: - Metrics
//
// The v2 redesign is a divider-based layout: one page ground, no tinted
// sections, and sections separated by a hairline rather than by a card. These
// constants are the spacing scale and the motion curves from the handoff, kept
// in one place so a screen never invents its own.

enum MivoMetrics {
    /// Screen horizontal padding. Was 18 before the redesign.
    static let screenPadding: CGFloat = 24

    /// Bottom padding on scroll content so it clears the tab bar.
    static let scrollBottomPadding: CGFloat = 130

    /// Every framed element — buttons, chips, tiles, sheets, badges.
    static let radius: CGFloat = 8

    /// Primary action height. Tertiary actions are 42.
    static let buttonHeight: CGFloat = 54
    static let tertiaryHeight: CGFloat = 42

    /// Spacing scale: 4, 6, 8, 10, 14, 18, 22, 26, 30, 44.
    static let sectionSpacing: CGFloat = 26
}

enum MivoMotion {
    /// The house curve — cubic-bezier(0.22, 0.7, 0.3, 1). Nothing bounces or
    /// overshoots.
    static func standard(_ duration: Double) -> Animation {
        .timingCurve(0.22, 0.7, 0.3, 1, duration: duration)
    }

    static let stepEnter = standard(0.24)
    static let sheetPresent = standard(0.26)
    static let progressFill = standard(0.48)
    static let keptBar = standard(0.60)
    static let onboardingProgress = standard(0.42)
    static let tabCrossfade = Animation.easeInOut(duration: 0.16)
    static let toggleKnob = Animation.timingCurve(0.3, 0.8, 0.3, 1, duration: 0.22)
}

extension Font {
    /// Tracking is specified in em in the handoff; SwiftUI takes points.
    static func mivoTracking(_ em: Double, at size: CGFloat) -> CGFloat {
        CGFloat(em) * size
    }
}

// MARK: - Hairline

/// The section divider. Full width, 1px — never a card edge.
struct MivoHairline: View {
    var soft: Bool = false

    var body: some View {
        Rectangle()
            .fill(soft ? MivoColors.hairlineSoft : MivoColors.hairline)
            .frame(height: 1)
    }
}

// MARK: - Eyebrow

/// 10/Bold uppercase, tracking 0.13em, `inkMuted`.
///
/// Eyebrow colour is 2.9:1, so it is only ever used for uppercase semibold-plus
/// labels — never prose — and its information is repeated in an accessibility
/// label where it is load-bearing.
struct MivoEyebrow: View {
    let text: String
    var color: Color = MivoColors.inkMuted
    var accessibilityText: String?

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .tracking(Font.mivoTracking(0.13, at: 10))
            .foregroundColor(color)
            .accessibilityLabel(accessibilityText ?? text)
    }
}

// MARK: - Buttons

/// The single primary action per screen. Amber is reserved for this, today's
/// bar/dot, and the active tab — nothing decorative.
struct MivoPrimaryButton: View {
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15.5, weight: .bold))
                .foregroundColor(disabled ? MivoColors.inkMuted : .white)
                .frame(maxWidth: .infinity)
                .frame(height: MivoMetrics.buttonHeight)
                .background(disabled ? MivoColors.ink.opacity(0.10) : MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                // The only button shadow in the system.
                .shadow(
                    color: disabled ? .clear : Color(red: 120/255, green: 70/255, blue: 20/255).opacity(0.30),
                    radius: 2,
                    y: 1
                )
        }
        .buttonStyle(MivoPressStyle())
        .disabled(disabled)
    }
}

/// Dark primary — used where the action is a confirmation rather than a start
/// ("I'm done early", "Save reflection").
struct MivoInkButton: View {
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15.5, weight: .bold))
                .foregroundColor(disabled ? MivoColors.inkMuted : MivoColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: MivoMetrics.buttonHeight)
                .background(disabled ? MivoColors.ink.opacity(0.10) : MivoColors.ink)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        }
        .buttonStyle(MivoPressStyle())
        .disabled(disabled)
    }
}

/// Text-only tertiary action. `deep` rather than amber — amber text on cream is
/// 2.6:1 and must never appear below 18pt.
struct MivoTertiaryButton: View {
    let label: String
    var color: Color = MivoColors.deep
    var height: CGFloat = MivoMetrics.tertiaryHeight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(MivoPressStyle())
    }
}

// MARK: - Badges

/// `BETA`, `FOUNDER`, and session outcome badges.
struct MivoBadge: View {
    let text: String
    var background: Color
    var foreground: Color
    var size: CGFloat = 8.5
    var tracking: Double = 0.10

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .heavy))
            .tracking(Font.mivoTracking(tracking, at: size))
            .foregroundColor(foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
    }

    static func beta() -> MivoBadge {
        MivoBadge(
            text: "BETA",
            background: MivoColors.info.opacity(0.13),
            foreground: Color(hex: "#3C5C8A")
        )
    }

    static func trial() -> MivoBadge {
        MivoBadge(
            text: "TRIAL",
            background: MivoColors.accent.opacity(0.13),
            foreground: MivoColors.deep
        )
    }

    static func founder() -> MivoBadge {
        MivoBadge(
            text: "FOUNDER",
            background: MivoColors.info.opacity(0.13),
            foreground: Color(hex: "#3C5C8A")
        )
    }
}

/// Session outcome. "Not worth it" is neutral, never red — going over a window
/// is not a failure.
enum MivoOutcome: String {
    case worthIt = "WORTH IT"
    case mixed = "MIXED"
    case closed = "CLOSED"
    case kept = "KEPT"
    case retry = "RETRY"

    var background: Color {
        switch self {
        case .worthIt, .kept: return MivoColors.kept.opacity(0.15)
        case .mixed: return MivoColors.accent.opacity(0.16)
        case .closed, .retry: return MivoColors.ink.opacity(0.08)
        }
    }

    var foreground: Color {
        switch self {
        case .worthIt, .kept: return Color(hex: "#4A6A4E")
        case .mixed: return Color(hex: "#96551A")
        case .closed, .retry: return MivoColors.inkBody
        }
    }
}

struct MivoOutcomeBadge: View {
    let outcome: MivoOutcome

    var body: some View {
        Text(outcome.rawValue)
            .font(.system(size: 9, weight: .heavy))
            .tracking(Font.mivoTracking(0.08, at: 9))
            .foregroundColor(outcome.foreground)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(outcome.background)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
    }
}

// MARK: - Rows

/// Settings-style row: label left, value + chevron right, hairlineSoft between.
struct MivoSettingsRow: View {
    let label: String
    var value: String?
    var valueColor: Color = MivoColors.inkMuted
    var valueWeight: Font.Weight = .medium
    var showsChevron: Bool = true
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: valueWeight))
                    .foregroundColor(valueColor)
                    .fixedSize()
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 15)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(MivoPressStyle())
        } else {
            content
        }
    }
}

/// A tappable navigation row with an eyebrow, title and optional trailing
/// chevron — the Home experiment and Mivo Clear rows.
struct MivoNavigationRow<Content: View>: View {
    var verticalPadding: CGFloat = 22
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    content()
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(MivoColors.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(MivoPressStyle())
    }
}

/// Selectable option row used by onboarding, the reason step and reflection.
struct MivoOptionRow: View {
    let label: String
    var note: String?
    let isSelected: Bool
    /// The reason step fills the row with `ink`; onboarding and reflection use
    /// the lighter `surface` treatment.
    var fillsWhenSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(labelColor)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(noteColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, fillsWhenSelected ? 17 : 18)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MivoPressStyle())
        .animation(MivoMotion.standard(0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        guard isSelected else { return .clear }
        return fillsWhenSelected ? MivoColors.ink : MivoColors.surfaceV2
    }

    private var borderColor: Color {
        if isSelected {
            return fillsWhenSelected ? MivoColors.ink : MivoColors.deep.opacity(0.50)
        }
        return MivoColors.ink.opacity(fillsWhenSelected ? 0.16 : 0.14)
    }

    private var labelColor: Color {
        isSelected && fillsWhenSelected ? MivoColors.background : MivoColors.ink
    }

    private var noteColor: Color {
        if isSelected {
            return fillsWhenSelected ? MivoColors.background.opacity(0.7) : Color(hex: "#96551A")
        }
        return MivoColors.inkMuted
    }
}

// MARK: - Stats

/// Equal-width stat columns divided by 1×32 hairline verticals.
struct MivoStatColumns: View {
    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                    Text(item.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(MivoColors.hairline)
                        .frame(width: 1, height: 32)
                }
            }
        }
        .padding(.vertical, 18)
    }
}

// MARK: - Progress

/// The 7-segment experiment progress bar.
struct MivoSegmentBar: View {
    let completed: Int
    var total: Int = 7
    var height: CGFloat = 4
    var spacing: CGFloat = 5
    var fill: Color = MivoColors.accent

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(1, total), id: \.self) { index in
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(index < completed ? fill : MivoColors.barTrack)
                    .frame(height: height)
            }
        }
        .animation(MivoMotion.progressFill, value: completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(min(max(0, completed), total)) of \(total)")
    }
}

/// A horizontal track with a proportional fill — "windows kept", plan progress.
struct MivoProgressTrack: View {
    let fraction: Double
    var height: CGFloat = 6
    var fill: Color = MivoColors.kept
    var animation: Animation = MivoMotion.keptBar

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MivoColors.barTrack)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .animation(animation, value: fraction)
    }
}

// MARK: - Toggle

/// The house toggle: 44×26 track, 20×20 knob travelling 3→21 over 220ms.
/// Used instead of `Toggle`, whose default green is not in the palette.
struct MivoToggle: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            isOn.toggle()
            HapticsService.selection()
        } label: {
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .fill(isOn ? MivoColors.accent : MivoColors.ink.opacity(0.20))
                .frame(width: 44, height: 26)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .offset(x: isOn ? 21 : 3)
                }
        }
        .buttonStyle(.plain)
        .animation(MivoMotion.toggleKnob, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Chips

/// Segmented range control (`7 days` / `30 days`) — no track, no border.
struct MivoSegmentedChips<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                    HapticsService.selection()
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selection == option.value ? MivoColors.background : MivoColors.ink)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 13)
                        .background(selection == option.value ? MivoColors.ink : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .animation(MivoMotion.standard(0.18), value: selection)
    }
}

/// Equal-width selection chips (`5m 10m 15m 30m`).
struct MivoChoiceChips<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 9) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                    HapticsService.selection()
                } label: {
                    Text(option.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(selection == option.value ? MivoColors.background : MivoColors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(selection == option.value ? MivoColors.ink : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                        .overlay(
                            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                                .strokeBorder(
                                    selection == option.value ? MivoColors.ink : MivoColors.ink.opacity(0.16),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .animation(MivoMotion.standard(0.18), value: selection)
    }
}

// MARK: - Greeting bar

/// Shared by Home and Patterns: date eyebrow, greeting, and the transparent
/// logo mark. No avatar, no settings gear — Settings is a tab.
struct MivoGreetingBar: View {
    let name: String

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                MivoEyebrow(text: Self.dateLabel())
                Text("\(greeting()), \(name)")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 21))
                    .foregroundColor(MivoColors.ink)
            }
            Spacer(minLength: 12)
            // The asset is a template so onboarding can knock it out to cream;
            // here it needs its own colours.
            Image("MivoLogoMark")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 52)
                .opacity(0.9)
                .accessibilityHidden(true)
        }
    }

    static func dateLabel(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Tab bar

/// The four-tab bar. Replaces `UITabBar`'s appearance entirely: the native bar
/// cannot express a 22pt icon over a 10/Bold label at 5pt spacing with no
/// selection pill, so it is hidden and this is overlaid instead.
struct MivoTabBar: View {
    @Binding var selection: Int

    struct Item {
        let title: String
        let icon: String
        let selectedIcon: String
    }

    static let items: [Item] = [
        Item(title: "Home", icon: "house", selectedIcon: "house.fill"),
        Item(title: "Patterns", icon: "chart.bar", selectedIcon: "chart.bar.fill"),
        Item(title: "Protect", icon: "pause.circle", selectedIcon: "pause.circle.fill"),
        Item(title: "Settings", icon: "slider.horizontal.3", selectedIcon: "slider.horizontal.3")
    ]

    var body: some View {
        VStack(spacing: 0) {
            MivoHairline()
            HStack(spacing: 0) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { index, item in
                    Button {
                        guard selection != index else { return }
                        selection = index
                        HapticsService.selection()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: selection == index ? item.selectedIcon : item.icon)
                                .font(.system(size: 22, weight: .regular))
                            Text(item.title)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(selection == index ? MivoColors.accent : MivoColors.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == index ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.top, 5)
        }
        .background {
            MivoColors.background.opacity(0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Section scaffolding

/// A section of the divided layout: content, then the hairline that closes it.
struct MivoDividedSection<Content: View>: View {
    var topPadding: CGFloat = MivoMetrics.sectionSpacing
    var bottomPadding: CGFloat = MivoMetrics.sectionSpacing
    var showsHairline: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsHairline {
                MivoHairline()
            }
        }
    }
}
