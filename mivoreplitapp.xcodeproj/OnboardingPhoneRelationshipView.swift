import SwiftUI

/// New onboarding step: Understanding the user's emotional relationship with their phone
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
        // Store in UserDefaults or append to AI dataset
        let feelingNames = selectedFeelings.map { $0.rawValue }
        let summary = "Phone feelings: \(feelingNames.joined(separator: ", "))"
        appVM.appendAISummary(summary)
    }
}

// MARK: - Phone Feeling Enum

enum PhoneFeeling: String, CaseIterable, Hashable, Codable {
    case anxious = "anxious"
    case fomo = "fomo"
    case numbed = "numbed"
    case overwhelmed = "overwhelmed"
    case distracted = "distracted"
    case guilty = "guilty"
    case restless = "restless"
    case compulsive = "compulsive"
    
    var title: String {
        switch self {
        case .anxious: return "Anxious"
        case .fomo: return "FOMO"
        case .numbed: return "Numbed"
        case .overwhelmed: return "Overwhelmed"
        case .distracted: return "Distracted"
        case .guilty: return "Guilty"
        case .restless: return "Restless"
        case .compulsive: return "Compulsive"
        }
    }
    
    var description: String {
        switch self {
        case .anxious: return "I feel tense or worried when using my phone"
        case .fomo: return "I'm afraid I'll miss something important"
        case .numbed: return "I scroll to avoid feeling or thinking"
        case .overwhelmed: return "Too much information, too fast"
        case .distracted: return "I can't focus on one thing"
        case .guilty: return "I know I should stop, but I don't"
        case .restless: return "I reach for my phone when I'm idle"
        case .compulsive: return "It feels automatic, not intentional"
        }
    }
    
    var emoji: String {
        switch self {
        case .anxious: return "😰"
        case .fomo: return "😨"
        case .numbed: return "😶"
        case .overwhelmed: return "🤯"
        case .distracted: return "🤪"
        case .guilty: return "😔"
        case .restless: return "😬"
        case .compulsive: return "🔁"
        }
    }
}
