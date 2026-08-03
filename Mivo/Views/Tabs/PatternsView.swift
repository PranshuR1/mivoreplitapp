import SwiftUI

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

#if canImport(ManagedSettings)
import ManagedSettings
#endif

private let monthNames = ["January","February","March","April","May","June",
                           "July","August","September","October","November","December"]
private let weekdayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

private struct DayPartStat {
    let name: String
    let count: Int
    let minutes: Int
    let share: CGFloat
    let tint: Color
}

private struct AIStatInsight {
    let title: String
    let body: String
    let icon: String
    let tint: Color
}

private struct PatternDayPoint: Identifiable {
    let id: String
    let label: String
    let actualMinutes: Int
    let plannedMinutes: Int
}

private struct PatternBarPoint: Identifiable {
    let id: String
    let label: String
    let value: Int
    let detail: String
    let tint: Color
}

private enum PatternDataScope: String, CaseIterable, Identifiable {
    case allScrolling = "All scrolling"
    case mivoClear = "Mivo Clear BETA"

    var id: String { rawValue }
}

// MARK: - Stat detail identifiers
private enum StatDetailKind: String, Identifiable {
    case todayScrolled
    case longestScroll
    case avgScroll
    case emergency
    case scrollBehavior
    case windows
    case triggers
    case habits
    var id: String { rawValue }
}

