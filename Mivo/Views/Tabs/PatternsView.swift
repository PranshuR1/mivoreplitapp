import SwiftUI

struct PatternsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared

    @State private var range: PatternsRange = .week

    /// Every value the screen renders, derived once per `body` evaluation
    /// instead of through separate computed properties. The old shape called
    /// `sessionsInRange` independently from five call sites — each re-parsing
    /// every stored session's date with a freshly constructed `DateFormatter`
    /// — which is exactly the kind of per-render cost that shows up as jank.
    private struct Derived {
        let totalMinutes: Int
        let previousPeriodMinutes: Int
        let keptCount: Int
        let totalWindowCount: Int
        let keptPercent: Int
        let barPoints: [PatternsBarPoint]
        let weeklyReportRows: [WeeklyReportRow]
    }

    var body: some View {
        let derived = deriveData()

        return ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    MivoScreenHeader(
                        eyebrow: range == .week ? "Last 7 days" : "Last 30 days",
                        title: "Patterns"
                    )
                    .padding(.top, 6)

                    // No sessions in this range: one card that says so and
                    // what to do next, instead of 0m, an empty chart and
                    // "0% windows kept", which read as failing.
                    if derived.totalWindowCount == 0 {
                        noSessionsSection
                    } else {
                        rangeMetricSection(derived)
                        windowsKeptSection(derived)
                    }
                    appUsageSection
                    reelAttentionSection
                    noticedSection
                    reportsSection(derived.weeklyReportRows)
                }
                .padding(.horizontal, MivoMetrics.tabPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Range metric + bar chart

    private func rangeMetricSection(_ derived: Derived) -> some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Intentional scrolling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)

                    Spacer(minLength: 8)

                    MivoSegmentedChips(
                        options: PatternsRange.allCases.map { ($0, $0.label) },
                        selection: $range
                    )
                }

                Text(formatDuration(derived.totalMinutes))
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                    .tracking(Font.mivoTracking(-0.04, at: 46))
                    .foregroundColor(MivoColors.ink)
                    .padding(.top, 12)

                Text(rangeNote(derived))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .padding(.top, 8)

                PatternsBarChart(points: derived.barPoints, range: range, height: derived.totalMinutes > 0 ? 132 : 28)
                    .padding(.top, 22)
            }
        }
    }

    // MARK: - No sessions yet

    private var noSessionsSection: some View {
        let hasAppVisits = appVM.appPurposeReport(days: range.rawValue).hasData
        return MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Intentional scrolling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)

                    Spacer(minLength: 8)

                    MivoSegmentedChips(
                        options: PatternsRange.allCases.map { ($0, $0.label) },
                        selection: $range
                    )
                }

                Text("No sessions yet")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 24))
                    .foregroundColor(MivoColors.ink)
                    .padding(.top, 14)

                Text(hasAppVisits
                     ? "Timed windows you start from Home show up here, with how many you kept. Your visits to apps inside Mivo are below."
                     : "Open an app through Mivo and say what it's for. Each visit adds to your patterns, and kept windows show up here.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if !hasAppVisits {
                    MivoPrimaryButton(label: "Open an app on purpose") {
                        HapticsService.selection()
                        appVM.pendingAppWindow = AppWindowRequest(app: nil)
                    }
                    .padding(.top, 18)
                }
            }
        }
    }

    private func rangeNote(_ derived: Derived) -> String {
        let delta = derived.previousPeriodMinutes - derived.totalMinutes
        let keptClause = "\(derived.keptPercent)% of windows kept."
        guard derived.previousPeriodMinutes > 0, abs(delta) >= 1 else { return keptClause }
        let direction = delta > 0 ? "Down" : "Up"
        return "\(direction) \(formatDuration(abs(delta))) from the \(range == .week ? "week" : "four weeks") before. \(keptClause)"
    }

    // MARK: - Windows kept

    private func windowsKeptSection(_ derived: Derived) -> some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Windows kept")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer(minLength: 8)
                    Text("\(derived.keptCount) of \(derived.totalWindowCount) windows")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }

                Text("\(derived.keptPercent)%")
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .tracking(Font.mivoTracking(-0.03, at: 32))
                    .foregroundColor(MivoColors.ink)
                    .padding(.top, 10)

                MivoProgressTrack(fraction: derived.totalWindowCount > 0 ? Double(derived.keptCount) / Double(derived.totalWindowCount) : 0)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: - Apps in Mivo

    /// Only once an app has been opened inside Mivo in this range.
    @ViewBuilder
    private var appUsageSection: some View {
        let report = appVM.appPurposeReport(days: range.rawValue)
        if report.hasData {
            AppUsageCard(report: report)
        }
    }

    // MARK: - Short-video attention

    /// Only once short videos have been watched inside Mivo in this range.
    @ViewBuilder
    private var reelAttentionSection: some View {
        let report = appVM.reelAttentionReport(days: range.rawValue)
        if report.sessionCount > 0 {
            ReelAttentionCard(report: report, plan: ReelPlan(report: report))
        }
    }

    // MARK: - What Mivo noticed

    @ViewBuilder
    private var noticedSection: some View {
        let insights = appVM.personalizedPatternInsights(limit: 3)
        if !insights.isEmpty {
            MivoCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What Mivo noticed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            PatternsNoticedRow(
                                dotColor: noticedDotColors[index % noticedDotColors.count],
                                text: boldingFigures(in: insight.detail)
                            )
                        }
                    }
                }
            }
        }
    }

    private var noticedDotColors: [Color] { [MivoColors.accent, MivoColors.info, MivoColors.kept] }

    // MARK: - Reports
    //
    // The weekly reports and the monthly Mivo Effect are all reports, so they
    // share one list instead of two sections with a heading each.

    private func reportsSection(_ rows: [WeeklyReportRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Reports")

            MivoListGroup {
                ForEach(Array(rows.enumerated()), id: \.element.weekOffset) { index, row in
                    if index > 0 {
                        MivoListDivider()
                    }
                    NavigationLink {
                        WeeklyReportView(initialWeekOffset: row.weekOffset)
                    } label: {
                        MivoListRow(icon: "calendar", title: row.title, subtitle: row.subtitle)
                    }
                    .buttonStyle(MivoRowPressStyle())
                }

                if expansion.isEnabled(.monthlyEffectReport) {
                    if !rows.isEmpty {
                        MivoListDivider()
                    }
                    NavigationLink {
                        MonthlyEffectReportView().environmentObject(appVM)
                    } label: {
                        MivoListRow(icon: "sparkles", title: "Mivo Effect", subtitle: "Your monthly change")
                    }
                    .buttonStyle(MivoRowPressStyle())
                }
            }
        }
    }

    // MARK: - Derivation

    private var firstName: String {
        appVM.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    private struct WeeklyReportRow {
        let weekOffset: Int
        let title: String
        let subtitle: String
    }

    /// One pass over `appVM.sessions` (and one shared `DateFormatter`) per
    /// render, instead of a formatter and a full array scan per stat.
    private func deriveData() -> Derived {
        let calendar = Calendar.current
        let dayFormatter = MivoDay.formatter
        let today = calendar.startOfDay(for: Date())

        let sessionDates: [(session: Session, date: Date)] = appVM.sessions.compactMap { session in
            guard let date = dayFormatter.date(from: session.date) else { return nil }
            return (session, date)
        }

        let cutoff = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: today) ?? .distantPast
        let sessionsInRange = sessionDates.filter { $0.date >= cutoff }.map(\.session)

        let previousEnd = calendar.date(byAdding: .day, value: -range.rawValue, to: today) ?? .distantPast
        let previousStart = calendar.date(byAdding: .day, value: -(range.rawValue * 2 - 1), to: today) ?? .distantPast
        let previousPeriodMinutes = sessionDates
            .filter { $0.date >= previousStart && $0.date < previousEnd }
            .reduce(0) { $0 + $1.session.actualDuration }

        let totalMinutes = sessionsInRange.reduce(0) { $0 + $1.actualDuration }
        // A window counts as "kept" when the session that used it did not run
        // past the length chosen for it — the plain reading of "kept the
        // window you set."
        let keptCount = sessionsInRange.filter { $0.actualDuration <= $0.plannedDuration }.count
        let totalWindowCount = sessionsInRange.count
        let keptPercent = totalWindowCount > 0 ? Int((Double(keptCount) / Double(totalWindowCount) * 100).rounded()) : 0

        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = range == .week ? "E" : "d"
        let grouped = Dictionary(grouping: appVM.sessions, by: \.date)
        let barPoints: [PatternsBarPoint] = (0..<range.rawValue).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = dayFormatter.string(from: date)
            let minutes = (grouped[key] ?? []).reduce(0) { $0 + $1.actualDuration }
            return PatternsBarPoint(id: key, label: labelFormatter.string(from: date), minutes: minutes, isToday: offset == 0)
        }

        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "MMM d"
        let weeklyReportRows: [WeeklyReportRow] = (0..<4).compactMap { offset in
            guard let anchor = calendar.date(byAdding: .weekOfYear, value: -offset, to: Date()),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return nil }
            let weekSessions = sessionDates
                .filter { $0.date >= interval.start && $0.date < interval.end }
                .map(\.session)
            guard !weekSessions.isEmpty || offset == 0 else { return nil }
            let minutes = weekSessions.reduce(0) { $0 + $1.actualDuration }
            let kept = weekSessions.filter { $0.actualDuration <= $0.plannedDuration }.count
            let keptPct = weekSessions.isEmpty ? 0 : Int((Double(kept) / Double(weekSessions.count) * 100).rounded())
            return WeeklyReportRow(
                weekOffset: -offset,
                title: "Week of \(weekFormatter.string(from: interval.start))",
                subtitle: weekSessions.isEmpty
                    ? "No sessions yet"
                    : "\(formatDuration(minutes)) intentional · \(keptPct)% kept"
            )
        }

        return Derived(
            totalMinutes: totalMinutes,
            previousPeriodMinutes: previousPeriodMinutes,
            keptCount: keptCount,
            totalWindowCount: totalWindowCount,
            keptPercent: keptPercent,
            barPoints: barPoints,
            weeklyReportRows: weeklyReportRows
        )
    }

    /// Wraps digit runs (with an optional trailing `%`, `m`, `h`, or `x`) in
    /// Semibold, so a dynamically generated sentence still lands the "key figure
    /// at Semibold" rule from the handoff without needing per-string markup.
    private func boldingFigures(in text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: #"\d+(\.\d+)?\s?(%|m|h|x)?\b"#) else { return result }
        let full = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: full).reversed() {
            guard let range = Range(match.range, in: text),
                  let attrRange = Range(range, in: result) else { continue }
            result[attrRange].font = .system(size: 13.5, weight: .semibold)
        }
        return result
    }
}
