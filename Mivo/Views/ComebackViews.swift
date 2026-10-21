import SwiftUI
import UIKit
import UserNotifications

// MARK: - Flow

/// The fresh-start flow for someone who stopped using Mivo (or just wants a
/// clean slate): welcome without guilt → pick a starting point and pace →
/// make sure the pieces that quietly break while away still work.
struct ComebackFlowView: View {
    @EnvironmentObject private var appVM: AppViewModel
    let prompt: ComebackPrompt

    private enum Step: Int, CaseIterable { case welcome, start, setup }

    @State private var step: Step = .welcome
    @State private var reason: ComebackLapseReason?
    @State private var pace: ComebackPace = .steady
    @State private var paceChosenByUser = false
    @State private var typicalDayMinutes: Int?
    @State private var goal: Int
    @State private var why: String?
    @State private var nudges = true
    @State private var screenTimeOn = FamilyControlsManager.shared.liveAuthorizationStatus()
    @State private var notificationStatus: UNAuthorizationStatus?

    init(prompt: ComebackPrompt) {
        self.prompt = prompt
        _goal = State(initialValue: prompt.floorMinutes)
    }

    private static let typicalDayOptions = [45, 60, 90, 120, 180]
    private static let goalOptions = [30, 45, 60, 90]
    private static let whyOptions = [
        "More time for people",
        "Sleep better",
        "Focus on what matters",
        "Feel less anxious",
        "Feel in control again"
    ]

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                progressBar
                    .padding(.top, 24)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case .welcome: welcomePage
                        case .start: startPage
                        case .setup: setupPage
                        }
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 20)
                }

                actions
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .task { await refreshNotificationStatus() }
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: prompt.isManual ? "Fresh start" : "Welcome back")

            Text(prompt.isManual
                 ? "Start fresh from where you are."
                 : "It's been \(prompt.lapseDays) days. Welcome back.")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Text(prompt.isManual
                 ? "Your plan doesn't have to carry on from where it was. Pick a starting point that fits you today, and the count begins at day 1."
                 : "Nothing is owed and nothing is lost. A plan that kept counting while you were away isn't a fair target, so you'll set a new one, starting today.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            MivoEyebrow(text: "What got in the way? (optional)")
                .padding(.top, 30)

            VStack(spacing: 9) {
                ForEach(ComebackLapseReason.allCases) { option in
                    MivoOptionRow(label: option.label, isSelected: reason == option) {
                        HapticsService.selection()
                        reason = (reason == option) ? nil : option
                        if let reason, !paceChosenByUser { pace = reason.suggestedPace }
                    }
                }
            }
            .padding(.top, 12)

            if let reason {
                Text(reason.acknowledgement)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .transition(.opacity)
            }
        }
        .animation(MivoMotion.standard(0.18), value: reason)
    }

    private var startPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Where you start")

            Text("A starting point you can beat.")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            baselineBlock
                .padding(.top, 22)

            if let lowest = prompt.lowestDay {
                Text("Your lowest measured day was \(lowest.minutes) min on \(MivoComeback.shortDate(lowest.date)). You've done it before.")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(MivoColors.kept)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            if let baseline = effectiveBaseline {
                MivoEyebrow(text: "Your daily goal")
                    .padding(.top, 30)

                HStack(spacing: 9) {
                    ForEach(goalChoices, id: \.self) { minutes in
                        goalChip(minutes)
                    }
                }
                .padding(.top, 12)

                MivoEyebrow(text: "How hard to lean")
                    .padding(.top, 30)

                VStack(spacing: 9) {
                    ForEach(ComebackPace.allCases) { option in
                        MivoOptionRow(
                            label: option.title,
                            note: "Day 1: \(startMinutes(for: option, baseline: baseline)) min",
                            isSelected: pace == option
                        ) {
                            HapticsService.selection()
                            pace = option
                            paceChosenByUser = true
                        }
                    }
                }
                .padding(.top, 12)

                Text(paceDetail(baseline: baseline))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Text("This clears your current scrolling plan and its windows. Right after, you'll choose today's windows again. Your sessions, reports and protected apps stay.")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private var baselineBlock: some View {
        if let baseline = prompt.baseline {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(baseline.minutes)")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                    Text("min a day, roughly")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
                Text(baseline.caption)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mivo has no measured days to start from. About how long do you scroll on a typical day?")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    ForEach(Self.typicalDayOptions, id: \.self) { minutes in
                        MivoOptionRow(
                            label: formattedDuration(minutes),
                            isSelected: typicalDayMinutes == minutes
                        ) {
                            HapticsService.selection()
                            typicalDayMinutes = minutes
                        }
                    }
                }
            }
        }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Make it stick")

            Text("Two things that help it last.")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            MivoEyebrow(text: "Why does this matter to you? (optional)")
                .padding(.top, 26)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                spacing: 9
            ) {
                ForEach(Self.whyOptions, id: \.self) { option in
                    whyChip(option)
                }
            }
            .padding(.top, 12)

            MivoEyebrow(text: "Check what may have stopped")
                .padding(.top, 30)

            VStack(spacing: 0) {
                statusRow(
                    title: "Screen Time access",
                    isOn: screenTimeOn,
                    actionTitle: "Turn on",
                    action: requestScreenTime
                )
                MivoHairline(soft: true)
                notificationRow
            }
            .padding(.top, 6)

            if notificationStatus != .denied {
                HStack(spacing: 12) {
                    Text("Nudge me if I go quiet again")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                    Spacer(minLength: 8)
                    MivoToggle(isOn: $nudges, label: "Nudge me if I go quiet again")
                }
                .padding(.top, 18)
                Text("At most three gentle reminders, 3, 7 and 14 days after you last open Mivo.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    /// The standard options plus whatever goal is already on file, so an
    /// unusual existing goal can still be kept.
    private var goalChoices: [Int] {
        Array(Set(Self.goalOptions + [prompt.floorMinutes])).sorted()
    }

    private func goalChip(_ minutes: Int) -> some View {
        let isSelected = goal == minutes
        return Button {
            HapticsService.selection()
            goal = minutes
        } label: {
            Text("\(minutes) min")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(isSelected ? MivoColors.surfaceV2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                        .strokeBorder(isSelected ? MivoColors.deep.opacity(0.50) : MivoColors.ink.opacity(0.14), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MivoPressStyle())
        .accessibilityLabel("Goal \(minutes) minutes a day")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func whyChip(_ option: String) -> some View {
        let isSelected = why == option
        return Button {
            HapticsService.selection()
            why = isSelected ? nil : option
        } label: {
            Text(option)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(isSelected ? MivoColors.surfaceV2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                        .strokeBorder(isSelected ? MivoColors.deep.opacity(0.50) : MivoColors.ink.opacity(0.14), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MivoPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var notificationRow: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return statusRow(title: "Notifications", isOn: true, actionTitle: "", action: {})
        case .denied:
            return statusRow(title: "Notifications", isOn: false, actionTitle: "Open Settings", action: openSystemSettings)
        default:
            return statusRow(title: "Notifications", isOn: false, actionTitle: "Allow", action: requestNotifications)
        }
    }

    private func statusRow(title: String, isOn: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Spacer(minLength: 8)
            if isOn {
                Label("On", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.kept)
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 48)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:
                MivoPrimaryButton(label: "Continue") { advance() }
            case .start:
                MivoPrimaryButton(label: "Continue", disabled: effectiveBaseline == nil) { advance() }
            case .setup:
                MivoPrimaryButton(label: startLabel) { start() }
            }

            if step == .welcome {
                MivoTertiaryButton(label: "Not now", color: MivoColors.inkMuted) {
                    appVM.snoozeComeback()
                }
            } else {
                MivoTertiaryButton(label: "Back", color: MivoColors.inkMuted) {
                    withAnimation(MivoMotion.standard(0.18)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? MivoColors.accent : MivoColors.barTrack)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private func advance() {
        HapticsService.tap()
        withAnimation(MivoMotion.standard(0.18)) {
            step = Step(rawValue: step.rawValue + 1) ?? .setup
        }
    }

    private func start() {
        guard let baseline = effectiveBaseline else { return }
        appVM.startComeback(
            prompt: prompt,
            baseline: baseline,
            pace: pace,
            goalMinutes: goal,
            reason: reason,
            why: why,
            nudges: nudges && notificationStatus != .denied
        )
    }

    // MARK: Derived

    /// The measured baseline when there is one, otherwise what the user typed.
    private var effectiveBaseline: ComebackBaseline? {
        if let measured = prompt.baseline { return measured }
        guard let typicalDayMinutes else { return nil }
        return ComebackBaseline(minutes: typicalDayMinutes, source: .selfReported)
    }

    private func startMinutes(for pace: ComebackPace, baseline: ComebackBaseline) -> Int {
        MivoComeback.startMinutes(baseline: baseline.minutes, pace: pace, floor: max(15, goal))
    }

    private var startLabel: String {
        guard let baseline = effectiveBaseline else { return "Start fresh" }
        return "Start fresh · \(startMinutes(for: pace, baseline: baseline)) min today"
    }

    private func paceDetail(baseline: ComebackBaseline) -> String {
        let start = startMinutes(for: pace, baseline: baseline)
        let floor = max(15, goal)
        guard start > floor else {
            return "You're already at your \(floor)-min goal. This keeps you there while the habit comes back."
        }
        let step = pace.dailyStepMinutes
        let days = MivoComeback.daysToGoal(startMinutes: start, dailyStep: step, floor: floor)
        let weekOneTarget = max(floor, start - step * 7)
        let horizon = days >= 14 ? "about \((days + 6) / 7) weeks" : "about \(days) days"
        return "Day 1 is \(start) min, then \(step) min lower each day. By day 8 you'd be at \(weekOneTarget) min, and at your \(floor)-min goal in \(horizon). You can change pace or restart any time."
    }

    private func formattedDuration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    // MARK: System permissions

    private func requestScreenTime() {
        FamilyControlsManager.shared.requestAuthorization { granted in
            DispatchQueue.main.async {
                screenTimeOn = granted || FamilyControlsManager.shared.liveAuthorizationStatus()
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        let current = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { notificationStatus = current.authorizationStatus }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Home

/// Shows the fresh-start week on Home, or a quiet way back for someone who
/// dismissed the offer. Renders nothing otherwise.
struct ComebackHomeSection: View {
    @EnvironmentObject private var appVM: AppViewModel

    var body: some View {
        if let week = appVM.comebackWeek() {
            MivoCard {
                activeCard(week)
            }
        } else if appVM.comebackRestartOfferLapseDays != nil {
            restartRow
        }
    }

    private func activeCard(_ week: ComebackWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Fresh start · Day \(week.dayIndex) of \(MivoComeback.cardDays)", color: MivoColors.inkBody)

            Text("Today's target: \(week.todayTarget) min")
                .font(.system(size: 20, weight: .bold))
                .tracking(Font.mivoTracking(-0.02, at: 20))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(Array(week.marks.enumerated()), id: \.offset) { _, mark in
                    dot(for: mark)
                }
            }
            .padding(.top, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dotsAccessibilityLabel(week))

            Text(progressLine(week))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if let why = week.why {
                Text("Your why: \(why.lowercased())")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.deep)
                    .padding(.top, 6)
            }

            // No "change pace" here: a fresh start can't be redone for 30 days,
            // so the card says when it can instead of offering a dead control.
            if let availableAgain = appVM.comebackAvailableAgainText {
                Text("You can start fresh again from \(availableAgain).")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .padding(.top, 10)
            }
        }
    }

    private var restartRow: some View {
        Button {
            HapticsService.selection()
            appVM.presentComebackFlow()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MivoEyebrow(text: "Fresh start", color: MivoColors.inkBody)
                    Text("Ready to restart?")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text("Set a plan from where you are today, not where you left off.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(MivoMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mivoCardBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(MivoPressStyle())
    }

    @ViewBuilder
    private func dot(for mark: ComebackDayMark) -> some View {
        switch mark {
        case .under:
            Circle().fill(MivoColors.kept).frame(width: 14, height: 14)
        case .over:
            Circle().strokeBorder(MivoColors.inkMuted, lineWidth: 1.5).frame(width: 14, height: 14)
        case .unmeasured:
            Circle().fill(MivoColors.barTrack).frame(width: 8, height: 8).frame(width: 14, height: 14)
        case .today:
            Circle().strokeBorder(MivoColors.accent, lineWidth: 2).frame(width: 14, height: 14)
        case .upcoming:
            Circle().fill(MivoColors.hairlineSoft).frame(width: 14, height: 14)
        }
    }

    private func progressLine(_ week: ComebackWeekSummary) -> String {
        if week.measuredCount == 0 {
            return week.dayIndex == 1
                ? "Day 1 is the only day that counts right now. Finished days appear here once Screen Time reports them."
                : "Finished days appear here once Screen Time reports them."
        }
        return "\(week.underCount) of \(week.measuredCount) finished day\(week.measuredCount == 1 ? "" : "s") under target. A rough day only changes tomorrow's number, never what you've already done."
    }

    private func dotsAccessibilityLabel(_ week: ComebackWeekSummary) -> String {
        "Day \(week.dayIndex) of \(MivoComeback.cardDays). \(week.underCount) of \(week.measuredCount) finished days under target."
    }
}

#if DEBUG
// MARK: - Debug previews

/// Sample data for `-MivoPreviewComeback` / `-MivoPreviewComebackHome`, so both
/// screens can be opened without a signed-in account or a real lapse.
enum ComebackPreviewFixtures {
    static var prompt: ComebackPrompt {
        ComebackPrompt(
            id: "preview",
            lapseDays: 12,
            isManual: false,
            baseline: ComebackBaseline(
                minutes: 94,
                source: .lastMeasuredDays(3, lastDay: MivoDay.key(offsetFromToday: -16))
            ),
            lowestDay: DailyScreenTimeObservation(
                date: MivoDay.key(offsetFromToday: -20), minutes: 58, recordedAt: ""
            ),
            floorMinutes: 30
        )
    }
}

struct ComebackHomePreview: View {
    @EnvironmentObject private var appVM: AppViewModel

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                ComebackHomeSection()
                Spacer()
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
            .padding(.top, 60)
        }
        .onAppear {
            appVM.comebackAnchor = ComebackAnchor(
                startDay: MivoDay.key(offsetFromToday: -3),
                baselineMinutes: 94,
                baselineSource: .recentDays(5),
                startMinutes: 85,
                dailyStepMinutes: 2,
                pace: .steady,
                reason: .lostMotivation,
                lapseDays: 12,
                why: "Sleep better",
                nudgesEnabled: true,
                createdAt: ""
            )
            appVM.dailyScreenTimeObservations = [
                DailyScreenTimeObservation(date: MivoDay.key(offsetFromToday: -3), minutes: 80, recordedAt: ""),
                DailyScreenTimeObservation(date: MivoDay.key(offsetFromToday: -2), minutes: 92, recordedAt: ""),
                DailyScreenTimeObservation(date: MivoDay.key(offsetFromToday: -1), minutes: 78, recordedAt: "")
            ]
        }
    }
}
#endif
