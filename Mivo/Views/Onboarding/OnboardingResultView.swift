import SwiftUI

struct OnboardingResultView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var estimate: Int? = nil
    @State private var showFinish = false
    @State private var spin = false
    @State private var appear = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("All set")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)

                Text("Here’s a quick estimate of how much time Mivo can help you save per day — based on your answers.")
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                ZStack {
                    Circle()
                        .stroke(MivoColors.border, lineWidth: 14)
                        .frame(width: 220, height: 220)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(Double(estimate ?? 0) / 120.0, 1.0)))
                        .stroke(AngularGradient(gradient: Gradient(colors: [MivoColors.accent, MivoColors.accentLight]), center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 220, height: 220)
                        .animation(.spring(response: 0.9, dampingFraction: 0.7), value: estimate)

                    VStack(spacing: 6) {
                        Text(estimate != nil ? "\(estimate!) min" : "—")
                            .font(.system(size: 36, weight: .bold).monospacedDigit())
                            .foregroundColor(MivoColors.textPrimary)
                        Text("estimated saved per day")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textMuted)
                    }
                }
                .padding(8)
                .onTapGesture {
                    HapticsService.impact(style: .medium)
                    withAnimation(.spring()) { spin.toggle() }
                }

                Text("Tip: This is an estimate. Mivo learns and personalizes as you use it.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer()

                Button {
                    // Dismiss first, then mark onboarding complete to avoid the onboarding navigation remaining on top
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                        appVM.completeOnboarding()
                        HapticsService.success()
                    }
                } label: {
                    Text("Finish setup")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .opacity(appear ? 1 : 0)
            .onAppear {
                appear = true
                computeEstimate()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    func computeEstimate() {
        // Use onboarding profile and AIService to compute estimated saved minutes per day
        // Heuristic fallback: saved = max(5, min(estimateReduction, 120))
        let profile = appVM.onboardingProfile
        let baseEstimate = profile.scrollEstimateMinutes ?? 60

        // Heuristic: if user selects intentions that include 'killTime' or 'bored', assume higher reducible time
        let multiplier: Double
        if profile.intentions.contains(.killTime) || profile.intentions.contains(.bored) {
            multiplier = 0.45
        } else if profile.intentions.contains(.relax) {
            multiplier = 0.25
        } else {
            multiplier = 0.18
        }

        // Age factor: younger users may reduce more quickly (heuristic)
        var ageFactor: Double = 1.0
        if let age = profile.age {
            if age < 25 { ageFactor = 1.05 }
            else if age > 54 { ageFactor = 0.9 }
        }

        let raw = Double(baseEstimate) * multiplier * ageFactor
        let saved = max(5, Int(raw.rounded()))

        // update estimate with modest animation and haptic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.9)) {
                estimate = min(saved, 120)
            }
            HapticsService.success()

            // also append AI summary
            var parts: [String] = []
            let ints = profile.intentions.map { $0.rawValue }
            if !ints.isEmpty { parts.append("Intentions: \(ints.joined(separator: ", "))") }
            if let s = profile.scrollEstimateMinutes { parts.append("Estimate: \(s) min/day") }
            if let a = profile.age { parts.append("Age: \(a)") }
            let summary = parts.joined(separator: " | ")
            if !summary.isEmpty { appVM.appendAISummary("Estimate: \(estimate ?? 0) min/day | \(summary)") }
        }
    }
}
