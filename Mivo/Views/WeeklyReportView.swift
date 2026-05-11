import SwiftUI

struct WeeklyReportView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    var weekDays: [String] {
        (0...6).reversed().map { offset -> String in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: date)
        }
    }

    var weekSessions: [Session] {
        let daySet = Set(weekDays)
        return appVM.sessions.filter { daySet.contains($0.date) }
    }

    var byDay: [String: [Session]] {
        var map: [String: [Session]] = [:]
        for s in weekSessions { map[s.date, default: []].append(s) }
        return map
    }

    var totalMinutes: Int { weekSessions.reduce(0) { $0 + $1.actualDuration } }
    var sessionCount: Int { weekSessions.count }
    var avgMinutes: Int { sessionCount > 0 ? totalMinutes / sessionCount : 0 }
    var overLimitCount: Int { weekSessions.filter { $0.actualDuration > $0.plannedDuration }.count }
    var reflectedCount: Int { weekSessions.filter { $0.reflection != nil }.count }
    var emergencyUnlockCount: Int { weekSessions.filter { $0.emergencyUnlockUsed == true }.count }
    var recoveredMinutes: Int { max(0, (appVM.onboardingProfile.scrollEstimateMinutes ?? totalMinutes) - totalMinutes) }

    var topIntention: String? {
        var counts: [String: Int] = [:]
        weekSessions.forEach { counts[$0.intention.rawValue, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var topUrge: String? {
        var counts: [String: Int] = [:]
        weekSessions.compactMap(\.urgeReason).forEach { counts[$0.rawValue, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var hardestWindow: String {
        appVM.makeCurrentWeeklyReportSnapshot().hardestWindow
    }

    var weeklyRecommendation: String {
        appVM.makeCurrentWeeklyReportSnapshot().recommendation
    }

    var weekTruthChecks: [TruthCheckGuess] {
        let daySet = Set(weekDays)
        return appVM.truthChecks.filter { daySet.contains($0.date) }
    }

    var avgTruthDiff: Int? {
        guard !weekTruthChecks.isEmpty else { return nil }
        let sum = weekTruthChecks.reduce(0) { $0 + ($1.guess - $1.actual) }
        return sum / weekTruthChecks.count
    }

    var hasData: Bool { !weekSessions.isEmpty }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18))
                                .foregroundColor(MivoColors.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        Text("Weekly Report")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.5)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.bottom, 8)

                    Text(dateRangeLabel)
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 28)

                    if !hasData {
                        emptyState
                    } else {
                        // Summary grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            SummaryStatCard(value: "\(sessionCount)", label: "Sessions")
                            SummaryStatCard(value: formatDuration(totalMinutes), label: "Total time")
                            SummaryStatCard(value: formatDuration(recoveredMinutes), label: "Recovered")
                            SummaryStatCard(
                                value: "\(emergencyUnlockCount)",
                                label: "Emergency",
                                alertColor: emergencyUnlockCount > 0 ? MivoColors.timerOrange : nil
                            )
                        }
                        .padding(.bottom, 28)

                        // Day by day
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Day by day")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)

                            VStack(spacing: 0) {
                                ForEach(weekDays.reversed(), id: \.self) { dateKey in
                                    let daySessions = byDay[dateKey] ?? []
                                    let dayTotal = daySessions.reduce(0) { $0 + $1.actualDuration }
                                    let isToday = dateKey == weekDays.last
                                    let label = isToday ? "Today" : dayLabel(for: dateKey)

                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(label)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(isToday ? MivoColors.accent : MivoColors.textPrimary)
                                            Text(shortDate(for: dateKey))
                                                .font(.system(size: 12))
                                                .foregroundColor(MivoColors.textMuted)
                                        }
                                        Spacer()
                                        if dayTotal > 0 {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(formatDuration(dayTotal))
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(MivoColors.textPrimary)
                                                Text("\(daySessions.count) session\(daySessions.count == 1 ? "" : "s")")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(MivoColors.textMuted)
                                            }
                                        } else {
                                            Text("—")
                                                .font(.system(size: 14))
                                                .foregroundColor(MivoColors.textMuted)
                                        }
                                    }
                                    .padding(14)
                                    if dateKey != weekDays.first {
                                        Divider().background(MivoColors.border)
                                    }
                                }
                            }
                            .background(MivoColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))
                        }
                        .padding(.bottom, 28)

                        // Insights
                        VStack(alignment: .leading, spacing: 12) {
                            Text("This week in numbers")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)

                            VStack(spacing: 12) {
                                if let top = topIntention {
                                    insightRow("Most common reason to scroll: \(top.lowercased())")
                                }
                                if let topUrge {
                                    insightRow("Most common urge: \(topUrge.lowercased())")
                                }
                                insightRow("Hardest time window: \(hardestWindow)")
                                if reflectedCount > 0 {
                                    insightRow("Reflected after \(reflectedCount) of \(sessionCount) sessions")
                                }
                                if let diff = avgTruthDiff {
                                    let text = diff == 0
                                        ? "Your daily time guesses were exactly right this week"
                                        : diff > 0
                                        ? "Your guesses were \(diff)m under your actual usage"
                                        : "Your guesses were \(abs(diff))m over your actual usage"
                                    insightRow(text)
                                }
                                if overLimitCount > 0 {
                                    insightRow("Went over your session limit \(overLimitCount) time\(overLimitCount == 1 ? "" : "s")")
                                }
                                if emergencyUnlockCount > 0 {
                                    insightRow("Used emergency unlock \(emergencyUnlockCount) time\(emergencyUnlockCount == 1 ? "" : "s")")
                                }
                                insightRow("Next week: \(weeklyRecommendation)")
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundColor(MivoColors.border)
            Text("No sessions this week")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
            Text("Start tracking sessions to get your weekly report.")
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    func insightRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(MivoColors.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(6)
        }
    }

    var dateRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let fmt = DateFormatter()
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        fmt.dateFormat = "MMM d"
        if let d1 = iso.date(from: first), let d2 = iso.date(from: last) {
            let fmt2 = DateFormatter(); fmt2.dateFormat = "MMM d, yyyy"
            return "\(fmt.string(from: d1)) – \(fmt2.string(from: d2))"
        }
        return ""
    }

    func dayLabel(for dateKey: String) -> String {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let date = iso.date(from: dateKey) else { return dateKey }
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    func shortDate(for dateKey: String) -> String {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let date = iso.date(from: dateKey) else { return dateKey }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

struct SummaryStatCard: View {
    let value: String
    let label: String
    var alertColor: Color? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(alertColor ?? MivoColors.textPrimary)
                .tracking(-0.5)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))
    }
}
