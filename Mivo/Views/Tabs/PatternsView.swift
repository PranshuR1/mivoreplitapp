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
                VStack(spacing: 0) {
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
                            let dayTotal = daySessions.reduce(0) { $0 + $1.actualDuration }
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

            if selectedSessions.isEmpty {
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
                        Text("Sessions")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                        Spacer()
                        Text("\(selectedSessions.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                    }
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
            return total + (dayMap[k] ?? []).reduce(0) { $0 + $1.actualDuration }
        }
    }

    var avgPerDay: Int { daysInMonth > 0 ? monthTotal / daysInMonth : 0 }

    var selectedKey: String { dateKey(year: viewYear, month: viewMonth, day: selectedDay) }
    var selectedSessions: [Session] { dayMap[selectedKey] ?? [] }
    var selectedTotal: Int { selectedSessions.reduce(0) { $0 + $1.actualDuration } }

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
