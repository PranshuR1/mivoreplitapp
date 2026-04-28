import SwiftUI

/// New onboarding step: Personal commitment to change
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
                
                // Features list
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

// MARK: - Commitment Level Enum

enum CommitmentLevel: String, CaseIterable, Hashable, Codable {
    case gentle = "gentle"
    case moderate = "moderate"
    case focused = "focused"
    
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
