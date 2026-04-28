import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var protectionEnabled = false
    @State private var reflectionText = ""
    @State private var reflectionSaved = false

    private var minutesToday: Int {
        appVM.deviceActivityMinutesToday ?? appVM.todaysTotalMinutes
    }

    var body: some View {
        ZStack {
            homeBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    heroCard
                    metricsRow
                    protectionCard
                    insightCard
                    reflectionCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 118)
            }

            VStack {
                Spacer()
                focusCTA
            }
        }
        .navigationBarHidden(true)
    }

    private var homeBackdrop: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(hex: "#F6EEE6"),
                    MivoColors.background,
                    Color(hex: "#F3EBE3").opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MivoLogo(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(greeting()), \(firstName)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                Text(dateLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Spacer()

            Button {
                protectionEnabled.toggle()
                HapticsService.selection()
            } label: {
                Image(systemName: protectionEnabled ? "shield.fill" : "shield")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(protectionEnabled ? MivoColors.accent : MivoColors.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.white.opacity(0.58))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: "#4A2E1F"))
                .frame(minHeight: 246)

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(appVM.deviceActivityMinutesToday != nil ? "Device activity" : "Mivo sessions", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(minutesToday))
                        .font(.system(size: 58, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.72)
                    Text("screen time today")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.66))
                }

                progressBar

                HStack(spacing: 10) {
                    miniHeroPill(icon: "lock.open.fill", title: "\(appVM.todaysSessions.count)", subtitle: appVM.todaysSessions.count == 1 ? "unlock" : "unlocks")
                    miniHeroPill(icon: trendIcon, title: trendText, subtitle: "week")
                }
            }
            .padding(22)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 20, y: 10)
    }

    private var progressBar: some View {
        let target = max(appVM.onboardingProfile.scrollEstimateMinutes ?? 120, 30)
        let progress = min(Double(minutesToday) / Double(target), 1)

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "#F3EBE3"), Color(hex: "#E6B17E")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, proxy.size.width * progress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: progress)
                }
            }
            .frame(height: 11)

            HStack {
                Text("Daily baseline")
                Spacer()
                Text("\(target)m")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color.white.opacity(0.58))
        }
    }

    private func miniHeroPill(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#F3EBE3"))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.56))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(icon: "target", value: "\(appVM.todaysSessions.count)", label: "Sessions")
            metricCard(icon: "chart.line.uptrend.xyaxis", value: trendText, label: "vs last week", tint: trendTint)
            metricCard(icon: "brain.head.profile", value: "\(appVM.truthChecks.count)", label: "Truth checks")
        }
    }

    private func metricCard(icon: String, value: String, label: String, tint: Color = Color(hex: "#A97B5B")) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 21, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var protectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: protectionEnabled ? "shield.checkered" : "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(protectionEnabled ? Color(hex: "#A97B5B") : MivoColors.textSecondary)
                .frame(width: 46, height: 46)
                .background(Color(hex: "#F3EBE3"))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(protectionEnabled ? "Protection is on" : "Protection is ready")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(protectionEnabled ? "Mivo will add a pause before impulse opens." : "Turn on a softer delay before distracting apps.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $protectionEnabled)
                .tint(MivoColors.accent)
                .labelsHidden()
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Today’s read", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(statusTint)
            }

            Text(insightText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(5)

            HStack(spacing: 8) {
                ForEach(insightTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#F6EEE6"))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick reflection")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("One sentence is enough.")
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                if reflectionSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#A97B5B"))
                }
            }

            ZStack(alignment: .topLeading) {
                if reflectionText.isEmpty {
                    Text("What pulled your attention today?")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 17)
                }

                TextEditor(text: $reflectionText)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 104)
            }
            .background(MivoColors.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                saveReflection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("Save reflection")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MivoColors.textMuted.opacity(0.36) : MivoColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var focusCTA: some View {
        NavigationLink {
            FocusView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Enter Focus")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(MivoColors.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(MivoColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: MivoColors.textPrimary.opacity(0.24), radius: 18, y: 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var firstName: String {
        appVM.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        return fmt.string(from: Date())
    }

    private var trendText: String {
        "\(appVM.patternPercent >= 0 ? "+" : "")\(appVM.patternPercent)%"
    }

    private var trendIcon: String {
        appVM.patternPercent <= 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private var trendTint: Color {
        appVM.patternPercent <= 0 ? Color(hex: "#A97B5B") : MivoColors.timerRed
    }

    private var statusLabel: String {
        let baseline = max(appVM.onboardingProfile.scrollEstimateMinutes ?? 120, 30)
        if minutesToday == 0 { return "Quiet start" }
        if minutesToday < baseline / 2 { return "On track" }
        if minutesToday <= baseline { return "Watchful" }
        return "Over baseline"
    }

    private var statusTint: Color {
        switch statusLabel {
        case "Quiet start", "On track": return Color(hex: "#A97B5B")
        case "Watchful": return MivoColors.accent
        default: return MivoColors.timerRed
        }
    }

    private var insightText: String {
        if minutesToday == 0 {
            return "You haven’t logged screen time yet today. This is a good moment to set intention before the first unlock."
        }
        if appVM.patternPercent > 20 {
            return "Your usage is trending higher than last week. A short focus session now can keep the day from drifting."
        }
        if appVM.patternPercent < -10 {
            return "You’re trending lower than last week. Keep the same friction in place and let the quiet compound."
        }
        return "Your day is still shapeable. Use a pause before opening the apps you selected during onboarding."
    }

    private var insightTags: [String] {
        [
            protectionEnabled ? "Protected" : "Ready",
            appVM.deviceActivityMinutesToday != nil ? "Device data" : "Manual data",
            appVM.todaysSessions.isEmpty ? "No sessions" : "\(appVM.todaysSessions.count) sessions"
        ]
    }

    private func saveReflection() {
        guard !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        HapticsService.success()
        reflectionSaved = true
        reflectionText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            reflectionSaved = false
        }
    }
}
