import SwiftUI
import UIKit

private struct WeeklyDayStat: Identifiable {
    let date: Date
    let dateKey: String
    let label: String
    let minutes: Int
    let sessionCount: Int

    var id: String { dateKey }
}

private struct WeeklyReportPreparedData {
    let selectedWeekDates: [Date]
    let selectedWeekKeys: [String]
    let weekSessions: [Session]
    let previousWeekSessions: [Session]
    let dayStats: [WeeklyDayStat]
    let elapsedDayStats: [WeeklyDayStat]
    let truthSummary: WeeklyTruthSummary
    let totalMinutes: Int
    let averageDailyMinutes: Int
    let previousAverageMinutes: Int
    let baselineMinutes: Int
    let reflectedCount: Int
    let extendedCount: Int
    let outcomeCount: Int
    let worthwhileCount: Int
    let topUrgeReason: UrgeReason?
    let maximumDayMinutes: Int
    let dateRangeLabel: String
    let impactBaselineMinutes: Int
    let impactMeasuredDays: Int
    let impactSessionCount: Int
    let weeklyReducedMinutes: Int
    let totalReducedMinutes: Int
    let hasImpactEstimate: Bool

    static let empty = WeeklyReportPreparedData(
        selectedWeekDates: [],
        selectedWeekKeys: [],
        weekSessions: [],
        previousWeekSessions: [],
        dayStats: [],
        elapsedDayStats: [],
        truthSummary: WeeklyTruthSummary(
            checkCount: 0,
            averageAccuracyScore: 0,
            totalForgottenMinutes: 0,
            averageSignedGapMinutes: 0,
            accuracyChangePoints: nil,
            topForgottenApp: nil,
            dailyAccuracyScores: []
        ),
        totalMinutes: 0,
        averageDailyMinutes: 0,
        previousAverageMinutes: 0,
        baselineMinutes: 1,
        reflectedCount: 0,
        extendedCount: 0,
        outcomeCount: 0,
        worthwhileCount: 0,
        topUrgeReason: nil,
        maximumDayMinutes: 1,
        dateRangeLabel: "",
        impactBaselineMinutes: 1,
        impactMeasuredDays: 0,
        impactSessionCount: 0,
        weeklyReducedMinutes: 0,
        totalReducedMinutes: 0,
        hasImpactEstimate: false
    )
}

