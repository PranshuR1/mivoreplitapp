import SwiftUI

/// "Mivo Recall" — the Attention Receipt.
///
/// Built instead of a real scroll counter, which iOS has no API for (no app
/// can read gesture/content events inside another app's process — see the
/// reasoning on `AppViewModel.recordRecallCheckIn` and the recall step added
/// to `MidScrollCheckInView`). Rather than a number Mivo can't actually get,
/// this pairs two things it *can* get honestly:
///   - real per-app time today, straight from the same Screen Time report
///     `TruthCheckGuess` already uses (`AppViewModel.todayPerAppMinutes()`)
///   - what the person themselves guessed they saw, logged at the moment it
///     was still fresh (`AppViewModel.recallCheckIns`)
/// The gap between those two — "you guessed ~5 things, you could name one" —
/// is the whole point, not a compromise for the missing scroll count.
struct AttentionReceiptView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var range: ReceiptRange = .today

    private enum ReceiptRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Range", selection: $range) {
                        ForEach(ReceiptRange.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, MivoMetrics.screenPadding)
                    .padding(.top, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            ReceiptPaperCard(data: data)
                                .padding(.top, 18)

                            AttentionCompletionCard(start: commitmentRangeStart, end: commitmentRangeEnd)
                                .padding(.horizontal, MivoMetrics.screenPadding)

                            Text("Real time, straight from Screen Time. Recall, straight from you.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MivoColors.inkMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(MivoColors.deep)
                }
            }
        }
    }

    private var data: ReceiptData {
        switch range {
        case .today:
            return ReceiptData.today(appVM: appVM)
        case .week:
            return ReceiptData.thisWeek(appVM: appVM)
        }
    }

    private var commitmentRangeEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var commitmentRangeStart: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return range == .today ? today : (Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today)
    }
}

// MARK: - Data assembly

@MainActor
private struct ReceiptData {
    let dateLabel: String
    let receiptNumber: String
    let perApp: [(name: String, minutes: Int)]
    let totalMinutes: Int
    let checkInCount: Int
    let averageGuess: Double?
    let namedCount: Int
    let blankCount: Int
    /// Everything measured inside `AppWrapperView` sessions — see
    /// `WrapperMetrics`. Nil `scrollCount` (inside it) means the wrapper was
    /// never used in this range, so the card can tell "no measured data"
    /// apart from "measured zero."
    let wrapper: WrapperMetrics
    /// "What was N reels ago?" prompts fired inside wrapper sessions — a
    /// second, more pointed recall signal than `RecallCheckIn`, since the
    /// question itself references a real scroll count rather than "however
    /// many things you think you saw."
    let inWrapperPromptCount: Int
    let inWrapperAnsweredCount: Int

    static func today(appVM: AppViewModel) -> ReceiptData {
        let key = MivoDay.todayKey
        let perApp = appVM.todayPerAppMinutes()
        let checkIns = appVM.recallCheckIns(for: key)
        let wrapperPrompts = appVM.instagramRecallPrompts(for: key)
        return ReceiptData(
            dateLabel: Self.formattedDay(key),
            receiptNumber: Self.receiptNumber(for: key),
            perApp: perApp,
            totalMinutes: perApp.reduce(0) { $0 + $1.minutes },
            checkInCount: checkIns.count,
            averageGuess: Self.averageGuess(checkIns),
            namedCount: checkIns.filter { $0.recalledSomething }.count,
            blankCount: checkIns.filter { !$0.recalledSomething }.count,
            wrapper: WrapperMetrics(sessions: appVM.instagramWrapperSessions(for: key)),
            inWrapperPromptCount: wrapperPrompts.count,
            inWrapperAnsweredCount: wrapperPrompts.filter { $0.recalledSomething }.count
        )
    }

