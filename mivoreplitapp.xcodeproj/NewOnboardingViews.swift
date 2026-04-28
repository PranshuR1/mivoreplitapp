import SwiftUI

// MARK: - Step 2: Phone Relationship

struct OnboardingPhoneRelationshipView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedFeelings: Set<PhoneFeeling> = []
    @State private var appear = false
    
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 2,
                            total: 6,
                            eyebrow: "Self-awareness",
                            title: "How does your phone make you feel?",
                            subtitle: "Select all that resonate. There are no wrong answers—this helps Mivo understand you better."
                        )
                        .onboardingEntrance(appear)
                        
                        selectionSummary
                            .onboardingEntrance(appear, delay: 0.08)
                        
                        VStack(spacing: 12) {
                            ForEach(Array(PhoneFeeling.allCases.enumerated()), id: \.element) { index, feeling in
                                feelingCard(feeling)
                                    .onboardingEntrance(appear, delay: 0.14 + Double(index) * 0.06)
                            }
                        }
                        
                        insightBox
                            .onboardingEntrance(appear, delay: 0.6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                
                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingTriggersView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(selectedFeelings.isEmpty ? MivoColors.muted : MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: selectedFeelings.isEmpty ? .clear : MivoColors.blue.opacity(0.24), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        saveFeelings()
                        HapticsService.impact(style: .light)
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
    
    private var selectionSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFeelings.isEmpty ? "No feelings selected" : "\(selectedFeelings.count) feeling\(selectedFeelings.count == 1 ? "" : "s") selected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text(summaryMessage)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: selectedFeelings.isEmpty ? "heart" : "heart.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(selectedFeelings.isEmpty ? MivoColors.muted : MivoColors.blue)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private func feelingCard(_ feeling: PhoneFeeling) -> some View {
        let isSelected = selectedFeelings.contains(feeling)
        
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                if isSelected {
                    selectedFeelings.remove(feeling)
                } else {
                    selectedFeelings.insert(feeling)
                }
            }
            HapticsService.selection()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? MivoColors.blue.opacity(0.14) : MivoColors.surface)
                        .frame(width: 52, height: 52)
                    
                    Text(feeling.emoji)
                        .font(.system(size: 26))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(feeling.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(feeling.description)
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(2)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? MivoColors.blue : MivoColors.muted, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(MivoColors.blue)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(16)
            .background(MivoColors.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? MivoColors.blue.opacity(0.4) : MivoColors.white.opacity(0.58), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.025), radius: isSelected ? 12 : 6, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var insightBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 20))
                .foregroundColor(MivoColors.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Why this matters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Naming the feeling is the first step to changing the pattern. Mivo will use this to personalize your experience.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(MivoColors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MivoColors.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var summaryMessage: String {
        if selectedFeelings.isEmpty {
            return "Tap feelings that resonate with you."
        } else if selectedFeelings.count == 1 {
            return "This is a great start. Add more if they fit."
        } else if selectedFeelings.count <= 3 {
            return "You're building self-awareness."
        } else {
            return "You're seeing the pattern clearly."
        }
    }
    
    private func saveFeelings() {
        let feelingNames = selectedFeelings.map { $0.rawValue }
        let summary = "Phone feelings: \(feelingNames.joined(separator: ", "))"
        appVM.appendAISummary(summary)
    }
}

// MARK: - Step 3: Triggers

struct OnboardingTriggersView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedTriggers: Set<PhoneTrigger> = []
    @State private var appear = false
    
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 3,
                            total: 6,
                            eyebrow: "Awareness",
                            title: "When do you reach for your phone?",
                            subtitle: "These are your triggers. Understanding them helps you notice the pattern before it starts."
                        )
                        .onboardingEntrance(appear)
                        
                        selectionSummary
                            .onboardingEntrance(appear, delay: 0.08)
                        
                        VStack(spacing: 10) {
                            ForEach(Array(PhoneTrigger.allCases.enumerated()), id: \.element) { index, trigger in
                                triggerCard(trigger)
                                    .onboardingEntrance(appear, delay: 0.12 + Double(index) * 0.04)
                            }
                        }
                        
                        recognitionCard
                            .onboardingEntrance(appear, delay: 0.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                
                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingGoalsView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(selectedTriggers.isEmpty ? MivoColors.muted : MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: selectedTriggers.isEmpty ? .clear : MivoColors.blue.opacity(0.24), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        saveTriggers()
                        HapticsService.impact(style: .light)
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
    
    private var selectionSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTriggers.isEmpty ? "No triggers selected" : "\(selectedTriggers.count) trigger\(selectedTriggers.count == 1 ? "" : "s") identified")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text(summaryMessage)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: selectedTriggers.isEmpty ? "clock" : "clock.badge.checkmark.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(selectedTriggers.isEmpty ? MivoColors.muted : MivoColors.blue)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private func triggerCard(_ trigger: PhoneTrigger) -> some View {
        let isSelected = selectedTriggers.contains(trigger)
        
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                if isSelected {
                    selectedTriggers.remove(trigger)
                } else {
                    selectedTriggers.insert(trigger)
                }
            }
            HapticsService.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: trigger.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? MivoColors.blue : MivoColors.secondary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? MivoColors.blue.opacity(0.12) : MivoColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(trigger.description)
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textSecondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(MivoColors.blue)
                }
            }
            .padding(14)
            .background(MivoColors.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? MivoColors.blue.opacity(0.3) : MivoColors.white.opacity(0.58), lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.05 : 0.02), radius: isSelected ? 8 : 4, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private var recognitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22))
                    .foregroundColor(MivoColors.blue)
                
                Text("The Pattern Recognition")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
            }
            
            Text("Noticing the trigger is half the battle. When you catch yourself in one of these moments, Mivo will help you pause and choose intentionally.")
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)
            
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.accent)
                Text("You'll learn to see these moments before they become scrolls.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MivoColors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MivoColors.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var summaryMessage: String {
        if selectedTriggers.isEmpty {
            return "Think about your typical day."
        } else if selectedTriggers.count == 1 {
            return "That's a common one. Any others?"
        } else if selectedTriggers.count <= 3 {
            return "You're mapping your patterns."
        } else {
            return "Strong self-awareness. Keep going."
        }
    }
    
    private func saveTriggers() {
        let triggerNames = selectedTriggers.map { $0.rawValue }
        let summary = "Phone triggers: \(triggerNames.joined(separator: ", "))"
        appVM.appendAISummary(summary)
    }
}
// MARK: - Step 4: Goals

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

