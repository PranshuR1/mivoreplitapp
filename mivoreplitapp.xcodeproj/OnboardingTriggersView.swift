import SwiftUI

/// New onboarding step: Understanding when and where the user reaches for their phone
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
                        OnboardingAppsView()
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

// MARK: - Phone Trigger Enum

enum PhoneTrigger: String, CaseIterable, Hashable, Codable {
    case wakeUp = "wake_up"
    case waiting = "waiting"
    case bored = "bored"
    case anxious = "anxious"
    case eating = "eating"
    case bathroom = "bathroom"
    case bedtime = "bedtime"
    case transition = "transition"
    case notification = "notification"
    case social = "social"
    
    var title: String {
        switch self {
        case .wakeUp: return "First thing in the morning"
        case .waiting: return "While waiting"
        case .bored: return "When I'm bored"
        case .anxious: return "When I'm anxious"
        case .eating: return "During meals"
        case .bathroom: return "In the bathroom"
        case .bedtime: return "Right before bed"
        case .transition: return "Between activities"
        case .notification: return "After a notification"
        case .social: return "In social settings"
        }
    }
    
    var description: String {
        switch self {
        case .wakeUp: return "Before I even get out of bed"
        case .waiting: return "In line, waiting for someone, etc."
        case .bored: return "To fill empty moments"
        case .anxious: return "To distract from stress"
        case .eating: return "Can't eat without scrolling"
        case .bathroom: return "Every single time"
        case .bedtime: return "The last thing I do at night"
        case .transition: return "Moving between tasks or locations"
        case .notification: return "Instantly, without thinking"
        case .social: return "Even when I'm with people"
        }
    }
    
    var icon: String {
        switch self {
        case .wakeUp: return "sunrise.fill"
        case .waiting: return "hourglass"
        case .bored: return "moon.zzz.fill"
        case .anxious: return "exclamationmark.triangle.fill"
        case .eating: return "fork.knife"
        case .bathroom: return "drop.fill"
        case .bedtime: return "bed.double.fill"
        case .transition: return "arrow.triangle.swap"
        case .notification: return "bell.badge.fill"
        case .social: return "person.2.fill"
        }
    }
}
