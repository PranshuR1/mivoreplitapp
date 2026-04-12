import SwiftUI

struct FocusView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedMode: FocusMode = .classic
    @State private var taskDesc = ""
    @State private var intendedDuration = "25"
    @State private var focusLevel = 3
    @State private var timeAvailable = "60"

    // Classic
    @State private var workMinutes = 25
    @State private var restMinutes = 5
    @State private var cyclesEnabled = false
    @State private var cycleCount = 1

    // Adaptive
    @State private var adaptiveStartMin = 10
    @State private var adaptiveMaxCap = 45

    // Micro
    @State private var microDuration = 7

    // Academic
    @State private var academicSprintCount = 4
    @State private var academicLongBreak = false

    // AI
    @State private var aiLoading = false
    @State private var aiPlan: FocusRecommendation? = nil
    @State private var aiError: String? = nil
    @State private var showAIPlan = false
    @State private var showTimerFullScreen = false

    var effectiveWorkMinutes: Int {
        switch selectedMode {
        case .classic: return workMinutes
        case .adaptive: return adaptiveStartMin
        case .open: return 120
        case .micro: return microDuration
        case .academic: return 25
        }
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18))
                                .foregroundColor(MivoColors.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        Text("Enter Focus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.bottom, 8)

                    // Mode selector
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mode")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)

                        ForEach(FocusMode.allCases, id: \.rawValue) { mode in
                            Button {
                                selectedMode = mode
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if selectedMode == mode {
                                            Circle().fill(MivoColors.accent).frame(width: 20, height: 20)
                                            Circle().fill(MivoColors.white).frame(width: 8, height: 8)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(selectedMode == mode ? MivoColors.accent : MivoColors.textPrimary)
                                        Text(mode.description)
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.textSecondary)
                                            .lineSpacing(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(selectedMode == mode ? MivoColors.accentMuted : MivoColors.background)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // Mode options
                    modeOptionsCard

                    // Task description
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What are you working on?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        TextField("Optional task description...", text: $taskDesc)
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(MivoColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // AI Coach card
                    aiCoachCard

                    // Enter Focus button as direct NavigationLink
                    NavigationLink {
                        FocusTimerView(
                            mode: selectedMode,
                            workMinutes: effectiveWorkMinutes,
                            restMinutes: restMinutes
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Text("Enter Focus")
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(MivoColors.white)
                        .tracking(0.3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(MivoColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: MivoColors.accent.opacity(0.3), radius: 12, y: 4)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showAIPlan) {
            if let plan = aiPlan {
                AIPlanSheet(plan: plan) {
                    applyPlan(plan)
                    showAIPlan = false
                } onStartWith: {
                    applyPlan(plan)
                    showAIPlan = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showTimerFullScreen = true
                    }
                } onDismiss: {
                    showAIPlan = false
                }
            }
        }
        .fullScreenCover(isPresented: $showTimerFullScreen) {
            FocusTimerView(
                mode: selectedMode,
                workMinutes: effectiveWorkMinutes,
                restMinutes: restMinutes
            )
        }
    }

    @ViewBuilder
    var modeOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch selectedMode {
            case .classic:
                Text("Timing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                HStack(spacing: 8) {
                    ForEach([(25, 5), (50, 10), (60, 5)], id: \.0) { w, r in
                        Button {
                            workMinutes = w; restMinutes = r
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(w)/\(r)")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(w)m work")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(workMinutes == w ? .white : MivoColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(workMinutes == w ? MivoColors.accent : MivoColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("Cycles")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $cyclesEnabled)
                        .tint(MivoColors.accent)
                        .labelsHidden()
                }
                if cyclesEnabled {
                    HStack(spacing: 8) {
                        ForEach([1, 2, 3, 4], id: \.self) { n in
                            Button { cycleCount = n } label: {
                                Text("\(n)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(cycleCount == n ? .white : MivoColors.textSecondary)
                                    .frame(width: 40, height: 36)
                                    .background(cycleCount == n ? MivoColors.accent : MivoColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            case .adaptive:
                Text("Starting duration")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                HStack(spacing: 8) {
                    ForEach([5, 10, 15], id: \.self) { n in
                        Button { adaptiveStartMin = n } label: {
                            Text("\(n) min")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(adaptiveStartMin == n ? .white : MivoColors.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(adaptiveStartMin == n ? MivoColors.accent : MivoColors.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Max cap")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                HStack(spacing: 8) {
                    ForEach([30, 45, 60, 90], id: \.self) { n in
                        Button { adaptiveMaxCap = n } label: {
                            Text("\(n)m")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(adaptiveMaxCap == n ? .white : MivoColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(adaptiveMaxCap == n ? MivoColors.accent : MivoColors.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .micro:
                Text("Duration")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                HStack(spacing: 8) {
                    ForEach([5, 7, 10], id: \.self) { n in
                        Button { microDuration = n } label: {
                            Text("\(n) min")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(microDuration == n ? .white : MivoColors.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(microDuration == n ? MivoColors.accent : MivoColors.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .academic:
                Text("Sprint system: 25 min work / 5 min break")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(4)
                HStack {
                    Text("Number of sprints")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach([2, 3, 4, 6], id: \.self) { n in
                            Button { academicSprintCount = n } label: {
                                Text("\(n)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(academicSprintCount == n ? .white : MivoColors.textSecondary)
                                    .frame(width: 36, height: 32)
                                    .background(academicSprintCount == n ? MivoColors.accent : MivoColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Text("Long break after 4 sprints")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $academicLongBreak)
                        .tint(MivoColors.accent)
                        .labelsHidden()
                }

            case .open:
                Text("No timer. Run until you choose to stop.")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(4)
            }
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)
    }

    @ViewBuilder
    var aiCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Focus Coach")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Get a personalised session recommendation")
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
            }

            // Focus level
            VStack(alignment: .leading, spacing: 6) {
                Text("Current focus level: \(focusLevel)/5")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button { focusLevel = n } label: {
                            Circle()
                                .fill(n <= focusLevel ? MivoColors.accent : MivoColors.border)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text("\(n)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(n <= focusLevel ? .white : MivoColors.textMuted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            if let error = aiError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
                    .lineSpacing(2)
            }

            Button {
                Task { await getRecommendation() }
            } label: {
                HStack(spacing: 8) {
                    if aiLoading {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(aiLoading ? "Thinking..." : "Recommend a session")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(aiLoading)
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)
    }

    func getRecommendation() async {
        aiLoading = true
        aiError = nil
        let summary = buildSessionSummary()
        let result = await AIService.recommendFocus(
            focusLevel: focusLevel,
            timeAvailable: Int(timeAvailable) ?? 60,
            intendedDuration: Int(intendedDuration) ?? 25,
            taskDesc: taskDesc.isEmpty ? nil : taskDesc,
            profile: appVM.onboardingProfile,
            recentSessionSummary: summary
        )
        switch result {
        case .success(let plan):
            aiPlan = plan
            showAIPlan = true
        case .failure:
            // Use offline fallback
            let plan = AIService.offlineRecommend(
                focusLevel: focusLevel,
                timeAvailable: Int(timeAvailable) ?? 60,
                intendedDuration: Int(intendedDuration) ?? 25
            )
            aiPlan = plan
            showAIPlan = true
            aiError = "Using offline recommendation (no network)."
        }
        aiLoading = false
    }

    func applyPlan(_ plan: FocusRecommendation) {
        selectedMode = plan.mode
        switch plan.mode {
        case .classic:
            workMinutes = plan.workMinutes
            restMinutes = plan.restMinutes
        case .micro:
            microDuration = max(5, min(10, plan.workMinutes))
        case .adaptive:
            adaptiveStartMin = max(5, min(15, plan.workMinutes))
        default: break
        }
    }

    func buildSessionSummary() -> String? {
        guard !appVM.sessions.isEmpty else { return nil }
        let recent = Array(appVM.sessions.suffix(10))
        let avg = recent.reduce(0) { $0 + $1.actualDuration } / recent.count
        let overruns = recent.filter { $0.actualDuration > $0.plannedDuration }.count
        return "Last \(recent.count) sessions: avg \(avg) min, \(overruns) went over planned time."
    }
}

// MARK: - AI Plan Sheet

struct AIPlanSheet: View {
    let plan: FocusRecommendation
    let onEdit: () -> Void
    let onStartWith: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(MivoColors.border)
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended session")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                        .tracking(0.4)
                        .textCase(.uppercase)
                    Text(plan.mode.displayName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                }

                HStack(spacing: 16) {
                    planStat(label: "Work", value: "\(plan.workMinutes)m")
                    planStat(label: "Rest", value: "\(plan.restMinutes)m")
                }

                Text(plan.rationale)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(6)

                Text(plan.dailySchedule)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textMuted)
                    .lineSpacing(4)
                    .italic()

                VStack(spacing: 10) {
                    Button(action: onStartWith) {
                        Text("Start with this plan")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button(action: onEdit) {
                        Text("Apply & adjust")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.accent)
                            .padding(.vertical, 12)
                    }
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textMuted)
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(MivoColors.background)
    }

    @ViewBuilder
    func planStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))
    }
}