struct WeeklyReportView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var page: Int
    @State private var weekOffset = 0
    @State private var reportData = WeeklyReportPreparedData.empty
    @State private var isPreparingReport = true
    @State private var sharePayload: WeeklyReportSharePayload?

    private let pageCount = 6
    private let calendar = Calendar.current

    init(initialPage: Int = 0, initialWeekOffset: Int = 0) {
        _page = State(initialValue: min(5, max(0, initialPage)))
        _weekOffset = State(initialValue: initialWeekOffset)
    }

    var body: some View {
        ZStack {
            reportBackground

            VStack(spacing: 0) {
                reportHeader

                Group {
                    if isPreparingReport {
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(MivoColors.accent)
                            Text("Preparing your weekly report")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TabView(selection: $page) {
                            averagePage.tag(0)
                            comparisonPage.tag(1)
                            dailyPage.tag(2)
                            reflectionPage.tag(3)
                            impactPage.tag(4)
                            recapPage.tag(5)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: page)
                    }
                }

                reportFooter
            }
        }
        .navigationBarHidden(true)
        .task(id: reportTaskID) { await prepareReport() }
        .onChange(of: page) { _, _ in
            HapticsService.selection()
        }
        .sheet(item: $sharePayload) { payload in
            WeeklyReportActivitySheet(items: [payload.image])
        }
    }

    private var reportBackground: some View {
        ZStack(alignment: .top) {
            MivoColors.background
                .ignoresSafeArea()

            Rectangle()
                .fill(MivoColors.blue.opacity(0.1))
                .frame(height: 220)
                .blur(radius: 72)
                .offset(y: -130)
                .ignoresSafeArea()
        }
    }

    private var reportHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    HapticsService.impact(style: .medium)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .frame(width: 42, height: 42)
                        .background(MivoColors.surfaceRaised.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close weekly report")

                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= page ? MivoColors.accent : MivoColors.border.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                }

                Button(action: shareReportImage) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .frame(width: 42, height: 42)
                        .background(MivoColors.surfaceRaised.opacity(0.72))
                        .clipShape(Circle())
                }
                .disabled(isPreparingReport)
                .opacity(isPreparingReport ? 0.45 : 1)
                .accessibilityLabel("Share weekly report")
            }

            HStack(spacing: 14) {
                Button {
                    guard weekOffset > -11 else { return }
                    HapticsService.selection()
                    weekOffset -= 1
                    page = 0
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundColor(weekOffset > -11 ? MivoColors.textSecondary : MivoColors.textMuted.opacity(0.45))
                .disabled(weekOffset <= -11)

                VStack(spacing: 2) {
                    Text(weekOffset == 0 ? "THIS WEEK" : "WEEKLY REPORT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    Text(dateRangeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    guard weekOffset < 0 else { return }
                    HapticsService.selection()
                    weekOffset += 1
                    page = 0
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundColor(weekOffset < 0 ? MivoColors.textSecondary : MivoColors.textMuted.opacity(0.45))
                .disabled(weekOffset >= 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var reportFooter: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    HapticsService.selection()
                    withAnimation { page -= 1 }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .frame(width: 54, height: 54)
                        .background(MivoColors.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }

            Button {
                HapticsService.impact(style: .medium)
                if page == pageCount - 1 {
                    dismiss()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                HStack(spacing: 9) {
                    Text(page == pageCount - 1 ? "Done" : "Continue")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: page == pageCount - 1 ? "checkmark" : "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(MivoColors.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(MivoColors.background.opacity(0.96))
        .disabled(isPreparingReport)
        .opacity(isPreparingReport ? 0.55 : 1)
    }

    private var averagePage: some View {
        reportPage {
            reportEyebrow("YOUR WEEK IN FOCUS")

            Text(hasData ? "You tracked an average of" : "Your weekly picture starts here")
                .reportSupportingText()

            Text(hasData ? formatDuration(averageDailyMinutes) : "No data yet")
                .font(.system(size: hasData ? 54 : 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)

            Text(hasData ? "per day in saved Mivo sessions" : "Save a session or complete a truth check to build this report.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(MivoColors.border.opacity(0.28), lineWidth: 22)
                Circle()
                    .trim(from: 0, to: baselineProgress)
                    .stroke(
                        MivoColors.accent,
                        style: StrokeStyle(lineWidth: 22, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.84), value: baselineProgress)

                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    Text(hasData ? "\(Int((baselineProgress * 100).rounded()))%" : "--")
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text("of your baseline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
            .frame(width: 220, height: 220)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            reportNote("This report uses saved Mivo sessions and truth checks. Apple’s live total remains available in Patterns.")
        }
    }

    private var comparisonPage: some View {
        reportPage {
            reportEyebrow("CHANGE OVER TIME")

            VStack(spacing: 8) {
                Text(comparisonHeadline)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundColor(comparisonTint)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text(comparisonSubtitle)
                    .reportSupportingText()
            }

            VStack(spacing: 20) {
                comparisonBar(
                    title: "This week",
                    value: averageDailyMinutes,
                    tint: MivoColors.accent
                )
                comparisonBar(
                    title: comparisonReferenceTitle,
                    value: comparisonReferenceMinutes,
                    tint: MivoColors.blue
                )
            }
            .padding(20)
            .background(MivoColors.surfaceRaised.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.5)))
            .padding(.vertical, 12)

            if hasData {
                reportNote(comparisonNote)
            } else {
                reportNote("Mivo needs at least one saved session before it can compare this week.")
            }
        }
    }

    private var dailyPage: some View {
        reportPage {
            reportEyebrow("DAILY RHYTHM")

            Text("Your week at a glance")
                .reportTitle()

            Text("The chart shows minutes from saved scrolling sessions.")
                .reportSupportingText()

            dailyBars
                .padding(.vertical, 14)

            if let quietestDay, let busiestDay {
                HStack(spacing: 12) {
                    dayHighlight(
                        title: "Quietest",
                        day: quietestDay.label,
                        value: formatDuration(quietestDay.minutes),
                        icon: "moon.stars.fill",
                        tint: MivoColors.blue
                    )
                    dayHighlight(
                        title: "Most tracked",
                        day: busiestDay.label,
                        value: formatDuration(busiestDay.minutes),
                        icon: "chart.bar.fill",
                        tint: MivoColors.accent
                    )
                }
            }

            reportNote("A low day is information, not a score. Look for what made that day feel different.")
        }
    }

    private var reflectionPage: some View {
        reportPage {
            reportEyebrow("INTENTION & TRUTH")

            Text(outcomeCount > 0 ? "\(worthwhileRate)% of rated sessions felt worth it" : "How did the scrolling feel?")
                .reportTitle(tint: outcomeCount > 0 ? MivoColors.blue : MivoColors.screenTimeInk)

            Text(outcomeCount > 0
                 ? "Your reflection adds meaning that raw minutes cannot show."
                 : "Rate a completed session to see whether your time felt useful.")
                .reportSupportingText()

            VStack(spacing: 0) {
                reportMetricRow(
                    icon: "checkmark.bubble.fill",
                    title: "Reflections completed",
                    value: "\(reflectedCount)/\(sessionCount)",
                    tint: MivoColors.blue
                )
                reportMetricRow(
                    icon: "scope",
                    title: "Truth-check accuracy",
                    value: truthSummary.checkCount > 0 ? "\(truthSummary.averageAccuracyScore)%" : "--",
                    tint: MivoColors.accent
                )
                reportMetricRow(
                    icon: "clock.arrow.circlepath",
                    title: "Sessions extended",
                    value: "\(extendedCount)",
                    tint: extendedCount > 0 ? MivoColors.timerOrange : MivoColors.textMuted
                )
                reportMetricRow(
                    icon: "eye.slash.fill",
                    title: "Forgotten time found",
                    value: truthSummary.checkCount > 0 ? formatDuration(truthSummary.totalForgottenMinutes) : "--",
                    tint: MivoColors.secondary
                )
            }
            .background(MivoColors.surfaceRaised.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.5)))
            .padding(.vertical, 12)

            if let topUrgeReason {
                reportNote("Your most recorded trigger was \(topUrgeReason.rawValue.lowercased()). Mivo will use that when suggesting your next experiment.")
            } else {
                reportNote("Choose a trigger when starting sessions to make next week’s pattern more specific.")
            }
        }
    }

    private var recapPage: some View {
        reportPage {
            reportEyebrow("WEEKLY RECAP")

            Text(dateRangeLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)

            Text("Here is what Mivo noticed")
                .reportTitle()

            VStack(spacing: 0) {
                recapRow(value: formatDuration(averageDailyMinutes), label: "Average tracked per day", badge: comparisonBadge)
                recapRow(value: "\(sessionCount)", label: "Saved sessions", badge: "\(reflectedCount) reflected")
                recapRow(
                    value: truthSummary.checkCount > 0 ? "\(truthSummary.averageAccuracyScore)%" : "--",
                    label: "Truth-check accuracy",
                    badge: truthSummary.checkCount > 0 ? "\(truthSummary.checkCount) checks" : "Keep checking"
                )
            }
            .padding(.horizontal, 18)
            .background(MivoColors.surfaceRaised.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.5)))
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 9) {
                Label("ONE THING FOR NEXT WEEK", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                Text(reportRecommendation)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(MivoColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: shareReportImage) {
                Label("Share this recap", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.blue.opacity(0.55)))
            }
            .buttonStyle(.plain)
        }
    }

    private var impactPage: some View {
        reportPage {
            reportEyebrow("YOUR MIVO EFFECT")

            Image(systemName: hasImpactEstimate ? "sparkles" : "hourglass")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(hasImpactEstimate ? MivoColors.blue : MivoColors.accent)
                .frame(width: 58, height: 58)
                .background((hasImpactEstimate ? MivoColors.blue : MivoColors.accent).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(impactHeadline)
                .reportSupportingText()

            Text(hasImpactEstimate ? formatDuration(totalReducedMinutes) : "Still measuring")
                .font(.system(size: hasImpactEstimate ? 54 : 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(hasImpactEstimate ? MivoColors.blue : MivoColors.screenTimeInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text(impactSubtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            HStack(spacing: 12) {
                impactMetric(
                    title: "THIS WEEK",
                    value: hasImpactEstimate ? formatDuration(weeklyReducedMinutes) : "--",
                    icon: "calendar"
                )
                impactMetric(
                    title: "MEASURED",
                    value: "\(impactMeasuredDays) day\(impactMeasuredDays == 1 ? "" : "s")",
                    icon: "chart.line.uptrend.xyaxis"
                )
            }
            .padding(.vertical, 8)

            Button(action: shareReportImage) {
                Label("Share with a friend", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(MivoColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            reportNote(impactMethodNote)
        }
    }

    private func reportPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                content()
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func reportEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(MivoColors.accent)
            .tracking(0)
    }

    private func reportNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func comparisonBar(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Text(formatDuration(value))
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.screenTimeInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MivoColors.border.opacity(0.28))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * comparisonWidth(value))
                }
            }
            .frame(height: 14)
        }
    }

    private var dailyBars: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(dayStats) { point in
                        VStack(spacing: 7) {
                            Text(point.minutes > 0 ? formatCompactDuration(point.minutes) : "")
                                .font(.system(size: 8, weight: .bold).monospacedDigit())
                                .foregroundColor(MivoColors.textSecondary)
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(point.id == busiestDay?.id ? MivoColors.accent : MivoColors.blue.opacity(point.minutes > 0 ? 0.8 : 0.16))
                                .frame(height: barHeight(for: point.minutes, available: proxy.size.height - 42))

                            Text(point.label.prefix(1))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(MivoColors.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 224)

            Rectangle()
                .fill(MivoColors.border.opacity(0.45))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
    }

    private func dayHighlight(title: String, day: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(day)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.screenTimeInk)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.45)))
    }

    private func reportMetricRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
        }
        .padding(.horizontal, 15)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.25)).frame(height: 1)
        }
    }

    private func impactMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.5)))
    }

    private func recapRow(value: String, label: String, badge: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer()
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MivoColors.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .frame(minHeight: 68)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.25)).frame(height: 1)
        }
    }

    private var reportTaskID: String {
        "\(weekOffset)-\(appVM.sessions.count)-\(appVM.truthChecks.count)-\(appVM.dailyScreenTimeObservations.count)"
    }

    @MainActor
    private func prepareReport() async {
        isPreparingReport = true
        await Task.yield()
        guard !Task.isCancelled else { return }

        let now = Date()
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: now) ?? now
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else {
            reportData = .empty
            isPreparingReport = false
            return
        }

        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        let keys = dates.map(dateKey)
        let keySet = Set(keys)
        let previousKeys = Set(dates.compactMap {
            calendar.date(byAdding: .day, value: -7, to: $0)
        }.map(dateKey))

        var currentSessions: [Session] = []
        var priorSessions: [Session] = []
        currentSessions.reserveCapacity(min(appVM.sessions.count, 128))
        priorSessions.reserveCapacity(min(appVM.sessions.count, 128))
        for session in appVM.sessions {
            if keySet.contains(session.date) {
                currentSessions.append(session)
            } else if previousKeys.contains(session.date) {
                priorSessions.append(session)
            }
        }

        let sessionsByDay = Dictionary(grouping: currentSessions, by: \.date)
        let safeMinutes: (Session) -> Int = { min(1_440, max(0, $0.actualDuration)) }
        let stats = dates.map { date in
            let key = dateKey(date)
            let sessions = sessionsByDay[key] ?? []
            return WeeklyDayStat(
                date: date,
                dateKey: key,
                label: dayName(date),
                minutes: sessions.reduce(0) { $0 + safeMinutes($1) },
                sessionCount: sessions.count
            )
        }
        let elapsedStats: [WeeklyDayStat]
        if weekOffset < 0 {
            elapsedStats = stats
        } else {
            let today = calendar.startOfDay(for: now)
            elapsedStats = stats.filter { calendar.startOfDay(for: $0.date) <= today }
        }

        let total = stats.reduce(0) { $0 + $1.minutes }
        let previousTotal = priorSessions.reduce(0) { $0 + safeMinutes($1) }
        let outcomes = currentSessions.compactMap(\.outcomeScore)
        let topUrge = Dictionary(grouping: currentSessions.compactMap(\.urgeReason), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key

        let firstFormatter = DateFormatter()
        firstFormatter.dateFormat = "MMM d"
        let lastFormatter = DateFormatter()
        lastFormatter.dateFormat = "MMM d, yyyy"
        let rangeLabel: String
        if let first = dates.first, let last = dates.last {
            rangeLabel = "\(firstFormatter.string(from: first)) - \(lastFormatter.string(from: last))"
        } else {
            rangeLabel = ""
        }

        let plan = appVM.adaptiveScreenTimePlan()
        let baseline = max(
            1,
            appVM.onboardingProfile.scrollEstimateMinutes
                ?? plan.baselineMinutes
        )
        let impactBaseline = max(1, plan.baselineMinutes)
        let reportCutoffKey = keys.last ?? dateKey(now)
        let impactObservations = appVM.dailyScreenTimeObservations
            .filter { $0.minutes >= 0 && $0.date <= reportCutoffKey }
            .sorted { $0.date < $1.date }
        let impactEvaluationDays = Array(impactObservations.dropFirst(min(3, impactObservations.count)))
        let selectedImpactDays = impactEvaluationDays.filter { keySet.contains($0.date) }
        let boundedObservationMinutes: (DailyScreenTimeObservation) -> Int = {
            min(1_440, max(0, $0.minutes))
        }
        let weeklyImpactActual = selectedImpactDays.reduce(0) { $0 + boundedObservationMinutes($1) }
        let totalImpactActual = impactEvaluationDays.reduce(0) { $0 + boundedObservationMinutes($1) }
        let sessionsThroughReport = appVM.sessions.lazy.filter { $0.date <= reportCutoffKey }.count
        let impactReady = !plan.collecting
            && impactObservations.count >= 7
            && sessionsThroughReport >= 3
            && !impactEvaluationDays.isEmpty
        let weeklyReduction = max(0, impactBaseline * selectedImpactDays.count - weeklyImpactActual)
        let totalReduction = max(0, impactBaseline * impactEvaluationDays.count - totalImpactActual)
        let prepared = WeeklyReportPreparedData(
            selectedWeekDates: dates,
            selectedWeekKeys: keys,
            weekSessions: currentSessions,
            previousWeekSessions: priorSessions,
            dayStats: stats,
            elapsedDayStats: elapsedStats,
            truthSummary: appVM.weeklyTruthSummary(for: keys),
            totalMinutes: total,
            averageDailyMinutes: total / max(1, elapsedStats.count),
            previousAverageMinutes: previousTotal / 7,
            baselineMinutes: baseline,
            reflectedCount: currentSessions.lazy.filter { $0.reflection != nil }.count,
            extendedCount: currentSessions.lazy.filter(\.extendedOnce).count,
            outcomeCount: outcomes.count,
            worthwhileCount: outcomes.lazy.filter { $0 == .worthIt }.count,
            topUrgeReason: topUrge,
            maximumDayMinutes: max(1, stats.lazy.map(\.minutes).max() ?? 1),
            dateRangeLabel: rangeLabel,
            impactBaselineMinutes: impactBaseline,
            impactMeasuredDays: impactObservations.count,
            impactSessionCount: sessionsThroughReport,
            weeklyReducedMinutes: weeklyReduction,
            totalReducedMinutes: totalReduction,
            hasImpactEstimate: impactReady
        )

        guard !Task.isCancelled else { return }
        reportData = prepared
        isPreparingReport = false
    }

    private var selectedWeekDates: [Date] { reportData.selectedWeekDates }
    private var selectedWeekKeys: [String] { reportData.selectedWeekKeys }
    private var weekSessions: [Session] { reportData.weekSessions }
    private var previousWeekSessions: [Session] { reportData.previousWeekSessions }
    private var dayStats: [WeeklyDayStat] { reportData.dayStats }
    private var elapsedDayStats: [WeeklyDayStat] { reportData.elapsedDayStats }
    private var totalMinutes: Int { reportData.totalMinutes }
    private var sessionCount: Int { weekSessions.count }
    private var averageDailyMinutes: Int { reportData.averageDailyMinutes }
    private var previousAverageMinutes: Int { reportData.previousAverageMinutes }
    private var hasData: Bool { !weekSessions.isEmpty }
    private var baselineMinutes: Int { reportData.baselineMinutes }

    private var baselineProgress: CGFloat {
        guard hasData else { return 0 }
        return min(1, CGFloat(averageDailyMinutes) / CGFloat(baselineMinutes))
    }

    private var comparisonUsesPreviousWeek: Bool { !previousWeekSessions.isEmpty }
    private var comparisonReferenceMinutes: Int { comparisonUsesPreviousWeek ? previousAverageMinutes : baselineMinutes }
    private var comparisonReferenceTitle: String { comparisonUsesPreviousWeek ? "Previous week" : "Onboarding estimate" }

    private var comparisonPercent: Int {
        guard hasData, comparisonReferenceMinutes > 0 else { return 0 }
        return Int(((Double(averageDailyMinutes - comparisonReferenceMinutes) / Double(comparisonReferenceMinutes)) * 100).rounded())
    }

    private var comparisonHeadline: String {
        guard hasData else { return "No comparison yet" }
        if comparisonPercent < 0 { return "\(abs(comparisonPercent))% less tracked time" }
        if comparisonPercent > 0 { return "\(comparisonPercent)% more tracked time" }
        return "Tracked time held steady"
    }

    private var comparisonSubtitle: String {
        comparisonUsesPreviousWeek ? "compared with the previous week" : "compared with what you reported during setup"
    }

    private var comparisonTint: Color {
        guard hasData else { return MivoColors.textMuted }
        return comparisonPercent <= 0 ? MivoColors.blue : MivoColors.accent
    }

    private var comparisonNote: String {
        let difference = abs(averageDailyMinutes - comparisonReferenceMinutes)
        if comparisonPercent < 0 {
            return "That is about \(formatDuration(difference)) less tracked scrolling per day. Look for the choice that made the difference."
        }
        if comparisonPercent > 0 {
            return "That is about \(formatDuration(difference)) more per day. This is a signal to inspect, not a failure."
        }
        return "Your average stayed within a few minutes of the comparison period."
    }

    private var comparisonBadge: String {
        guard hasData else { return "Still learning" }
        if comparisonPercent < 0 { return "↓ \(abs(comparisonPercent))%" }
        if comparisonPercent > 0 { return "↑ \(comparisonPercent)%" }
        return "Steady"
    }

    private var quietestDay: WeeklyDayStat? { elapsedDayStats.min { $0.minutes < $1.minutes } }
    private var busiestDay: WeeklyDayStat? { elapsedDayStats.max { $0.minutes < $1.minutes } }
    private var maximumDayMinutes: Int { reportData.maximumDayMinutes }

    private var reflectedCount: Int { reportData.reflectedCount }
    private var extendedCount: Int { reportData.extendedCount }
    private var outcomeCount: Int { reportData.outcomeCount }
    private var worthwhileCount: Int { reportData.worthwhileCount }
    private var worthwhileRate: Int { outcomeCount == 0 ? 0 : Int((Double(worthwhileCount) / Double(outcomeCount) * 100).rounded()) }

    private var truthSummary: WeeklyTruthSummary { reportData.truthSummary }

    private var topUrgeReason: UrgeReason? { reportData.topUrgeReason }

    private var impactBaselineMinutes: Int { reportData.impactBaselineMinutes }
    private var impactMeasuredDays: Int { reportData.impactMeasuredDays }
    private var impactSessionCount: Int { reportData.impactSessionCount }
    private var weeklyReducedMinutes: Int { reportData.weeklyReducedMinutes }
    private var totalReducedMinutes: Int { reportData.totalReducedMinutes }
    private var hasImpactEstimate: Bool { reportData.hasImpactEstimate }

    private var impactHeadline: String {
        if hasImpactEstimate, totalReducedMinutes > 0 {
            return "Mivo helped you reduce an estimated"
        }
        if hasImpactEstimate {
            return "Mivo is helping you see the change"
        }
        return "Mivo is building your impact estimate"
    }

    private var impactSubtitle: String {
        if hasImpactEstimate, totalReducedMinutes > 0 {
            let evaluatedDays = max(1, impactMeasuredDays - 3)
            return "of total screen time across \(evaluatedDays) measured day\(evaluatedDays == 1 ? "" : "s") after your baseline"
        }
        if hasImpactEstimate {
            return "No clear reduction yet. That is useful information for shaping next week."
        }
        let days = min(7, impactMeasuredDays)
        let sessions = min(3, impactSessionCount)
        return "Keep Apple Screen Time connected. Mivo has \(days)/7 measured days and \(sessions)/3 saved sessions."
    }

    private var impactMethodNote: String {
        if hasImpactEstimate {
            return "Estimated from Apple’s daily Screen Time totals compared with your \(formatDuration(impactBaselineMinutes)) blended baseline. Higher-use days offset lower-use days; this does not guarantee Mivo caused every minute of change."
        }
        return "Mivo waits for seven Apple Screen Time days and three saved sessions before showing a reduction estimate."
    }

    private var reportRecommendation: String {
        if let topUrgeReason {
            return "Before the first \(topUrgeReason.rawValue.lowercased())-driven session, pause and name what you want from it."
        }
        if extendedCount > 0 {
            return "Try finishing one planned session without extending it and notice what changes."
        }
        if truthSummary.checkCount == 0 {
            return "Complete one truth check before reviewing Screen Time next week."
        }
        return "Keep one scroll window exactly as planned and notice what helps it stay intentional."
    }

    private var dateRangeLabel: String { reportData.dateRangeLabel }

    @MainActor
    private func shareReportImage() {
        HapticsService.impact(style: .medium)
        let card = WeeklyReportShareCard(
            dateRange: dateRangeLabel,
            heroValue: hasImpactEstimate && totalReducedMinutes > 0
                ? formatDuration(totalReducedMinutes)
                : formatDuration(averageDailyMinutes),
            heroLabel: hasImpactEstimate && totalReducedMinutes > 0
                ? "estimated screen time reduced"
                : "average tracked scrolling per day",
            sessionCount: sessionCount,
            reflectedCount: reflectedCount,
            truthAccuracy: truthSummary.checkCount > 0 ? truthSummary.averageAccuracyScore : nil,
            dailyStats: dayStats,
            recommendation: reportRecommendation
        )
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        guard let image = renderer.uiImage else {
            HapticsService.error()
            return
        }
        sharePayload = WeeklyReportSharePayload(image: image)
    }

    private func comparisonWidth(_ value: Int) -> CGFloat {
        let maximum = max(1, max(averageDailyMinutes, comparisonReferenceMinutes))
        return max(value > 0 ? 0.06 : 0, CGFloat(value) / CGFloat(maximum))
    }

    private func barHeight(for minutes: Int, available: CGFloat) -> CGFloat {
        guard minutes > 0 else { return 8 }
        return max(16, available * CGFloat(minutes) / CGFloat(maximumDayMinutes))
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = MivoDay.formatter
        return formatter.string(from: date)
    }

    private func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func formatCompactDuration(_ minutes: Int) -> String {
        if minutes >= 60 { return "\(minutes / 60)h\(minutes % 60)m" }
        return "\(minutes)m"
    }
}