struct PatternsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var clearStore = MivoClearStore.shared
    @State private var viewYear: Int
    @State private var viewMonth: Int
    @State private var selectedDay: Int
    @State private var showFocus = false
    @State private var refreshPulse = false
    @State private var activeStatDetail: StatDetailKind? = nil
    @State private var patternRangeDays = 7
    @State private var patternDataScope: PatternDataScope = .allScrolling
    @State private var weeklyReportSnapshot: WeeklyReportSnapshot? = nil
    @State private var weeklyReportBaselineMinutes = 1

    init() {
        let now = Date()
        let cal = Calendar.current
        _viewYear = State(initialValue: cal.component(.year, from: now))
        _viewMonth = State(initialValue: cal.component(.month, from: now) - 1) // 0-indexed
        _selectedDay = State(initialValue: cal.component(.day, from: now))
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    screenTimeInfographic
                    weeklyReportAccessRow
                    personalizedPatternSection
                    if ProductExpansionStore.shared.isEnabled(.mivoClear) {
                        patternDataScopePicker
                    }
                    if patternDataScope == .mivoClear {
                        MivoClearPatternsCard(rangeDays: patternRangeDays)
                    } else {
                        statisticsDashboard
                    }
                    experimentHistorySection
                    calendarCard
                    insightSection
                        .padding(.bottom, 90)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .mivoReadableWidth()
            }
            .refreshable {
                refreshPatternsData()
            }

            VStack {
                Spacer()
                NavigationLink {
                    FocusView()
                } label: {
                    Text("Enter Focus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(MivoColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: MivoColors.accent.opacity(0.28), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            refreshPatternsData()
            Task { await MivoClearStore.shared.prepare(for: appVM) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mivoDeviceActivityDidUpdate)) { _ in
            refreshPatternsData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mivoSessionHistoryDidUpdate)) { _ in
            refreshPulse.toggle()
            keepSelectedDayValid()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            refreshPatternsData()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshPatternsData()
            }
        }
    }

    private var focusAction: some View {
        NavigationLink {
            FocusView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Enter Focus")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(MivoColors.white)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(MivoColors.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var patternsHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            MivoLogo(size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("Patterns")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text("See where your time goes.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 40, height: 40)
        }
        .padding(.top, 4)
    }

    private var weeklyReportAccessRow: some View {
        let average = (weeklyReportSnapshot?.totalMinutes ?? 0) / max(1, currentWeekElapsedDayCount)
        let sessionCount = weeklyReportSnapshot?.sessionCount ?? 0

        return NavigationLink {
            WeeklyReportView()
                .environmentObject(appVM)
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .stroke(MivoColors.border.opacity(0.3), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: weeklyReportProgress(average: average))
                        .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("Weekly report")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.screenTimeInk)
                        Text("NEW")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(MivoColors.accent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(sessionCount > 0
                         ? "\(formatDuration(average)) daily average · \(sessionCount) saved session\(sessionCount == 1 ? "" : "s")"
                         : "Your recap, comparisons, truth checks, and daily chart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(MivoColors.border.opacity(0.32)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(MivoColors.border.opacity(0.32)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the five-page weekly statistics recap")
    }

    private var currentWeekElapsedDayCount: Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 1 }
        return max(1, (Calendar.current.dateComponents([.day], from: interval.start, to: Date()).day ?? 0) + 1)
    }

    private func weeklyReportProgress(average: Int) -> CGFloat {
        min(1, CGFloat(average) / CGFloat(max(1, weeklyReportBaselineMinutes)))
    }

    private var appleScreenTimeTodayCard: some View {
        Group {
            if hasScreenTimeAccess {
                if #available(iOS 16.0, *) {
                    MivoScreenTimeUsageLiveReport()
                        .frame(maxWidth: .infinity)
                        .frame(height: 154)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                missingScreenTimeCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's total Apple Screen Time")
    }

    private var patternDataScopePicker: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PATTERN DATA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                Text(patternDataScope.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
            }

            Spacer()

            Menu {
                Button("All scrolling") { patternDataScope = .allScrolling }
                Button("Mivo Clear BETA") { patternDataScope = .mivoClear }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .frame(width: 36, height: 36)
                    .background(MivoColors.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel("Choose pattern data")
            .accessibilityValue(patternDataScope.rawValue)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
    }

    private var totalTimeScrolledCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Text(patternDataScope == .mivoClear ? "MIVO CLEAR BETA TIME" : "TOTAL TIME SCROLLED")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                Spacer()

                Menu {
                    Button("All scrolling") { patternDataScope = .allScrolling }
                    if ProductExpansionStore.shared.isEnabled(.mivoClear) {
                        Button("Mivo Clear BETA") { patternDataScope = .mivoClear }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(patternDataScope.rawValue)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(MivoColors.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }

            HStack(alignment: .lastTextBaseline) {
                Text(formatDuration(displayedRangeMinutes))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 12)
                Text("\(displayedRangeSessionCount) visit\(displayedRangeSessionCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Text(patternDataScope == .mivoClear
                 ? "Focused social time recorded through Mivo Clear BETA."
                 : "Saved scrolling sessions from the last \(patternRangeDays) days.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
        }
    }

    private var personalizedPatternSection: some View {
        let insights = appVM.personalizedPatternInsights(limit: 3)
        let enoughHistory = appVM.truthChecks.count >= 3 || appVM.sessions.count >= 3
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Mivo noticed", systemImage: "lightbulb.fill")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                Spacer()
                Text(enoughHistory ? "Based on your data" : "Still learning")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.accent)
            }

            if !enoughHistory {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete \(max(0, 3 - appVM.truthChecks.count)) more truth check\(3 - appVM.truthChecks.count == 1 ? "" : "s") to connect your estimates with apps and session triggers.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                    ProgressView(value: Double(min(3, appVM.truthChecks.count)), total: 3)
                        .tint(MivoColors.accent)
                }
            } else if let primary = insights.first {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: primary.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                        .frame(width: 38, height: 38)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(primary.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.screenTimeInk)
                        Text(primary.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                        Text(primary.evidence)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(MivoColors.textMuted)
                            .lineSpacing(2)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("TRY TOMORROW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    Text(primary.tomorrowExperiment)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .lineSpacing(3)
                }
                .padding(.top, 2)

                ForEach(Array(insights.dropFirst())) { insight in
                    Divider().overlay(MivoColors.border.opacity(0.5))
                    Label(insight.title, systemImage: insight.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(2)
                }
            } else {
                Text("Mivo has enough history and will show the next supported pattern after your next truth check.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.34), lineWidth: 1)
        }
    }

    private var experimentHistorySection: some View {
        let completed = appVM.weeklyExperiments.filter { $0.status == .completed }
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("7-day experiments", systemImage: "flask.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Spacer()
                Text("\(completed.count) complete")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.textMuted)
            }

            if completed.isEmpty {
                Text("Your first before-and-after result will appear here after an approved experiment runs for seven days.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            } else {
                ForEach(completed.prefix(4)) { experiment in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(experiment.title)
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text(experimentOutcomeLabel(experiment))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(experiment.outcome == .helped ? MivoColors.blue : MivoColors.textSecondary)
                        }
                        HStack(spacing: 8) {
                            experimentBar("Before", value: experimentMetric(experiment.baselineMetrics, experiment: experiment), maxValue: experimentMetricMax(experiment))
                            experimentBar("During", value: experimentMetric(experiment.resultMetrics ?? experiment.baselineMetrics, experiment: experiment), maxValue: experimentMetricMax(experiment))
                        }
                    }
                    .padding(12)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.42), lineWidth: 1))
    }

    private func experimentBar(_ title: String, value: Double, maxValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text(experimentDisplay(value)) }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MivoColors.border.opacity(0.45))
                    Capsule().fill(MivoColors.blue).frame(width: proxy.size.width * min(1, value / max(1, maxValue)))
                }
            }.frame(height: 7)
        }.frame(maxWidth: .infinity)
    }

    private func experimentMetric(_ metrics: ExperimentMetrics, experiment: WeeklyExperiment) -> Double {
        switch experiment.type {
        case .protectedWindow: return Double(metrics.outsideWindowMinutes)
        case .reduceExtensions: return metrics.extensionRate * 100
        case .strongerFriction: return metrics.cancellationRate * 100
        }
    }
    private func experimentMetricMax(_ experiment: WeeklyExperiment) -> Double {
        max(experimentMetric(experiment.baselineMetrics, experiment: experiment), experimentMetric(experiment.resultMetrics ?? experiment.baselineMetrics, experiment: experiment), 1)
    }
    private func experimentDisplay(_ value: Double) -> String { value >= 100 ? "\(Int(value))" : String(format: "%.0f", value) }
    private func experimentOutcomeLabel(_ experiment: WeeklyExperiment) -> String {
        switch experiment.outcome { case .helped: return "Helped"; case .worsened: return "Different direction"; default: return "No clear change" }
    }

    // MARK: - Selected-day Mivo scrolling

    var screenTimeInfographic: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mivo scrolling")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text(selectedDateLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }

                Spacer()

                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("TOTAL TIME SCROLLED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                Text(formatDuration(selectedDayTotalMinutes))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(selectedSessions.isEmpty
                     ? "No scrolling sessions were recorded through Mivo on this day."
                     : "Scrolling recorded through completed Mivo sessions on this day.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)

                Rectangle()
                    .fill(MivoColors.border.opacity(0.38))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    selectedDaySummaryMetric("Sessions", value: "\(selectedSessions.count)")
                    selectedDaySummaryMetric("Planned", value: formatDuration(selectedDayPlannedMinutes))
                    selectedDaySummaryMetric("Extended", value: "\(selectedDayExtendedCount)")
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: MivoColors.screenTimeInk.opacity(0.06), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectedDateLabel), \(formatDuration(selectedDayTotalMinutes)) recorded through Mivo")
    }

    private func selectedDaySummaryMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingScreenTimeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Screen Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text("Allow Screen Time and Mivo will show Apple’s live Device Activity report here.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [MivoColors.card, MivoColors.surface.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder
    private var realScreenTimeReportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
                Text("Live iOS Screen Time report")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Spacer()
            }

            if #available(iOS 16.0, *) {
                MivoReadableScreenTimeSummaryCard(compact: false)
            } else {
                Text("Real Screen Time reports require iOS 16 or later.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Text("Live data from Apple’s DeviceActivityReport API.")
                .font(.system(size: 11))
                .foregroundColor(MivoColors.textMuted)
        }
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MivoColors.border.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Calendar

    var statisticsDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your patterns")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text(statisticsCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 0) {
                dashboardMetric("Today", value: formatDuration(todayLoggedMinutes))
                dashboardMetric("Average", value: formatDuration(averageSessionMinutes))
                dashboardMetric("Longest", value: longestScrollText)
            }

            dashboardDivider
            weeklyTrendChart
            dashboardDivider
            chartButton(.habits) { sessionQualityChart }
            dashboardDivider
            chartButton(.windows) { timeWindowChart }
            dashboardDivider
            chartButton(.triggers) { intentionChart }
            aiInsightCard
        }
        .padding(18)
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: MivoColors.screenTimeInk.opacity(0.06), radius: 12, y: 6)
        .sheet(item: $activeStatDetail) { kind in
            StatDetailSheet(kind: kind, sessions: appVM.sessions, dayPartStats: dayPartStats)
        }
    }

    private var patternsToWorkOn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MivoFeatureIcon(systemName: "target", tint: MivoColors.accent, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patterns to work on")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text("Small shifts, backed by your sessions.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }
            }

            patternWorkRow(
                icon: "sunrise.fill",
                title: strongestScrollWindow,
                detail: mostFrequentScrollWindow,
                kind: .windows
            )
            patternWorkRow(
                icon: "plus.circle.fill",
                title: "Extensions",
                detail: "\(extendedRate)% of saved sessions",
                kind: .habits
            )
        }
    }

    private func patternWorkRow(icon: String, title: String, detail: String, kind: StatDetailKind) -> some View {
        Button {
            activeStatDetail = kind
        } label: {
            HStack(spacing: 11) {
                MivoFeatureIcon(systemName: icon, tint: MivoColors.accent, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MivoColors.border.opacity(0.26)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(MivoColors.border.opacity(0.42))
            .frame(height: 1)
    }

    private func dashboardMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartButton<Content: View>(_ kind: StatDetailKind, @ViewBuilder content: () -> Content) -> some View {
        Button {
            activeStatDetail = kind
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    private func chartHeading(_ title: String, subtitle: String, legend: [(String, Color)] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .padding(.top, 4)
            }

            if !legend.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(item.1)
                                .frame(width: 7, height: 7)
                            Text(item.0)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(MivoColors.textMuted)
                        }
                    }
                }
            }
        }
    }

    private var weeklyTrendChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scrolling trend")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text("Actual compared with planned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }

                Spacer(minLength: 8)
                patternRangeSelector
            }

            HStack(spacing: 12) {
                chartLegend("Actual", tint: MivoColors.accent)
                chartLegend("Planned", tint: MivoColors.blue)
            }

            if appVM.sessions.isEmpty {
                chartEmptyState("Complete a session to start the trend line.")
            } else {
                GeometryReader { proxy in
                    let points = recentDayPoints
                    let maxValue = max(points.flatMap { [$0.actualMinutes, $0.plannedMinutes] }.max() ?? 0, 1)
                    let usableHeight = max(proxy.size.height - 24, 1)
                    let step = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : proxy.size.width

                    ZStack(alignment: .bottomLeading) {
                        ForEach(0..<3, id: \.self) { line in
                            Path { path in
                                let y = usableHeight * CGFloat(line) / 2
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                            .stroke(MivoColors.border.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }

                        trendPath(points: points, keyPath: \.plannedMinutes, width: proxy.size.width, height: usableHeight, maxValue: maxValue)
                            .stroke(MivoColors.blue.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        trendPath(points: points, keyPath: \.actualMinutes, width: proxy.size.width, height: usableHeight, maxValue: maxValue)
                            .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            if patternRangeDays <= 7 || shouldShowTrendLabel(index: index, count: points.count) {
                                Circle()
                                    .fill(MivoColors.accent)
                                    .frame(width: 7, height: 7)
                                    .position(
                                        x: CGFloat(index) * step,
                                        y: usableHeight - (CGFloat(point.actualMinutes) / CGFloat(maxValue) * usableHeight)
                                    )
                            }
                        }

                        HStack {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                Text(shouldShowTrendLabel(index: index, count: points.count) ? point.label : "")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(MivoColors.textMuted)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 18)
                    }
                }
                .frame(height: 150)
            }
        }
        .contentShape(Rectangle())
    }

    private var patternRangeSelector: some View {
        HStack(spacing: 3) {
            rangeButton(days: 7, title: "7 Days")
            rangeButton(days: 30, title: "30 Days")
        }
        .padding(3)
        .background(MivoColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart range")
    }

    private func rangeButton(days: Int, title: String) -> some View {
        Button {
            HapticsService.selection()
            withAnimation(.easeOut(duration: 0.18)) {
                patternRangeDays = days
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(patternRangeDays == days ? MivoColors.white : MivoColors.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(patternRangeDays == days ? MivoColors.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chartLegend(_ title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
    }

    private var sessionQualityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartHeading("Session quality", subtitle: "Intentional sessions compared with extensions and emergency use.")

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(sessionQualityPoints) { point in
                    VStack(spacing: 7) {
                        Text("\(point.value)%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.screenTimeInk)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(point.tint)
                            .frame(height: max(4, CGFloat(point.value) * 0.72))
                            .frame(maxHeight: 74, alignment: .bottom)
                        Text(point.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
        }
        .contentShape(Rectangle())
    }

    private func shouldShowTrendLabel(index: Int, count: Int) -> Bool {
        guard count > 7 else { return true }
        let stride = max(1, count / 6)
        return index == 0 || index == count - 1 || index.isMultiple(of: stride)
    }

    private var timeWindowChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartHeading("When scrolling happens", subtitle: strongestScrollWindow)
            VStack(spacing: 10) {
                ForEach(dayPartStats, id: \.name) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MivoColors.border.opacity(0.25))
                                Capsule()
                                    .fill(item.tint)
                                    .frame(width: item.minutes == 0 ? 0 : max(8, proxy.size.width * item.share))
                            }
                        }
                        .frame(height: 10)
                        Text(item.minutes == 0 ? "0m" : formatDuration(item.minutes))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.screenTimeInk)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var intentionChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartHeading("Why you opened", subtitle: behaviorSummary)

            if intentionChartPoints.isEmpty {
                chartEmptyState("Your intention breakdown will appear after the first session.")
            } else {
                VStack(spacing: 10) {
                    ForEach(intentionChartPoints) { point in
                        VStack(spacing: 5) {
                            HStack {
                                Text(point.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(MivoColors.screenTimeInk)
                                    .lineLimit(1)
                                Spacer()
                                Text(point.detail)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(MivoColors.border.opacity(0.25))
                                    Capsule()
                                        .fill(point.tint)
                                        .frame(width: max(8, proxy.size.width * CGFloat(point.value) / 100))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var compactAIRead: some View {
        let insight = aiStatInsights.first
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight?.icon ?? "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 30, height: 30)
                .background(insight?.tint ?? MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(insight?.title ?? "Mivo is still learning")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(insight?.body ?? "Complete a session to unlock a useful pattern read.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func chartEmptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(MivoColors.textMuted)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
    }

    private func trendPath(
        points: [PatternDayPoint],
        keyPath: KeyPath<PatternDayPoint, Int>,
        width: CGFloat,
        height: CGFloat,
        maxValue: Int
    ) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            let step = points.count > 1 ? width / CGFloat(points.count - 1) : width
            for (index, point) in points.enumerated() {
                let value = point[keyPath: keyPath]
                let location = CGPoint(
                    x: CGFloat(index) * step,
                    y: height - (CGFloat(value) / CGFloat(maxValue) * height)
                )
                if index == 0 { path.move(to: location) }
                else { path.addLine(to: location) }
            }
        }
    }

    // Tappable wrapper for a stat tile
    private func statTileButton(_ kind: StatDetailKind, title: String, value: String, icon: String, tint: Color) -> some View {
        Button { activeStatDetail = kind } label: {
            statTile(title, value: value, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    // Tappable wrapper for a behavior card
    @ViewBuilder
    private func behaviorCardButton<Content: View>(_ kind: StatDetailKind, @ViewBuilder content: () -> Content) -> some View {
        Button { activeStatDetail = kind } label: {
            content()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .padding(8)
        }
    }

    private func statTile(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 28, height: 28)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .padding(14)
        .frame(minHeight: 112, alignment: .topLeading)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var scrollBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "hand.draw", title: "Scroll", subtitle: scrollBehaviorSummary)

            VStack(spacing: 6) {
                compactMetricRow("Most frequent", value: mostFrequentScrollWindow)
                compactMetricRow("Most time", value: highestDurationScrollWindow)
                compactMetricRow("Longest", value: longestScrollDetail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "waveform.path", title: "Windows", subtitle: strongestScrollWindow)

            VStack(spacing: 8) {
                ForEach(dayPartStats, id: \.name) { item in
                    rhythmRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var triggerMapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "map.fill", title: "Triggers", subtitle: triggerMapSummary)

            VStack(spacing: 6) {
                compactMetricRow("Top urge", value: topUrgeText)
                compactMetricRow("Most regretted", value: mostRegrettedTriggerText)
                compactMetricRow("Emergency", value: "\(emergencyUnlockCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func rhythmRow(_ item: DayPartStat) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Spacer()
                Text(item.minutes == 0 ? "No logged sessions" : "\(formatDuration(item.minutes)) · \(item.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MivoColors.border.opacity(0.28))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.tint)
                        .frame(width: max(7, geo.size.width * item.share))
                }
            }
            .frame(height: 8)
        }
    }

    private var behaviorMixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "brain.head.profile", title: "Habits", subtitle: behaviorSummary)

            VStack(spacing: 6) {
                compactMetricRow("Top reason", value: mostCommonIntention)
                compactMetricRow("Extended", value: "\(extendedRate)%")
                compactMetricRow("Intentional", value: reflectionWinRateText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "sparkles", title: "AI Insight", subtitle: aiInsightSubtitle)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(aiStatInsights.prefix(2).enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.heroText)
                            .frame(width: 28, height: 28)
                            .background(insight.tint)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(MivoColors.screenTimeInk)
                            Text(insight.body)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(3)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(MivoColors.surfaceRaised.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.35), lineWidth: 1))
    }

    private var screenTimeSummaryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "iphone.gen3", title: "Apple Screen Time", subtitle: screenTimeSummaryText)

            if appVM.deviceActivityPerAppSeconds.isEmpty {
                Text("Top-app numeric details will appear here when iOS publishes a cached report. The live report above remains the source of truth.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(topCachedApps, id: \.key) { app in
                        insightMetricRow(prettyBundleName(app.key), value: formatDuration(app.value / 60))
                    }
                }
            }
        }
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 30, height: 30)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer()
        }
    }

    private func insightMetricRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.screenTimeInk)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private func compactMetricRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(monthNames[viewMonth]) \(String(viewYear))")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text("Darker days had more logged scrolling")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                }
                Spacer()
                HStack(spacing: 2) {
                    Button { goToPrevMonth() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(MivoColors.surface.opacity(0.62))
                            .clipShape(Circle())
                    }
                    Button { goToNextMonth() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isNextDisabled ? MivoColors.border : MivoColors.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(MivoColors.surface.opacity(0.62))
                            .clipShape(Circle())
                    }
                    .disabled(isNextDisabled)
                }
            }

            HStack {
                ForEach(weekdayLabels, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MivoColors.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 5) {
                ForEach(0..<weeks.count, id: \.self) { wi in
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { di in
                            let day = weeks[wi][di]
                            if let day {
                                let key = dateKey(year: viewYear, month: viewMonth, day: day)
                                let minutes = (dayMap[key] ?? []).reduce(0) { $0 + $1.actualDuration }
                                let isToday = key == todayKey
                                let isSelected = day == selectedDay

                                Button {
                                    selectedDay = day
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(calendarDayColor(minutes: minutes, selected: isSelected))
                                        if isToday && !isSelected {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(MivoColors.accent, lineWidth: 1.5)
                                        }
                                        Text("\(day)")
                                            .font(.system(size: 12, weight: isToday || isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? MivoColors.heroText : MivoColors.screenTimeInk)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text("Less")
                ForEach([0.12, 0.3, 0.52, 0.78], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(MivoColors.accent.opacity(opacity))
                        .frame(width: 15, height: 7)
                }
                Text("More")
                Spacer()
                Text("\(monthSessionCount) sessions")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(MivoColors.textMuted)
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.42), lineWidth: 1))
    }

    var insightSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Day view")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .textCase(.uppercase)
                    Text(selectedDateLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                }
                Spacer()
                Text(formatDuration(selectedDayTotalMinutes))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
            }
            .padding(16)

            if selectedSessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.accent)
                    Text("No sessions logged on this day.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 7) {
                        HStack {
                            Text("Actual")
                            Spacer()
                            Text("\(formatDuration(selectedDayTotalMinutes)) of \(formatDuration(selectedDayPlannedMinutes)) planned")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MivoColors.border.opacity(0.28))
                                Capsule()
                                    .fill(selectedDayTotalMinutes > selectedDayPlannedMinutes ? MivoColors.timerRed : MivoColors.accent)
                                    .frame(width: proxy.size.width * selectedDayPlanProgress)
                            }
                        }
                        .frame(height: 8)
                    }

                    HStack(spacing: 0) {
                        dayInlineMetric("Sessions", value: "\(selectedSessions.count)")
                        dayInlineMetric("Extended", value: "\(selectedDayExtendedCount)")
                        dayInlineMetric("Emergency", value: "\(selectedDayEmergencyCount)")
                    }

                    HStack(spacing: 12) {
                        dayLabel("Reason", value: selectedDayTopIntention)
                        dayLabel("Urge", value: selectedDayTopUrge)
                    }

                    Rectangle()
                        .fill(MivoColors.border.opacity(0.42))
                        .frame(height: 1)

                    VStack(spacing: 0) {
                        ForEach(Array(selectedSessions.sorted { $0.startTime < $1.startTime }.enumerated()), id: \.element.id) { index, session in
                            selectedDaySessionRow(session)
                            if index < selectedSessions.count - 1 {
                                Rectangle()
                                    .fill(MivoColors.border.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.leading, 24)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.42), lineWidth: 1))
    }

    private func dayInlineMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayLabel(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedDaySessionRow(_ session: Session) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.extendedOnce ? MivoColors.timerRed : MivoColors.accent)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTime(session))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(session.intention.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(session.actualDuration))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(session.actualDuration > session.plannedDuration ? "over plan" : "within plan")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(session.actualDuration > session.plannedDuration ? MivoColors.timerRed : MivoColors.textMuted)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Computed

    var dayMap: [String: [Session]] {
        var map: [String: [Session]] = [:]
        for s in appVM.sessions {
            map[s.date, default: []].append(s)
        }
        return map
    }

    private var monthSessionCount: Int {
        (1...daysInMonth).reduce(0) { count, day in
            count + (dayMap[dateKey(year: viewYear, month: viewMonth, day: day)]?.count ?? 0)
        }
    }

    private var monthMaxLoggedMinutes: Int {
        max(1, (1...daysInMonth).map { day in
            (dayMap[dateKey(year: viewYear, month: viewMonth, day: day)] ?? []).reduce(0) { $0 + $1.actualDuration }
        }.max() ?? 1)
    }

    private func calendarDayColor(minutes: Int, selected: Bool) -> Color {
        if selected { return MivoColors.accent }
        guard minutes > 0 else { return MivoColors.surface.opacity(0.58) }
        let intensity = min(1, Double(minutes) / Double(monthMaxLoggedMinutes))
        return MivoColors.accent.opacity(0.16 + intensity * 0.64)
    }

    var daysInMonth: Int {
        var comps = DateComponents()
        comps.year = viewYear
        comps.month = viewMonth + 1
        return Calendar.current.range(of: .day, in: .month, for: Calendar.current.date(from: comps)!)!.count
    }

    var firstDayOfWeek: Int {
        var comps = DateComponents()
        comps.year = viewYear
        comps.month = viewMonth + 1
        comps.day = 1
        let date = Calendar.current.date(from: comps)!
        return Calendar.current.component(.weekday, from: date) - 1
    }

    var weeks: [[Int?]] {
        var cells: [Int?] = Array(repeating: nil, count: firstDayOfWeek)
        cells += (1...daysInMonth).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0+7]) }
    }

    var selectedKey: String { dateKey(year: viewYear, month: viewMonth, day: selectedDay) }
    var selectedSessions: [Session] { dayMap[selectedKey] ?? [] }

    var selectedDayTotalMinutes: Int {
        selectedSessions.reduce(0) { $0 + $1.actualDuration }
    }

    var selectedDayPlannedMinutes: Int {
        selectedSessions.reduce(0) { $0 + $1.plannedDuration }
    }

    var selectedDayPlanProgress: CGFloat {
        guard selectedDayPlannedMinutes > 0 else { return 0 }
        return min(1, CGFloat(selectedDayTotalMinutes) / CGFloat(selectedDayPlannedMinutes))
    }

    var selectedDayExtendedCount: Int {
        selectedSessions.filter(\.extendedOnce).count
    }

    var selectedDayLongestMinutes: Int {
        selectedSessions.map(\.actualDuration).max() ?? 0
    }

    var selectedDayOverrunCount: Int {
        selectedSessions.filter { $0.actualDuration > $0.plannedDuration }.count
    }

    var selectedDayTopIntention: String {
        let grouped = Dictionary(grouping: selectedSessions, by: { $0.intention })
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "Not enough data" }
        return top.key.rawValue
    }

    var selectedDayTopUrge: String {
        let grouped = Dictionary(grouping: selectedSessions.compactMap(\.urgeReason), by: { $0 })
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "Not logged yet" }
        return top.key.rawValue
    }

    var selectedDayEmergencyCount: Int {
        selectedSessions.filter { $0.emergencyUnlockUsed == true }.count
    }

    var totalLoggedMinutes: Int {
        appVM.sessions.reduce(0) { $0 + $1.actualDuration }
    }

    private var displayedRangeMinutes: Int {
        switch patternDataScope {
        case .allScrolling:
            return sessionsInSelectedRange.reduce(0) { $0 + $1.actualDuration }
        case .mivoClear:
            let seconds = clearSessionsInSelectedRange.reduce(0) { $0 + $1.activeSeconds }
            return seconds == 0 ? 0 : max(1, Int(ceil(Double(seconds) / 60.0)))
        }
    }

    private var displayedRangeSessionCount: Int {
        switch patternDataScope {
        case .allScrolling: return sessionsInSelectedRange.count
        case .mivoClear: return clearSessionsInSelectedRange.count
        }
    }

    private var sessionsInSelectedRange: [Session] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(patternRangeDays - 1), to: calendar.startOfDay(for: Date())) ?? .distantPast
        let formatter = MivoDay.formatter
        return appVM.sessions.filter { session in
            guard let date = formatter.date(from: session.date) else { return false }
            return date >= cutoff
        }
    }

    private var clearSessionsInSelectedRange: [MivoClearSession] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(patternRangeDays - 1), to: calendar.startOfDay(for: Date())) ?? .distantPast
        return clearStore.sessions.filter { session in
            guard let date = ISO8601DateFormatter().date(from: session.startedAt) else { return false }
            return date >= cutoff
        }
    }

    var todayLoggedMinutes: Int {
        appVM.sessions.filter { $0.date == todayKey }.reduce(0) { $0 + $1.actualDuration }
    }

    var averageSessionMinutes: Int {
        guard !appVM.sessions.isEmpty else { return 0 }
        return max(1, totalLoggedMinutes / appVM.sessions.count)
    }

    var longestSession: Session? {
        appVM.sessions.max(by: { $0.actualDuration < $1.actualDuration })
    }

    var longestScrollText: String {
        guard let longestSession else { return "0m" }
        return formatDuration(longestSession.actualDuration)
    }

    var longestScrollDetail: String {
        guard let session = longestSession else { return "No scrolls yet" }
        return "\(formatDuration(session.actualDuration)) · \(session.intention.rawValue.lowercased())"
    }

    var totalOverPlanMinutes: Int {
        appVM.sessions.reduce(0) { total, session in
            total + max(0, session.actualDuration - session.plannedDuration)
        }
    }

    var emergencyUnlockCount: Int {
        appVM.sessions.filter { $0.emergencyUnlockUsed == true }.count
    }

    var averageOverrunText: String {
        let overrunSessions = appVM.sessions.filter { $0.actualDuration > $0.plannedDuration }
        guard !overrunSessions.isEmpty else { return "No overruns" }
        let minutes = overrunSessions.reduce(0) { $0 + max(0, $1.actualDuration - $1.plannedDuration) } / overrunSessions.count
        return formatDuration(max(1, minutes))
    }

    var overrunRate: Int {
        guard !appVM.sessions.isEmpty else { return 0 }
        let overruns = appVM.sessions.filter { $0.actualDuration > $0.plannedDuration }.count
        return Int((Double(overruns) / Double(appVM.sessions.count) * 100).rounded())
    }

    var extendedRate: Int {
        guard !appVM.sessions.isEmpty else { return 0 }
        let extended = appVM.sessions.filter { $0.extendedOnce }.count
        return Int((Double(extended) / Double(appVM.sessions.count) * 100).rounded())
    }

    var statisticsCaption: String {
        appVM.sessions.isEmpty ? "Mivo will build this from your sessions." : "A quieter view of \(appVM.sessions.count) logged sessions."
    }

    private var recentDayPoints: [PatternDayPoint] {
        let calendar = Calendar.current
        let keyFormatter = MivoDay.formatter
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "E"
        let grouped = Dictionary(grouping: appVM.sessions, by: \.date)

        return (0..<patternRangeDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = keyFormatter.string(from: date)
            let sessions = grouped[key] ?? []
            return PatternDayPoint(
                id: key,
                label: labelFormatter.string(from: date),
                actualMinutes: sessions.reduce(0) { $0 + $1.actualDuration },
                plannedMinutes: sessions.reduce(0) { $0 + $1.plannedDuration }
            )
        }
    }

    private var sessionQualityPoints: [PatternBarPoint] {
        let count = max(appVM.sessions.count, 1)
        let emergency = appVM.sessions.filter { $0.emergencyUnlockUsed == true }.count
        let extended = appVM.sessions.filter { $0.extendedOnce && $0.emergencyUnlockUsed != true }.count
        let intentional = max(0, appVM.sessions.count - extended - emergency)

        return [
            PatternBarPoint(id: "intentional", label: "Intentional", value: Int((Double(intentional) / Double(count) * 100).rounded()), detail: "\(intentional)", tint: MivoColors.secondary),
            PatternBarPoint(id: "extended", label: "Extended", value: Int((Double(extended) / Double(count) * 100).rounded()), detail: "\(extended)", tint: MivoColors.accent),
            PatternBarPoint(id: "emergency", label: "Emergency", value: Int((Double(emergency) / Double(count) * 100).rounded()), detail: "\(emergency)", tint: MivoColors.timerRed)
        ]
    }

    private var intentionChartPoints: [PatternBarPoint] {
        let total = max(appVM.sessions.count, 1)
        let colors: [Color] = [MivoColors.accent, MivoColors.blue, MivoColors.secondary, MivoColors.timerOrange]
        return intentionGroups
            .sorted { $0.value.count > $1.value.count }
            .enumerated()
            .map { index, group in
                let percentage = Int((Double(group.value.count) / Double(total) * 100).rounded())
                return PatternBarPoint(
                    id: group.key.rawValue,
                    label: group.key.rawValue,
                    value: percentage,
                    detail: "\(percentage)% · \(group.value.count)x",
                    tint: colors[index % colors.count]
                )
            }
    }

    private var dayPartStats: [DayPartStat] {
        let buckets: [(name: String, range: Range<Int>, tint: Color)] = [
            ("Morning", 6..<12, MivoColors.blue),
            ("Afternoon", 12..<17, MivoColors.accent),
            ("Evening", 17..<21, MivoColors.secondary),
            ("Night", 0..<6, MivoColors.timerRed)
        ]

        var values: [(name: String, count: Int, minutes: Int, tint: Color)] = buckets.map { bucket in
            let sessions = appVM.sessions.filter { session in
                guard let hour = hourOfSession(session) else { return false }
                if bucket.name == "Night" { return hour >= 21 || bucket.range.contains(hour) }
                return bucket.range.contains(hour)
            }
            return (bucket.name, sessions.count, sessions.reduce(0) { $0 + $1.actualDuration }, bucket.tint)
        }

        if values.allSatisfy({ $0.minutes == 0 }) {
            values = buckets.map { ($0.name, 0, 0, $0.tint) }
        }

        let maxMinutes = max(values.map(\.minutes).max() ?? 0, 1)
        return values.map {
            DayPartStat(name: $0.name, count: $0.count, minutes: $0.minutes, share: CGFloat(Double($0.minutes) / Double(maxMinutes)), tint: $0.tint)
        }
    }

    var strongestScrollWindow: String {
        guard let top = dayPartStats.max(by: { $0.minutes < $1.minutes }), top.minutes > 0 else {
            return "No session rhythm yet"
        }
        return "\(top.name) is your strongest logged window"
    }

    var mostFrequentScrollWindow: String {
        guard let top = dayPartStats.max(by: { $0.count < $1.count }), top.count > 0 else {
            return "No scrolls yet"
        }
        return "\(top.name) · \(top.count)x"
    }

    var highestDurationScrollWindow: String {
        guard let top = dayPartStats.max(by: { $0.minutes < $1.minutes }), top.minutes > 0 else {
            return "No time logged"
        }
        return "\(top.name) · \(formatDuration(top.minutes))"
    }

    var scrollBehaviorSummary: String {
        if appVM.sessions.isEmpty { return "Waiting for your first scroll" }
        return "\(mostFrequentScrollWindow) is your most repeated window"
    }

    var mostCommonIntention: String {
        guard let top = intentionGroups.max(by: { $0.value.count < $1.value.count }) else { return "Not enough data" }
        return top.key.rawValue
    }

    var longestIntention: String {
        let ranked = intentionGroups.map { key, sessions in
            (key: key, average: sessions.reduce(0) { $0 + $1.actualDuration } / max(sessions.count, 1))
        }
        guard let top = ranked.max(by: { $0.average < $1.average }) else { return "Not enough data" }
        return top.key.rawValue
    }

    var intentionGroups: [Intention: [Session]] {
        Dictionary(grouping: appVM.sessions, by: { $0.intention })
    }

    var reflectionWinRateText: String {
        let reflected = appVM.sessions.compactMap(\.reflection)
        guard !reflected.isEmpty else { return "No reflections yet" }
        let wins = reflected.filter { $0 == .yes || $0 == .kindOf }.count
        let pct = Int((Double(wins) / Double(reflected.count) * 100).rounded())
        return "\(pct)%"
    }

    var baselineEstimateText: String {
        guard let minutes = appVM.onboardingProfile.scrollEstimateMinutes else { return "Not set" }
        return "\(minutes)m/day"
    }

    var behaviorSummary: String {
        appVM.sessions.isEmpty ? "Waiting for first session" : "\(mostCommonIntention.lowercased()) shows up most"
    }

    var topUrgeText: String {
        let grouped = Dictionary(grouping: appVM.sessions.compactMap(\.urgeReason), by: { $0 })
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "Not logged yet" }
        return top.key.rawValue
    }

    var notWorthItRateText: String {
        let outcomes = appVM.sessions.compactMap(\.outcomeScore)
        guard !outcomes.isEmpty else { return "No outcomes yet" }
        let count = outcomes.filter { $0 == .notWorthIt }.count
        return "\(Int((Double(count) / Double(outcomes.count) * 100).rounded()))%"
    }

    var mostRegrettedTriggerText: String {
        let regretted = appVM.sessions.filter { $0.outcomeScore == .notWorthIt }.compactMap(\.urgeReason)
        let grouped = Dictionary(grouping: regretted, by: { $0 })
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "Not enough data" }
        return top.key.rawValue
    }

    var triggerMapSummary: String {
        if appVM.sessions.isEmpty { return "Waiting for sessions" }
        return "\(topUrgeText) is the strongest recorded urge"
    }

    var triggerInsightText: String? {
        guard !appVM.sessions.isEmpty else { return nil }
        if emergencyUnlockCount > 0 {
            return "Emergency unlocks are your highest-friction moments. Mivo will treat these as signals when deciding whether more time should be allowed."
        }
        if topUrgeText != "Not logged yet" {
            return "\(topUrgeText) is showing up most. Before that urge, pick one tiny replacement action before opening the selected app."
        }
        return "Complete one new intervention session to start mapping urges to timing and outcomes."
    }

    private var aiInsightSubtitle: String {
        if appVM.sessions.isEmpty && appVM.deviceActivityMinutesToday == nil {
            return "Waiting for enough user data"
        }

        let readableSignals = appVM.sessions.count + appVM.deviceActivityPerAppSeconds.count
        return "Reading \(readableSignals) behavior signal\(readableSignals == 1 ? "" : "s")"
    }

    private var aiStatInsights: [AIStatInsight] {
        var insights: [AIStatInsight] = []

        if appVM.sessions.isEmpty {
            insights.append(AIStatInsight(
                title: "Start with one real session",
                body: "Mivo needs completed sessions before it can learn your triggers, timing, and follow-through.",
                icon: "play.circle.fill",
                tint: MivoColors.accent
            ))
        } else {
            insights.append(primaryBehaviorInsight)

            if overrunRate >= 40 {
                insights.append(AIStatInsight(
                    title: "Your limit is getting stretched",
                    body: "\(overrunRate)% of sessions run over plan. Try choosing a shorter limit first, then intentionally extend only when it still feels useful.",
                    icon: "timer",
                    tint: MivoColors.timerRed
                ))
            } else if extendedRate >= 30 {
                insights.append(AIStatInsight(
                    title: "Extensions are the pressure point",
                    body: "\(extendedRate)% of sessions were extended. Add a clearer reason before opening the app so extensions feel like a choice.",
                    icon: "arrow.triangle.2.circlepath",
                    tint: MivoColors.secondary
                ))
            } else {
                insights.append(AIStatInsight(
                    title: "Session control looks steady",
                    body: "Most sessions are staying near plan. Keep the opening pause short and specific so it stays easy to follow.",
                    icon: "checkmark.seal.fill",
                    tint: MivoColors.accent
                ))
            }

            if let topWindow = dayPartStats.max(by: { $0.minutes < $1.minutes }), topWindow.minutes > 0 {
                insights.append(AIStatInsight(
                    title: "\(topWindow.name) is your scroll window",
                    body: "You have logged \(formatDuration(topWindow.minutes)) there. Set your strictest app protection around this time block.",
                    icon: "waveform.path.ecg",
                    tint: topWindow.tint
                ))
            }
        }

        if let screenTimeInsight {
            insights.append(screenTimeInsight)
        } else if hasScreenTimeAccess {
            insights.append(AIStatInsight(
                title: "Screen Time is connected",
                body: "Apple’s live report is visible above. When iOS publishes cached app totals, Mivo will fold them into these insights automatically.",
                icon: "iphone.gen3",
                tint: MivoColors.blue
            ))
        }

        if insights.count < 3 {
            insights.append(AIStatInsight(
                title: "Feedback gets sharper over time",
                body: "More sessions and reflections help Mivo separate quick checks from patterns that deserve stronger intervention.",
                icon: "brain.head.profile",
                tint: MivoColors.secondary
            ))
        }

        return Array(insights.prefix(4))
    }

    private var primaryBehaviorInsight: AIStatInsight {
        let top = mostCommonIntention
        let response: String
        switch intentionGroups.max(by: { $0.value.count < $1.value.count })?.key {
        case .killTime:
            response = "Your most common trigger is killing time. Use a 5-minute session for this so the app opens as a deliberate break, not a default."
        case .bored:
            response = "Boredom is showing up often. Add a tiny offline replacement before opening the app: water, stretch, or one message you actually meant to send."
        case .relax:
            response = "Relaxing is the main reason. Keep the session boundary visible so rest does not quietly turn into recovery debt."
        case .lookingForSomethingSpecific:
            response = "You usually open with a purpose. Write the target in your head first, then leave when that specific task is done."
        case nil:
            response = "Mivo has sessions, but not enough consistent intention data yet."
        }

        return AIStatInsight(
            title: "\(top) is the main pattern",
            body: response,
            icon: "target",
            tint: MivoColors.accent
        )
    }

    private var screenTimeInsight: AIStatInsight? {
        if let topApp = topCachedApps.first {
            return AIStatInsight(
                title: "\(prettyBundleName(topApp.key)) leads today",
                body: "Cached Screen Time shows \(formatDuration(topApp.value / 60)) here. If this is a protected app, make your next session short and intentional.",
                icon: "app.badge",
                tint: MivoColors.blue
            )
        }

        if let minutes = appVM.deviceActivityMinutesToday {
            return AIStatInsight(
                title: "Today’s Screen Time is available",
                body: "Cached Apple data shows \(formatDuration(minutes)) today. Compare that with your Mivo session total to see what happened outside protected openings.",
                icon: "chart.bar.fill",
                tint: MivoColors.blue
            )
        }

        return nil
    }

    var screenTimeSummaryText: String {
        if let minutes = appVM.deviceActivityMinutesToday {
            return "Cached today total: \(formatDuration(minutes))"
        }
        if let generated = appVM.deviceActivityReportGeneratedAt {
            return "Cached report: \(generated.formatted(date: .omitted, time: .shortened))"
        }
        return "Live report only right now"
    }

    var topCachedApps: [(key: String, value: Int)] {
        Array(appVM.deviceActivityPerAppSeconds.sorted { $0.value > $1.value }.prefix(3))
    }

    var topCachedAppText: String {
        guard let app = topCachedApps.first else {
            return hasScreenTimeAccess ? "Live report only" : "Needs Screen Time"
        }
        return "\(prettyBundleName(app.key)) · \(formatDuration(app.value / 60))"
    }

    var hasScreenTimeAccess: Bool {
        FamilyControlsManager.shared.cachedAuthorizationStatus() == true
    }

    var screenTimeCaption: String {
        hasScreenTimeAccess ? "Live Apple Screen Time report. No placeholder totals." : "Connect Screen Time to turn this into live usage."
    }

    var selectedDateLabel: String {
        var comps = DateComponents()
        comps.year = viewYear; comps.month = viewMonth + 1; comps.day = selectedDay
        let date = Calendar.current.date(from: comps)!
        let fmt = DateFormatter(); fmt.dateStyle = .long
        return fmt.string(from: date)
    }

    var todayKey: String {
        let fmt = MivoDay.formatter
        return fmt.string(from: Date())
    }

    var isNextDisabled: Bool {
        let cal = Calendar.current
        let now = Date()
        let nowY = cal.component(.year, from: now)
        let nowM = cal.component(.month, from: now) - 1
        return viewYear > nowY || (viewYear == nowY && viewMonth >= nowM)
    }

    func dateKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month + 1, day)
    }

    func sessionTime(_ s: Session) -> String {
        let fmt = ISO8601DateFormatter()
        if let date = fmt.date(from: s.startTime) {
            let disp = DateFormatter(); disp.dateFormat = "h:mm a"
            return disp.string(from: date)
        }
        return s.startTime
    }

    func hourOfSession(_ s: Session) -> Int? {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: s.startTime) else { return nil }
        return Calendar.current.component(.hour, from: date)
    }

    func prettyBundleName(_ bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    func refreshPatternsData() {
        appVM.refreshScreenTimeData()
        weeklyReportSnapshot = appVM.makeCurrentWeeklyReportSnapshot()
        weeklyReportBaselineMinutes = max(1, appVM.adaptiveScreenTimePlan().baselineMinutes)
        refreshPulse.toggle()
        keepSelectedDayValid()
    }

    func keepSelectedDayValid() {
        selectedDay = min(selectedDay, daysInMonth)
    }

    func goToPrevMonth() {
        if viewMonth == 0 { viewMonth = 11; viewYear -= 1 }
        else { viewMonth -= 1 }
        selectedDay = 1
    }

    func goToNextMonth() {
        if isNextDisabled { return }
        if viewMonth == 11 { viewMonth = 0; viewYear += 1 }
        else { viewMonth += 1 }
        selectedDay = 1
    }
}