    static func thisWeek(appVM: AppViewModel) -> ReceiptData {
        let keys = (0..<7).map { MivoDay.key(offsetFromToday: -$0) }
        let checkIns = keys.flatMap { appVM.recallCheckIns(for: $0) }
        let wrapperPrompts = keys.flatMap { appVM.instagramRecallPrompts(for: $0) }

        // Per-app history isn't captured every day the way today's live
        // Screen Time report is — only days with a truth check carry a
        // `perAppMinutes` snapshot. Merge whatever real snapshots exist
        // rather than inventing a number for days without one.
        var mergedApp: [String: Int] = [:]
        for check in appVM.truthChecks where keys.contains(check.date) {
            for (app, minutes) in check.perAppMinutes ?? [:] {
                mergedApp[app, default: 0] += minutes
            }
        }
        let totalFromObservations = appVM.dailyScreenTimeObservations
            .filter { keys.contains($0.date) }
            .reduce(0) { $0 + $1.minutes }

        return ReceiptData(
            dateLabel: "Last 7 days",
            receiptNumber: Self.receiptNumber(for: MivoDay.todayKey),
            perApp: mergedApp.map { (name: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes },
            totalMinutes: max(totalFromObservations, mergedApp.values.reduce(0, +)),
            checkInCount: checkIns.count,
            averageGuess: Self.averageGuess(checkIns),
            namedCount: checkIns.filter { $0.recalledSomething }.count,
            blankCount: checkIns.filter { !$0.recalledSomething }.count,
            wrapper: WrapperMetrics(sessions: keys.flatMap { appVM.instagramWrapperSessions(for: $0) }),
            inWrapperPromptCount: wrapperPrompts.count,
            inWrapperAnsweredCount: wrapperPrompts.filter { $0.recalledSomething }.count
        )
    }

    private static func averageGuess(_ checkIns: [RecallCheckIn]) -> Double? {
        guard !checkIns.isEmpty else { return nil }
        return Double(checkIns.reduce(0) { $0 + $1.guessedCount }) / Double(checkIns.count)
    }

    private static func formattedDay(_ key: String) -> String {
        guard let date = MivoDay.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = MivoDay.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d yyyy"
        return formatter.string(from: date).uppercased()
    }

    private static func receiptNumber(for key: String) -> String {
        let digits = key.filter(\.isNumber)
        let suffix = digits.suffix(4)
        return "NO. \(suffix)"
    }
}

/// Every real, measured number `AppWrapperView` produces, aggregated
/// across whatever sessions fall in a range. Counts sum; `longestPauseSeconds`
/// takes the max (a sum of "longest pauses" across sessions wouldn't mean
/// anything); `averageFirstScrollDelaySeconds` averages, since it's about
/// typical hesitation, not a running total.
private struct WrapperMetrics {
    let scrollCount: Int?
    let sessionCount: Int
    let videoPlayCount: Int
    let videoWatchSeconds: Int
    let tapCount: Int
    let scrollDistancePoints: Int
    let sectionChanges: Int
    let longestPauseSeconds: Int
    let averageFirstScrollDelaySeconds: Int?

