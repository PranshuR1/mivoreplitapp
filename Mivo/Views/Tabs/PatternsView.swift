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
                VStack(alignment: .leading, spacing: 0) {
                    MivoGreetingBar(name: firstName)
                        .padding(.top, 6)

                    rangeMetricSection(derived)
                    MivoHairline()

                    windowsKeptSection(derived)
                    MivoHairline()

                    noticedSection
                    MivoHairline()

                    weeklyReportsSection(derived.weeklyReportRows)

                    // Moved here from Settings' "Mivo Tools" page: it is a
                    // report, so it sits with the other reports.
                    if expansion.isEnabled(.monthlyEffectReport) {
                        MivoHairline()
                        monthlyEffectSection
                    }
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - 2.1 Range metric + 2.2 bar chart

    private func rangeMetricSection(_ derived: Derived) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Intentional scrolling · \(range.label)")

            HStack(alignment: .bottom) {
                Text(formatDuration(derived.totalMinutes))
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                    .tracking(Font.mivoTracking(-0.04, at: 46))
                    .foregroundColor(MivoColors.ink)

                Spacer(minLength: 12)

                MivoSegmentedChips(
                    options: PatternsRange.allCases.map { ($0, $0.label) },
                    selection: $range
                )
            }
            .padding(.top, 8)

            Text(rangeNote(derived))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .padding(.top, 12)

            PatternsBarChart(points: derived.barPoints, range: range)
                .padding(.top, 26)
        }
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rangeNote(_ derived: Derived) -> String {
        guard derived.totalWindowCount > 0 else {
            return "Complete a session to start building this view."
        }
        let delta = derived.previousPeriodMinutes - derived.totalMinutes
        let keptClause = "\(derived.keptPercent)% of windows kept."
        guard derived.previousPeriodMinutes > 0, abs(delta) >= 1 else { return keptClause }
        let direction = delta > 0 ? "Down" : "Up"
        return "\(direction) \(formatDuration(abs(delta))) from the \(range == .week ? "week" : "four weeks") before. \(keptClause)"
    }

    // MARK: - 2.3 Windows kept

    private func windowsKeptSection(_ derived: Derived) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoEyebrow(text: "Windows kept")

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(derived.keptPercent)%")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                Text("\(derived.keptCount) of \(derived.totalWindowCount) windows")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }

            MivoProgressTrack(fraction: derived.totalWindowCount > 0 ? Double(derived.keptCount) / Double(derived.totalWindowCount) : 0)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 2.4 What Mivo noticed

    @ViewBuilder
    private var noticedSection: some View {
        let insights = appVM.personalizedPatternInsights(limit: 3)
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                MivoEyebrow(text: "What Mivo noticed")
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        PatternsNoticedRow(
                            dotColor: noticedDotColors[index % noticedDotColors.count],
                            text: boldingFigures(in: insight.detail)
                        )
                    }
                }
            }
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noticedDotColors: [Color] { [MivoColors.accent, MivoColors.info, MivoColors.kept] }

    // MARK: - 2.5 Weekly reports

    private func weeklyReportsSection(_ rows: [WeeklyReportRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Weekly reports")
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.weekOffset) { index, row in
                    NavigationLink {
                        WeeklyReportView(initialWeekOffset: row.weekOffset)
                    } label: {
                        MivoSettingsRow(
                            label: row.title,
                            value: row.subtitle,
                            valueColor: MivoColors.inkMuted
                        )
                    }
                    .buttonStyle(.plain)
                    if index < rows.count - 1 {
                        MivoHairline(soft: true)
                    }
                }
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 2.6 Monthly effect

    private var monthlyEffectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Monthly")
                .padding(.bottom, 4)

            NavigationLink {
                MonthlyEffectReportView().environmentObject(appVM)
            } label: {
                MivoSettingsRow(
                    label: "Mivo Effect",
                    value: "Your monthly change",
                    valueColor: MivoColors.inkMuted
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    ? "No sessions logged"
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