// MARK: - Stat Detail Sheet

private struct StatDetailSheet: View {
    let kind: StatDetailKind
    let sessions: [Session]
    let dayPartStats: [DayPartStat]

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch kind {
        case .todayScrolled:  return "Today's Scrolling"
        case .longestScroll:  return "Longest Scrolls"
        case .avgScroll:      return "Session Length"
        case .emergency:      return "Emergency Unlocks"
        case .scrollBehavior: return "Scroll Behavior"
        case .windows:        return "Time Windows"
        case .triggers:       return "Trigger Map"
        case .habits:         return "Habit Profile"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .todayScrolled:  todayDetail
        case .longestScroll:  longestDetail
        case .avgScroll:      avgDetail
        case .emergency:      emergencyDetail
        case .scrollBehavior: scrollBehaviorDetail
        case .windows:        windowsDetail
        case .triggers:       triggersDetail
        case .habits:         habitsDetail
        }
    }

    // ── Today scrolled ──────────────────────────────────────────────────────
    private var todayDetail: some View {
        let fmt = MivoDay.formatter
        let todayKey = fmt.string(from: Date())
        let todaySessions = sessions.filter { $0.date == todayKey }
        let total = todaySessions.reduce(0) { $0 + $1.actualDuration }

        return Group {
            summaryRow("Sessions today", value: "\(todaySessions.count)")
            summaryRow("Total time", value: formatDuration(total))
            summaryRow("Avg per session", value: todaySessions.isEmpty ? "—" : formatDuration(total / max(1, todaySessions.count)))

            detailSectionHeader("Today's sessions")
            if todaySessions.isEmpty {
                emptyState("No sessions logged today yet.")
            } else {
                ForEach(todaySessions.sorted { $0.startTime > $1.startTime }) { session in
                    sessionRow(session)
                }
            }

            detailSectionHeader("Recent days comparison")
            recentDaysComparisonRows()
        }
    }

    // ── Longest scroll ───────────────────────────────────────────────────────
    private var longestDetail: some View {
        let sorted = sessions.sorted { $0.actualDuration > $1.actualDuration }
        let top = Array(sorted.prefix(10))

        return Group {
            summaryRow("All-time longest", value: top.first.map { formatDuration($0.actualDuration) } ?? "—")
            summaryRow("Total sessions", value: "\(sessions.count)")

            detailSectionHeader("Top 10 longest sessions")
            if top.isEmpty {
                emptyState("Complete a session to see it here.")
            } else {
                ForEach(Array(top.enumerated()), id: \.offset) { i, session in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(i == 0 ? MivoColors.accent : MivoColors.textMuted)
                            .frame(width: 22)
                        sessionRow(session)
                    }
                }
            }
        }
    }

    // ── Average scroll ───────────────────────────────────────────────────────
    private var avgDetail: some View {
        let avg = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.actualDuration } / sessions.count
        let buckets: [(label: String, range: ClosedRange<Int>)] = [
            ("< 5 min", 0...4), ("5–15 min", 5...15), ("15–30 min", 16...30),
            ("30–60 min", 31...60), ("> 60 min", 61...Int.max)
        ]
        let counts = buckets.map { b in sessions.filter { b.range.contains($0.actualDuration) }.count }
        let maxCount = max(counts.max() ?? 0, 1)

        return Group {
            summaryRow("Average duration", value: formatDuration(avg))
            summaryRow("Median duration", value: medianDuration())
            summaryRow("Total sessions", value: "\(sessions.count)")

            detailSectionHeader("Session length distribution")
            VStack(spacing: 10) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { i, bucket in
                    HStack(spacing: 10) {
                        Text(bucket.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.screenTimeInk)
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(MivoColors.border.opacity(0.28))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(MivoColors.accent.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * CGFloat(counts[i]) / CGFloat(maxCount)))
                            }
                        }
                        .frame(height: 10)
                        Text("\(counts[i])")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
            .padding(14)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            detailSectionHeader("Recent 10 sessions")
            ForEach(sessions.suffix(10).reversed()) { s in sessionRow(s) }
        }
    }

    // ── Emergency ────────────────────────────────────────────────────────────
    private var emergencyDetail: some View {
        let emergencySessions = sessions.filter { $0.emergencyUnlockUsed == true }
        let byUrge = Dictionary(grouping: emergencySessions.compactMap(\.urgeReason), by: { $0 })
        let topUrge = byUrge.max(by: { $0.value.count < $1.value.count })

        return Group {
            summaryRow("Total emergency unlocks", value: "\(emergencySessions.count)")
            summaryRow("Rate", value: sessions.isEmpty ? "0%" : "\(Int(Double(emergencySessions.count) / Double(sessions.count) * 100))%")
            summaryRow("Top trigger", value: topUrge?.key.rawValue ?? "Not logged")

            detailSectionHeader("Emergency sessions")
            if emergencySessions.isEmpty {
                emptyState("No emergency unlocks yet. That's good!")
            } else {
                ForEach(emergencySessions.sorted { $0.startTime > $1.startTime }) { session in
                    sessionRow(session)
                }
            }
        }
    }

    // ── Scroll behavior card ─────────────────────────────────────────────────
    private var scrollBehaviorDetail: some View {
        let sorted = sessions.sorted { $0.actualDuration > $1.actualDuration }

        return Group {
            detailSectionHeader("Time-of-day breakdown")
            windowsBarChart

            detailSectionHeader("By intention")
            intentionBreakdown

            detailSectionHeader("Longest sessions")
            ForEach(sorted.prefix(5)) { sessionRow($0) }
        }
    }

    // ── Windows card ─────────────────────────────────────────────────────────
    private var windowsDetail: some View {
        Group {
            detailSectionHeader("Sessions by time of day")
            windowsBarChart

            ForEach(dayPartStats, id: \.name) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stat.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(MivoColors.screenTimeInk)
                        Spacer()
                        Text("\(stat.count) sessions · \(stat.minutes == 0 ? "—" : formatDuration(stat.minutes))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                    Text(stat.minutes == 0 ? "No sessions in this window" : windowInsight(stat))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                }
                .padding(14)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // ── Trigger map card ─────────────────────────────────────────────────────
    private var triggersDetail: some View {
        let urgeGroups = Dictionary(grouping: sessions.compactMap(\.urgeReason), by: { $0 })
            .sorted { $0.value.count > $1.value.count }
        let regrettedGroups = Dictionary(grouping: sessions.filter { $0.outcomeScore == .notWorthIt }.compactMap(\.urgeReason), by: { $0 })
        let total = urgeGroups.reduce(0) { $0 + $1.value.count }

        return Group {
            summaryRow("Unique triggers logged", value: "\(urgeGroups.count)")
            summaryRow("Total trigger logs", value: "\(total)")
            summaryRow("Emergency rate", value: sessions.isEmpty ? "0%" : "\(Int(Double(sessions.filter { $0.emergencyUnlockUsed == true }.count) / Double(sessions.count) * 100))%")

            detailSectionHeader("All triggers ranked")
            if urgeGroups.isEmpty {
                emptyState("Log your urge when starting a session to see this.")
            } else {
                VStack(spacing: 8) {
                    ForEach(urgeGroups, id: \.key) { urge, sessionList in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(urge.rawValue)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(MivoColors.screenTimeInk)
                                if let regreted = regrettedGroups[urge] {
                                    Text("\(regreted.count) of \(sessionList.count) regretted")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(MivoColors.timerRed)
                                }
                            }
                            Spacer()
                            Text("\(sessionList.count)×")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.accent)
                        }
                        .padding(12)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // ── Habits card ──────────────────────────────────────────────────────────
    private var habitsDetail: some View {
        let intentionGroups = Dictionary(grouping: sessions, by: { $0.intention })
            .sorted { $0.value.count > $1.value.count }
        let reflections = sessions.compactMap(\.reflection)
        let wins = reflections.filter { $0 == .yes || $0 == .kindOf }.count
        let winPct = reflections.isEmpty ? 0 : Int(Double(wins) / Double(reflections.count) * 100)

        return Group {
            summaryRow("Intentional rate", value: reflections.isEmpty ? "—" : "\(winPct)%")
            summaryRow("Sessions with reflection", value: "\(reflections.count) / \(sessions.count)")
            summaryRow("Extension rate", value: sessions.isEmpty ? "0%" : "\(Int(Double(sessions.filter { $0.extendedOnce }.count) / Double(sessions.count) * 100))%")

            detailSectionHeader("Sessions by intention")
            if intentionGroups.isEmpty {
                emptyState("Complete sessions to see your intention profile.")
            } else {
                let total = sessions.count
                VStack(spacing: 8) {
                    ForEach(intentionGroups, id: \.key) { intention, sessionList in
                        let pct = total > 0 ? Int(Double(sessionList.count) / Double(total) * 100) : 0
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intention.rawValue)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(MivoColors.screenTimeInk)
                                Text("\(sessionList.count) sessions · avg \(formatDuration(sessionList.reduce(0) { $0 + $1.actualDuration } / max(1, sessionList.count)))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                            Spacer()
                            Text("\(pct)%")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.accent)
                        }
                        .padding(12)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Shared sub-views

    private var windowsBarChart: some View {
        VStack(spacing: 8) {
            ForEach(dayPartStats, id: \.name) { stat in
                HStack(spacing: 10) {
                    Text(stat.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .frame(width: 68, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(MivoColors.border.opacity(0.28))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stat.tint)
                                .frame(width: max(4, geo.size.width * stat.share))
                        }
                    }
                    .frame(height: 14)
                    Text(stat.minutes == 0 ? "—" : formatDuration(stat.minutes))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.textSecondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var intentionBreakdown: some View {
        let groups = Dictionary(grouping: sessions, by: { $0.intention })
            .sorted { $0.value.count > $1.value.count }
        return VStack(spacing: 6) {
            ForEach(groups, id: \.key) { intention, list in
                HStack {
                    Text(intention.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Spacer()
                    Text("\(list.count) sessions · \(formatDuration(list.reduce(0) { $0 + $1.actualDuration } / max(1, list.count))) avg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .padding(10)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func recentDaysComparisonRows() -> some View {
        let cal = Calendar.current
        let fmt = MivoDay.formatter
        let days: [(label: String, key: String)] = (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let label = offset == 0 ? "Today" : offset == 1 ? "Yesterday" : {
                let d = DateFormatter(); d.dateFormat = "EEE"
                return d.string(from: date)
            }()
            return (label, fmt.string(from: date))
        }
        let sessionsByDay = Dictionary(grouping: sessions, by: { $0.date })
        return VStack(spacing: 6) {
            ForEach(days, id: \.key) { day in
                let daySessions = sessionsByDay[day.key] ?? []
                let total = daySessions.reduce(0) { $0 + $1.actualDuration }
                HStack {
                    Text(day.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .frame(width: 72, alignment: .leading)
                    Text(daySessions.isEmpty ? "No sessions" : "\(daySessions.count) session\(daySessions.count == 1 ? "" : "s") · \(formatDuration(total))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                    Spacer()
                }
                .padding(10)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTimeLabel(session))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.screenTimeInk)
                HStack(spacing: 6) {
                    Text(session.intention.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                    if let urge = session.urgeReason {
                        Text("· \(urge.rawValue)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MivoColors.textMuted)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(session.actualDuration))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                if session.emergencyUnlockUsed == true {
                    Text("⚠ Emergency")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MivoColors.timerRed)
                }
            }
        }
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.screenTimeInk)
        }
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailSectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundColor(MivoColors.textMuted)
            .padding(.top, 4)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(MivoColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Computed helpers

    private func medianDuration() -> String {
        guard !sessions.isEmpty else { return "—" }
        let sorted = sessions.map(\.actualDuration).sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        return formatDuration(median)
    }

    private func windowInsight(_ stat: DayPartStat) -> String {
        let pct = Int(stat.share * 100)
        return "\(pct)% of your total logged session time"
    }

    private func sessionTimeLabel(_ session: Session) -> String {
        let fmt = ISO8601DateFormatter()
        if let date = fmt.date(from: session.startTime) {
            let disp = DateFormatter(); disp.dateFormat = "MMM d, h:mm a"
            return disp.string(from: date)
        }
        return session.date
    }
}

#if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
@available(iOS 16.0, *)
private struct MivoLiveDeviceActivityReport: View {
    private let context = DeviceActivityReport.Context("MivoPatternsTotalActivity")

    private var filter: DeviceActivityFilter {
        let interval = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 24 * 60 * 60)
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            devices: .init([.iPhone, .iPad]),
            applications: Set<ApplicationToken>(),
            categories: Set<ActivityCategoryToken>(),
            webDomains: Set<WebDomainToken>()
        )
    }

    var body: some View {
        DeviceActivityReport(context, filter: filter)
            .background(MivoColors.surfaceRaised.opacity(0.42))
    }
}
#else
@available(iOS 16.0, *)
private struct MivoLiveDeviceActivityReport: View {
    var body: some View {
        Text("Device Activity is unavailable in this build.")
            .font(.system(size: 12))
            .foregroundColor(MivoColors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MivoColors.surfaceRaised.opacity(0.42))
    }
}
#endif
