import SwiftUI

/// New onboarding step: Setting realistic, personal goals
struct OnboardingGoalsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedGoals: Set<PhoneGoal> = []
    @State private var customGoal: String = ""
    @State private var appear = false
    
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 4,
                            total: 6,
                            eyebrow: "Your vision",
                            title: "What would you like to reclaim?",
                            subtitle: "Choose what matters to you. Mivo isn't about going cold turkey—it's about making space for what you value."
                        )
                        .onboardingEntrance(appear)
                        
                        goalsSummary
                            .onboardingEntrance(appear, delay: 0.08)
                        
                        VStack(spacing: 12) {
                            ForEach(Array(PhoneGoal.allCases.enumerated()), id: \.element) { index, goal in
                                goalCard(goal)
                                    .onboardingEntrance(appear, delay: 0.12 + Double(index) * 0.05)
                            }
                        }
                        
                        customGoalCard
                            .onboardingEntrance(appear, delay: 0.5)
                        
                        visionCard
                            .onboardingEntrance(appear, delay: 0.6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                
                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingCommitmentView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Set my vision")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(hasSelection ? MivoColors.blue : MivoColors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: hasSelection ? MivoColors.blue.opacity(0.24) : .clear, radius: 16, y: 8)
                    }
                    .disabled(!hasSelection)
                    .simultaneousGesture(TapGesture().onEnded {
                        if hasSelection {
                            saveGoals()
                            HapticsService.success()
                        }
                    })
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
        .onAppear { appear = true }
    }
    
    private var hasSelection: Bool {
        !selectedGoals.isEmpty || !customGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var goalsSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedGoals.isEmpty ? "Choose your vision" : "\(selectedGoals.count) goal\(selectedGoals.count == 1 ? "" : "s") selected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text(summaryMessage)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: selectedGoals.isEmpty ? "target" : "checkmark.seal.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(selectedGoals.isEmpty ? MivoColors.muted : MivoColors.blue)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private func goalCard(_ goal: PhoneGoal) -> some View {
        let isSelected = selectedGoals.contains(goal)
        
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                if isSelected {
                    selectedGoals.remove(goal)
                } else {
                    selectedGoals.insert(goal)
                }
            }
            HapticsService.selection()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(goal.emoji)
                        .font(.system(size: 28))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(goal.timeImpact)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? MivoColors.blue : MivoColors.secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? MivoColors.blue : MivoColors.muted, lineWidth: 2)
                            .frame(width: 28, height: 28)
                        
                        if isSelected {
                            Circle()
                                .fill(MivoColors.blue)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Text(goal.description)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(isSelected ? MivoColors.blue.opacity(0.06) : MivoColors.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? MivoColors.blue.opacity(0.4) : MivoColors.white.opacity(0.58), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.025), radius: isSelected ? 10 : 4, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private var customGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(MivoColors.accent)
                
                Text("Or write your own")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }
            
            ZStack(alignment: .topLeading) {
                if customGoal.isEmpty {
                    Text("E.g., 'Read before bed' or 'Be present with my kids'")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                }
                
                TextEditor(text: $customGoal)
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 80)
            }
            .background(MivoColors.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(MivoColors.surface.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MivoColors.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var visionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(MivoColors.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Your vision guides your progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Mivo will remind you of these when the urge to scroll feels strongest.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(MivoColors.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MivoColors.blue.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var summaryMessage: String {
        if selectedGoals.isEmpty {
            return "What matters most to you?"
        } else if selectedGoals.count == 1 {
            return "A focused goal. Add more if you'd like."
        } else {
            return "You're building a meaningful vision."
        }
    }
    
    private func saveGoals() {
        var goalDescriptions: [String] = selectedGoals.map { $0.rawValue }
        
        let trimmed = customGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            goalDescriptions.append("custom: \(trimmed)")
        }
        
        let summary = "Phone goals: \(goalDescriptions.joined(separator: ", "))"
        appVM.appendAISummary(summary)
    }
}

// MARK: - Phone Goal Enum

enum PhoneGoal: String, CaseIterable, Hashable, Codable {
    case morningRoutine = "morning_routine"
    case deepWork = "deep_work"
    case quality_time = "quality_time"
    case reading = "reading"
    case sleep = "sleep"
    case presence = "presence"
    case creativity = "creativity"
    
    var title: String {
        switch self {
        case .morningRoutine: return "Calm mornings"
        case .deepWork: return "Deep work"
        case .quality_time: return "Quality time"
        case .reading: return "More reading"
        case .sleep: return "Better sleep"
        case .presence: return "Be present"
        case .creativity: return "Create more"
        }
    }
    
    var description: String {
        switch self {
        case .morningRoutine: return "Start my day with intention instead of scrolling"
        case .deepWork: return "Focus on meaningful work without constant interruptions"
        case .quality_time: return "Be fully present with the people I care about"
        case .reading: return "Reclaim time for books, articles, and longer-form content"
        case .sleep: return "Put the phone down and actually rest"
        case .presence: return "Notice the world around me instead of living through a screen"
        case .creativity: return "Use my hands and mind to make things, not just consume"
        }
    }
    
    var timeImpact: String {
        switch self {
        case .morningRoutine: return "15-30 min saved"
        case .deepWork: return "1-2 hours saved"
        case .quality_time: return "Priceless"
        case .reading: return "30-60 min saved"
        case .sleep: return "Better rest"
        case .presence: return "Moments matter"
        case .creativity: return "Hours reclaimed"
        }
    }
    
    var emoji: String {
        switch self {
        case .morningRoutine: return "☀️"
        case .deepWork: return "🎯"
        case .quality_time: return "❤️"
        case .reading: return "📚"
        case .sleep: return "😴"
        case .presence: return "🌿"
        case .creativity: return "🎨"
        }
    }
}
