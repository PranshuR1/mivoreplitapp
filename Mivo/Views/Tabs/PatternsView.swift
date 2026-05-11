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

struct PatternsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewYear: Int
    @State private var viewMonth: Int
    @State private var selectedDay: Int
    @State private var showFocus = false
    @State private var refreshPulse = false

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
                    statisticsDashboard
                    calendarCard
                    insightSection
                        .padding(.bottom, 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
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
                        .tracking(0.3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(MivoColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: MivoColors.accent.opacity(0.3), radius: 12, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            refreshPatternsData()
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
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshPatternsData()
            }
        }
    }

    // MARK: - Screen Time Infographic

    var screenTimeInfographic: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Screen Time")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(screenTimeCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }

                Spacer()

                Image(systemName: hasScreenTimeAccess ? "waveform.path.ecg" : "lock.open")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(hasScreenTimeAccess ? MivoColors.accent : MivoColors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if hasScreenTimeAccess {
                realScreenTimeReportCard
            } else {
                missingScreenTimeCard
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 14, y: 7)
    }

    private var missingScreenTimeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Screen Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Allow Screen Time and Mivo will show Apple’s live Device Activity report here.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(MivoColors.heroText)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
            }

            if #available(iOS 16.0, *) {
                MivoLiveDeviceActivityReport()
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text("Real Screen Time reports require iOS 16 or later.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Text("This panel is real Screen Time data from Apple’s DeviceActivityReport API. The main app cannot copy those private totals out of the report extension, so Mivo renders the Apple report directly.")
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(MivoColors.heroText)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Calendar

    var statisticsDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Behavior Statistics")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(statisticsCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile("Today scrolled", value: formatDuration(todayLoggedMinutes), icon: "clock.fill", tint: MivoColors.accent)
                statTile("Longest scroll", value: longestScrollText, icon: "arrow.up.right", tint: MivoColors.blue)
                statTile("Avg scroll", value: appVM.sessions.isEmpty ? "0m" : formatDuration(averageSessionMinutes), icon: "chart.bar.xaxis", tint: MivoColors.secondary)
                statTile("Emergency", value: "\(emergencyUnlockCount)", icon: "exclamationmark.triangle.fill", tint: MivoColors.timerRed)
            }

            scrollBehaviorCard
            triggerMapCard
            rhythmCard
            behaviorMixCard
            aiInsightCard
            screenTimeSummaryStrip
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 14, y: 7)
    }

    private func statTile(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 28, height: 28)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
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
        .background(MivoColors.heroText.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var scrollBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "hand.draw", title: "Scroll behavior", subtitle: scrollBehaviorSummary)

            VStack(spacing: 8) {
                insightMetricRow("Most times scrolled", value: mostFrequentScrollWindow)
                insightMetricRow("Most time spent", value: highestDurationScrollWindow)
                insightMetricRow("Longest single scroll", value: longestScrollDetail)
                insightMetricRow("Average over limit", value: averageOverrunText)
                insightMetricRow("Top cached app", value: topCachedAppText)
            }
        }
        .padding(14)
        .background(MivoColors.heroText.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "waveform.path", title: "Scroll windows", subtitle: strongestScrollWindow)

            VStack(spacing: 10) {
                ForEach(dayPartStats, id: \.name) { item in
                    rhythmRow(item)
                }
            }
        }
        .padding(14)
        .background(MivoColors.heroText.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var triggerMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "map.fill", title: "Trigger Map", subtitle: triggerMapSummary)

            VStack(spacing: 8) {
                insightMetricRow("Strongest urge", value: topUrgeText)
                insightMetricRow("Hardest time", value: highestDurationScrollWindow)
                insightMetricRow("Most regretted", value: mostRegrettedTriggerText)
                insightMetricRow("Emergency unlocks", value: "\(emergencyUnlockCount)")
                insightMetricRow("Not worth it", value: notWorthItRateText)
            }

            if let trigger = triggerInsightText {
                Text(trigger)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MivoColors.white.opacity(0.46))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .background(MivoColors.heroText.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rhythmRow(_ item: DayPartStat) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "brain.head.profile", title: "What Mivo knows", subtitle: behaviorSummary)

            VStack(spacing: 8) {
                insightMetricRow("Most common reason", value: mostCommonIntention)
                insightMetricRow("Most common urge", value: topUrgeText)
                insightMetricRow("Longest trigger", value: longestIntention)
                insightMetricRow("Extended sessions", value: "\(extendedRate)%")
                insightMetricRow("Felt intentional", value: reflectionWinRateText)
                insightMetricRow("Baseline estimate", value: baselineEstimateText)
            }
        }
        .padding(14)
        .background(MivoColors.heroText.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "sparkles", title: "AI Insight", subtitle: aiInsightSubtitle)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(aiStatInsights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.heroText)
                            .frame(width: 28, height: 28)
                            .background(insight.tint)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            Text(insight.body)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(3)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(MivoColors.white.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [MivoColors.heroText.opacity(0.9), MivoColors.white.opacity(0.54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1))
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
        .background(MivoColors.heroText.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 30, height: 30)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
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
                .foregroundColor(MivoColors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    var calendarCard: some View {
        VStack(spacing: 0) {
            // Month nav
            HStack {
                Text("\(monthNames[viewMonth]) \(String(viewYear))")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .tracking(-0.4)
                Spacer()
                HStack(spacing: 4) {
                    Button { goToPrevMonth() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    Button { goToNextMonth() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16))
                            .foregroundColor(isNextDisabled ? MivoColors.border : MivoColors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(isNextDisabled)
                }
            }
            .padding(.bottom, 4)

            Text("Session calendar")
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)

            // Weekday labels
            HStack {
                ForEach(weekdayLabels, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)

            // Calendar grid
            ForEach(0..<weeks.count, id: \.self) { wi in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { di in
                        let day = weeks[wi][di]
                        if let day {
                            let key = dateKey(year: viewYear, month: viewMonth, day: day)
                            let daySessions = dayMap[key] ?? []
                            let isToday = key == todayKey
                            let isSelected = day == selectedDay
                            let hasSessionData = !daySessions.isEmpty

                            Button {
                                selectedDay = day
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        if isSelected {
                                            Circle().fill(MivoColors.accent).frame(width: 30, height: 30)
                                        }
                                        Text("\(day)")
                                            .font(.system(size: 14, weight: isToday || isSelected ? .semibold : .regular))
                                            .foregroundColor(
                                                isSelected ? .white :
                                                isToday ? MivoColors.accent :
                                                MivoColors.textPrimary
                                            )
                                    }
                                    .frame(width: 30, height: 30)

                                    Rectangle()
                                        .fill(hasSessionData ? (isSelected ? MivoColors.accent : MivoColors.accentLight) : MivoColors.border)
                                        .frame(width: 28, height: 4)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).padding(.vertical, 2)
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)
        .padding(.bottom, 20)
    }

    var insightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights for \(selectedDateLabel)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .tracking(-0.4)

            if selectedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(MivoColors.accent)
                    Text("No logged sessions for this date.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("When you complete a Mivo session, this day will show timing, intention, overrun, and reflection data.")
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        selectedDayTile("Total", value: formatDuration(selectedDayTotalMinutes), icon: "clock")
                        selectedDayTile("Sessions", value: "\(selectedSessions.count)", icon: "number")
                        selectedDayTile("Longest", value: formatDuration(selectedDayLongestMinutes), icon: "arrow.up.right")
                        selectedDayTile("Emergency", value: "\(selectedDayEmergencyCount)", icon: "exclamationmark.triangle")
                    }

                    insightMetricRow("Primary reason", value: selectedDayTopIntention)
                        .padding(14)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    insightMetricRow("Primary urge", value: selectedDayTopUrge)
                        .padding(14)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    ForEach(selectedSessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sessionTime(session))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.textPrimary)
                                Text(session.intention.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textSecondary)
                                if let urge = session.urgeReason {
                                    Text("Urge: \(urge.rawValue)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                            }
                            Spacer()
                            Text(formatDuration(session.actualDuration))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                        }
                        .padding(14)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func selectedDayTile(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 28, height: 28)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 64)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Computed

    var dayMap: [String: [Session]] {
        var map: [String: [Session]] = [:]
        for s in appVM.sessions {
            map[s.date, default: []].append(s)
        }
        return map
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
        appVM.sessions.isEmpty ? "Mivo will build this from your sessions." : "\(appVM.sessions.count) logged sessions analyzed."
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
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
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
            .background(MivoColors.white.opacity(0.42))
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
            .background(MivoColors.white.opacity(0.42))
    }
}
#endif