    init(sessions: [InstagramWrapperSession]) {
        scrollCount = sessions.isEmpty ? nil : sessions.reduce(0) { $0 + $1.scrollCount }
        sessionCount = sessions.count
        videoPlayCount = sessions.reduce(0) { $0 + $1.videoPlayCount }
        videoWatchSeconds = sessions.reduce(0) { $0 + $1.videoWatchSeconds }
        tapCount = sessions.reduce(0) { $0 + $1.tapCount }
        scrollDistancePoints = sessions.reduce(0) { $0 + $1.scrollDistancePoints }
        sectionChanges = sessions.reduce(0) { $0 + $1.sectionChanges }
        longestPauseSeconds = sessions.map(\.longestPauseSeconds).max() ?? 0
        averageFirstScrollDelaySeconds = sessions.isEmpty ? nil :
            sessions.reduce(0) { $0 + $1.firstScrollDelaySeconds } / sessions.count
    }
}

// MARK: - Paper card

private struct ReceiptPaperCard: View {
    let data: ReceiptData

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("MIVO")
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundColor(MivoColors.ink)
                Text("ATTENTION RECEIPT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(MivoColors.inkMuted)
                Text("\(data.dateLabel)  ·  \(data.receiptNumber)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 4)
            }
            .padding(.top, 22)

            dashedRule.padding(.vertical, 16)

            if data.perApp.isEmpty {
                Text("No tracked time yet — Screen Time reporting fills in through the day.")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(MivoColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    sectionLabel("Time Spent")
                    ForEach(data.perApp, id: \.name) { row in
                        DotLeaderRow(label: row.name, value: minutesLabel(row.minutes))
                            .padding(.bottom, 10)
                    }
                }
            }

            if data.wrapper.scrollCount != nil {
                dashedRule.padding(.vertical, 16)
                measuredBlock
            }

            dashedRule.padding(.vertical, 16)

            recallBlock

            dashedRule.padding(.vertical, 16)

            HStack(alignment: .lastTextBaseline) {
                Text("TOTAL TRACKED")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(MivoColors.ink)
                Spacer()
                Text(minutesLabel(data.totalMinutes))
                    .font(.system(size: 21, weight: .bold, design: .monospaced))
                    .foregroundColor(MivoColors.ink)
            }

            barcode.padding(.top, 20)

            Text("SEE YOU TOMORROW")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(MivoColors.inkMuted)
                .padding(.top, 10)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, 22)
        .background(MivoColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MivoColors.hairlineSoft, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    /// Every real, measured number from `AppWrapperView` sessions —
    /// shown apart from `recallBlock` (always a self-report) and styled in
    /// ink rather than terracotta so the two never read as the same kind of
    /// number. Leads with reels watched (real `<video>` play events) since
    /// that's the most precise, most literal answer this whole feature was
    /// built to give.
    private var measuredBlock: some View {
        let w = data.wrapper
        let sessionWord = w.sessionCount == 1 ? "session" : "sessions"
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Measured — \(w.sessionCount) \(sessionWord)", color: MivoColors.ink)

            VStack(spacing: 8) {
                DotLeaderRow(label: "Reels watched", value: "\(w.videoPlayCount)")
                DotLeaderRow(label: "Video watch time", value: durationLabel(w.videoWatchSeconds))
                DotLeaderRow(label: "Scroll bursts", value: "\(w.scrollCount ?? 0)")
                DotLeaderRow(label: "Scroll distance", value: "\(w.scrollDistancePoints) pt")
                DotLeaderRow(label: "Taps", value: "\(w.tapCount)")
                DotLeaderRow(label: "Sections visited", value: "\(w.sectionChanges)")
                DotLeaderRow(label: "Longest pause", value: durationLabel(w.longestPauseSeconds))
                if let delay = w.averageFirstScrollDelaySeconds {
                    DotLeaderRow(label: "First scroll after", value: durationLabel(delay))
                }
            }

            if data.inWrapperPromptCount > 0 {
                (Text("Asked mid-scroll ").fontWeight(.bold) + Text("\(data.inWrapperPromptCount)×") + Text(" — answered \(data.inWrapperAnsweredCount)."))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.ink.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func durationLabel(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    @ViewBuilder
    private var recallBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Recall", color: MivoColors.deep)

            if data.checkInCount == 0 {
                Text("No check-ins yet. Mivo will ask what you saw the next time a session pauses you.")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(MivoColors.inkBody)
            } else {
                if let average = data.averageGuess {
                    (Text("You guessed ") + Text("~\(Self.roundedString(average)) things").fontWeight(.bold) + Text(" per check-in."))
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundColor(MivoColors.inkBody)
                }
                (Text("You could name ") + Text("\(data.namedCount)").fontWeight(.bold) + Text(blankSuffix))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(MivoColors.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.deep.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var blankSuffix: String {
        guard data.blankCount > 0 else { return " — every time." }
        return data.blankCount == 1 ? " — and blanked once." : " — and blanked \(data.blankCount) times."
    }

    private static func roundedString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func sectionLabel(_ text: String, color: Color = MivoColors.inkMuted) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
    }

    private var dashedRule: some View {
        Rectangle()
            .fill(MivoColors.hairline)
            .frame(height: 1)
            .overlay(
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(MivoColors.muted, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
            )
    }

    private var barcode: some View {
        HStack(spacing: 2) {
            ForEach(0..<38, id: \.self) { i in
                Rectangle()
                    .fill(MivoColors.ink.opacity(0.85))
                    .frame(width: i % 3 == 0 ? 2.4 : 1.2, height: 26)
            }
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

/// Classic receipt dot-leader row: label, a line of dots, right-aligned value.
private struct DotLeaderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                .foregroundColor(MivoColors.ink)
                .lineLimit(1)

            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .stroke(MivoColors.muted, style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
            }
            .frame(height: 8)

            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundColor(MivoColors.ink)
                .lineLimit(1)
        }
    }
}
