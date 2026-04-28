import SwiftUI

private let monthNames = ["January","February","March","April","May","June",
                           "July","August","September","October","November","December"]
private let weekdayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

struct PatternsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var viewYear: Int
    @State private var viewMonth: Int
    @State private var selectedDay: Int
    @State private var showFocus = false

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
                    calendarCard
                    insightSection
                        .padding(.bottom, 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
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
            appVM.loadDeviceActivityReport()
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

                Image(systemName: hasDeviceData ? "waveform.path.ecg" : "lock.open")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(hasDeviceData ? MivoColors.accent : MivoColors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(alignment: .center, spacing: 18) {
                usageRing

                VStack(alignment: .leading, spacing: 10) {
                    Text(formatDuration(screenTimeMinutesToday))
                        .font(.system(size: 38, weight: .bold).monospacedDigit())
                        .foregroundColor(MivoColors.textPrimary)
                        .contentTransition(.numericText())

                    Text("today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)

                    HStack(spacing: 8) {
                        statPill(title: "\(topDeviceApps.count)", subtitle: "tracked apps")
                        statPill(title: "\(baselineDeltaText)", subtitle: "vs baseline")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasDeviceData {
                appUsageBars
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

    private var usageRing: some View {
        let progress = min(Double(screenTimeMinutesToday) / Double(dailyBaseline), 1)

        return ZStack {
            Circle()
                .stroke(MivoColors.surface, lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [MivoColors.accent, MivoColors.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.86), value: progress)
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.textPrimary)
                Text("baseline")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .frame(width: 116, height: 116)
    }

    private func statPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.textPrimary)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MivoColors.heroText)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var appUsageBars: some View {
        VStack(spacing: 11) {
            ForEach(topDeviceApps, id: \.bundleID) { item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(appDisplayName(item.bundleID))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(formatDuration(Int((Double(item.seconds) / 60.0).rounded())))
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundColor(MivoColors.textSecondary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(MivoColors.surface)
                            Capsule()
                                .fill(MivoColors.accent)
                                .frame(width: max(8, proxy.size.width * appBarProgress(item.seconds)))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private var missingScreenTimeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for Screen Time data")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("After access is allowed, Mivo reads the shared Device Activity report and these charts update from real usage.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(MivoColors.heroText)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Calendar

    var calendarCard: some View {
        VStack(spacing: 0) {
            // Month nav
            HStack {
                Text("\(monthNames[viewMonth]) \(viewYear)")
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

            Text("Month: \(formatDuration(monthTotal))  •  Avg/day: \(formatDuration(avgPerDay))")
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
                            let dayTotal = totalForDay(key, sessions: daySessions)
                            let isToday = key == todayKey
                            let isSelected = day == selectedDay

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
                                        .fill(dayTotal > 0 ? (isSelected ? MivoColors.accent : MivoColors.accentLight) : MivoColors.border)
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

            if selectedTotal == 0 {
                Text("No data recorded.")
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textMuted)
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Text("Total")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                        Spacer()
                        Text(formatDuration(selectedTotal))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                    .padding(14)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Text(selectedKey == todayKey && hasDeviceData ? "Source" : "Sessions")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                        Spacer()
                        Text(selectedKey == todayKey && hasDeviceData ? "Screen Time" : "\(selectedSessions.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                    .padding(14)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if selectedKey == todayKey && hasDeviceData {
                        ForEach(topDeviceApps, id: \.bundleID) { item in
                            HStack {
                                Text(appDisplayName(item.bundleID))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDuration(Int((Double(item.seconds) / 60.0).rounded())))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(MivoColors.textPrimary)
                            }
                            .padding(14)
                            .background(MivoColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        ForEach(selectedSessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sessionTime(session))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.textPrimary)
                                Text(session.intention.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textSecondary)
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

    var monthTotal: Int {
        (1...daysInMonth).reduce(0) { total, day in
            let k = dateKey(year: viewYear, month: viewMonth, day: day)
            return total + totalForDay(k, sessions: dayMap[k] ?? [])
        }
    }

    var avgPerDay: Int { daysInMonth > 0 ? monthTotal / daysInMonth : 0 }

    var selectedKey: String { dateKey(year: viewYear, month: viewMonth, day: selectedDay) }
    var selectedSessions: [Session] { dayMap[selectedKey] ?? [] }
    var selectedTotal: Int { totalForDay(selectedKey, sessions: selectedSessions) }

    var hasDeviceData: Bool {
        (appVM.deviceActivityMinutesToday ?? 0) > 0 || !appVM.deviceActivityPerAppSeconds.isEmpty
    }

    var screenTimeMinutesToday: Int {
        appVM.deviceActivityMinutesToday ?? appVM.todaysTotalMinutes
    }

    var dailyBaseline: Int {
        max(appVM.onboardingProfile.scrollEstimateMinutes ?? 120, 30)
    }

    var baselineDeltaText: String {
        let delta = screenTimeMinutesToday - dailyBaseline
        if delta == 0 { return "Even" }
        return "\(delta > 0 ? "+" : "")\(delta)m"
    }

    var screenTimeCaption: String {
        guard hasDeviceData else { return "Connect Screen Time to turn this into live usage." }
        if let generatedAt = appVM.deviceActivityReportGeneratedAt {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            return "Updated \(fmt.string(from: generatedAt)) from Device Activity."
        }
        return "Updated from Device Activity."
    }

    var topDeviceApps: [(bundleID: String, seconds: Int)] {
        appVM.deviceActivityPerAppSeconds
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (bundleID: $0.key, seconds: $0.value) }
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

    func totalForDay(_ key: String, sessions: [Session]) -> Int {
        if key == todayKey, let deviceMinutes = appVM.deviceActivityMinutesToday {
            return deviceMinutes
        }
        return sessions.reduce(0) { $0 + $1.actualDuration }
    }

    func appBarProgress(_ seconds: Int) -> Double {
        guard let largest = topDeviceApps.first?.seconds, largest > 0 else { return 0 }
        return min(Double(seconds) / Double(largest), 1)
    }

    func appDisplayName(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init)
        guard let last = parts.last else { return bundleID }
        return last
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