private struct WeeklyReportSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct WeeklyReportActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct WeeklyReportShareCard: View {
    let dateRange: String
    let heroValue: String
    let heroLabel: String
    let sessionCount: Int
    let reflectedCount: Int
    let truthAccuracy: Int?
    let dailyStats: [WeeklyDayStat]
    let recommendation: String

    var body: some View {
        ZStack {
            MivoColors.background

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    MivoLogo(size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mivo weekly recap")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.screenTimeInk)
                        Text(dateRange)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(width: 36, height: 36)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Rectangle()
                    .fill(MivoColors.border.opacity(0.45))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(heroValue)
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(MivoColors.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(heroLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }

                HStack(spacing: 8) {
                    shareMetric(value: "\(sessionCount)", label: "SESSIONS")
                    shareMetric(value: "\(reflectedCount)", label: "REFLECTED")
                    shareMetric(value: truthAccuracy.map { "\($0)%" } ?? "--", label: "TRUTH SCORE")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR WEEK")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    GeometryReader { proxy in
                        let peak = max(1, dailyStats.map(\.minutes).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 7) {
                            ForEach(dailyStats) { day in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(day.minutes > 0 ? MivoColors.accent : MivoColors.border.opacity(0.35))
                                        .frame(height: max(5, 45 * CGFloat(day.minutes) / CGFloat(peak)))
                                    Text(day.label.prefix(1))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    }
                    .frame(height: 64)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("NEXT WEEK", systemImage: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    Text(recommendation)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .minimumScaleFactor(0.84)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.surfaceRaised.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Text("See the pattern. Break the loop.")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                    Spacer()
                    Text("usemivo.app")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
            }
            .padding(20)
        }
        .frame(width: 360, height: 450)
    }

    private func shareMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(MivoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.42)))
    }
}

private extension View {
    func reportTitle(tint: Color = MivoColors.screenTimeInk) -> some View {
        font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }

    func reportSupportingText() -> some View {
        font(.system(size: 15, weight: .medium))
            .foregroundColor(MivoColors.textSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
    }
}