// MARK: - Step 5: Commitment

struct OnboardingCommitmentView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedCommitment: CommitmentLevel = .gentle
    @State private var personalPledge: String = ""
    @State private var appear = false
    @State private var showPledgeSheet = false
    
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 5,
                            total: 6,
                            eyebrow: "Your commitment",
                            title: "How do you want to approach this?",
                            subtitle: "There's no right answer. Choose the level that feels sustainable for where you are right now."
                        )
                        .onboardingEntrance(appear)
                        
                        VStack(spacing: 14) {
                            ForEach(Array(CommitmentLevel.allCases.enumerated()), id: \.element) { index, level in
                                commitmentCard(level)
                                    .onboardingEntrance(appear, delay: 0.1 + Double(index) * 0.08)
                            }
                        }
                        
                        pledgeSection
                            .onboardingEntrance(appear, delay: 0.4)
                        
                        reminderCard
                            .onboardingEntrance(appear, delay: 0.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                
                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingAppsView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Lock it in")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: MivoColors.blue.opacity(0.28), radius: 18, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        saveCommitment()
                        HapticsService.success()
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
        .sheet(isPresented: $showPledgeSheet) {
            pledgeSheetView
        }
    }
    
    private func commitmentCard(_ level: CommitmentLevel) -> some View {
        let isSelected = selectedCommitment == level
        
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                selectedCommitment = level
            }
            HapticsService.impact(style: .medium)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(level.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected ? MivoColors.blue : MivoColors.secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? MivoColors.blue : MivoColors.muted, lineWidth: 2.5)
                            .frame(width: 32, height: 32)
                        
                        if isSelected {
                            Circle()
                                .fill(MivoColors.blue)
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Text(level.description)
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(4)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(level.features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(isSelected ? MivoColors.blue : MivoColors.accent)
                            Text(feature)
                                .font(.system(size: 13))
                                .foregroundColor(MivoColors.textPrimary)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(isSelected ? MivoColors.blue.opacity(0.08) : MivoColors.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? MivoColors.blue.opacity(0.5) : MivoColors.white.opacity(0.58), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 14 : 6, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var pledgeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("✍️")
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Write your pledge")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Optional, but powerful")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textSecondary)
                }
                
                Spacer()
            }
            
            Button {
                showPledgeSheet = true
                HapticsService.selection()
            } label: {
                HStack {
                    if personalPledge.isEmpty {
                        Text("Tap to write a personal commitment")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textMuted)
                    } else {
                        Text(personalPledge)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MivoColors.textPrimary)
                            .lineLimit(3)
                    }
                    Spacer()
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(MivoColors.blue)
                }
                .padding(14)
                .background(MivoColors.white.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(MivoColors.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MivoColors.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var reminderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundColor(MivoColors.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("You can adjust this anytime")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Progress isn't linear. Mivo adapts as you do.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .padding(14)
        .background(MivoColors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var pledgeSheetView: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your personal pledge")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        Text("Write a commitment to yourself. This is private and will remind you why you started.")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ZStack(alignment: .topLeading) {
                        if personalPledge.isEmpty {
                            Text("E.g., 'I want to be present for my family' or 'I'm reclaiming my mornings'")
                                .font(.system(size: 15))
                                .foregroundColor(MivoColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        
                        TextEditor(text: $personalPledge)
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 150)
                    }
                    .background(MivoColors.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(MivoColors.muted.opacity(0.4), lineWidth: 1)
                    )
                    
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPledgeSheet = false
                    }
                    .foregroundColor(MivoColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        showPledgeSheet = false
                        HapticsService.success()
                    }
                    .foregroundColor(MivoColors.blue)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveCommitment() {
        let summary = "Commitment level: \(selectedCommitment.rawValue)"
        appVM.appendAISummary(summary)
        
        if !personalPledge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pledge = "Personal pledge: \(personalPledge)"
            appVM.appendAISummary(pledge)
        }
    }
}

