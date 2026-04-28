import SwiftUI

// MARK: - Onboarding Components

/// Reusable header component for onboarding steps
struct OnboardingStepHeader: View {
    let step: Int
    let total: Int
    let eyebrow: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress indicator
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? MivoColors.blue : MivoColors.muted.opacity(0.3))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            
            // Eyebrow text
            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.secondary)
                .tracking(1.2)
            
            // Title
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(2)
            
            // Subtitle
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(5)
        }
    }
}

/// Reusable backdrop for onboarding screens
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            
            LinearGradient(
                colors: [
                    MivoColors.heroText,
                    MivoColors.background,
                    MivoColors.surface.opacity(0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

/// Bottom bar container for onboarding CTAs
struct OnboardingBottomBar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Subtle divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            MivoColors.muted.opacity(0.1),
                            MivoColors.muted.opacity(0.3),
                            MivoColors.muted.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            content
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    MivoColors.background.opacity(0.95)
                        .background(.ultraThinMaterial)
                )
        }
    }
}

/// Primary button for onboarding
struct OnboardingPrimaryButton<TrailingIcon: View>: View {
    let title: String
    let trailingIcon: TrailingIcon
    let action: () -> Void
    
    init(_ title: String, @ViewBuilder trailingIcon: () -> TrailingIcon, action: @escaping () -> Void) {
        self.title = title
        self.trailingIcon = trailingIcon()
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                trailingIcon
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(MivoColors.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(MivoColors.blue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: MivoColors.blue.opacity(0.24), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// Entrance animation modifier for onboarding elements
struct OnboardingEntranceModifier: ViewModifier {
    let appear: Bool
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay), value: appear)
    }
}

extension View {
    func onboardingEntrance(_ appear: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingEntranceModifier(appear: appear, delay: delay))
    }
}

// MARK: - Data Models

enum PhoneFeeling: String, CaseIterable, Hashable, Codable {
    case anxious, fomo, numbed, overwhelmed, distracted, guilty, restless, compulsive
    
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

enum PhoneTrigger: String, CaseIterable, Hashable, Codable {
    case wakeUp, waiting, bored, anxious, eating, bathroom, bedtime, transition, notification, social
    
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

enum PhoneGoal: String, CaseIterable, Hashable, Codable {
    case morningRoutine, deepWork, quality_time, reading, sleep, presence, creativity
    
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

enum CommitmentLevel: String, CaseIterable, Hashable, Codable {
    case gentle, moderate, focused
    
    var title: String {
        switch self {
        case .gentle: return "Gentle start"
        case .moderate: return "Steady progress"
        case .focused: return "Focused change"
        }
    }
    
    var subtitle: String {
        switch self {
        case .gentle: return "Small steps, sustainable pace"
        case .moderate: return "Balanced and intentional"
        case .focused: return "Clear boundaries, faster results"
        }
    }
    
    var description: String {
        switch self {
        case .gentle: return "I want to build awareness first. Mivo will help me notice patterns without adding pressure. Perfect if you're just starting or prefer a softer approach."
        case .moderate: return "I'm ready to make real changes while staying flexible. Mivo will encourage progress and give gentle nudges when I need them."
        case .focused: return "I'm serious about this and want clear boundaries. Mivo will hold me accountable and help me stay on track with stronger friction."
        }
    }
    
    var features: [String] {
        switch self {
        case .gentle:
            return [
                "Pattern tracking and insights",
                "Optional pauses before opening apps",
                "Weekly reflections"
            ]
        case .moderate:
            return [
                "All Gentle features",
                "Daily intention prompts",
                "Truth check reminders",
                "Usage goal suggestions"
            ]
        case .focused:
            return [
                "All Moderate features",
                "Mandatory pause before selected apps",
                "Time limits and alerts",
                "Accountability check-ins"
            ]
        }
    }
}
