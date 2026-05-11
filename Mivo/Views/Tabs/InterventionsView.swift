import SwiftUI

private let durations: [(label: String, value: Int)] = [
    ("5 min", 5), ("10 min", 10), ("15 min", 15), ("20 min", 20), ("30 min", 30)
]

struct InterventionsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedIntention: Intention? = nil
    @State private var selectedDuration: Int? = nil
    @State private var customDurationText = ""
    @State private var durationLimitNotice: String? = nil
    @State private var showIntervention = false
    @State private var appear = false
    @State private var pulse = false
    @FocusState private var customDurationFocused: Bool

    var durationLimit: (maxMinutes: Int, isLimited: Bool, message: String, windowTitle: String) {
        appVM.adaptiveSessionDurationLimit()
    }
    var selectedDurationAllowed: Bool {
        guard let selectedDuration else { return false }
        return selectedDuration >= 1 && selectedDuration <= durationLimit.maxMinutes
    }
    var canStart: Bool { selectedIntention != nil && selectedDurationAllowed }
    var startSelection: (intention: Intention, duration: Int)? {
        guard let intention = selectedIntention, let duration = selectedDuration, selectedDurationAllowed else { return nil }
        return (intention, duration)
    }
    var statusText: String {
        if let selection = startSelection { return "\(selection.intention.rawValue) · \(selection.duration) min" }
        if durationLimit.maxMinutes == 0 { return "No scroll window open" }
        if let selectedDuration, selectedDuration > durationLimit.maxMinutes { return "Mivo recommends \(durationLimit.maxMinutes) min or less" }
        if selectedIntention != nil { return "Choose a time limit" }
        return "Choose why you are opening it"
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if appVM.mivoLaunchGateActive {
                        mivoGateCard
                    }
                    heroCard
                    sessionBuilderCard
                    practiceCard
                    startSessionButton
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 18)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showIntervention) {
            InterventionView(intention: nil, duration: nil, completionTitle: "Back to Mivo")
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) { appear = true }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) { pulse = true }
            clampSelectedDurationIfNeeded()
        }
        .onChange(of: customDurationText) { value in
            applyCustomDuration(value)
        }
        .alert("Adaptive limit", isPresented: Binding(
            get: { durationLimitNotice != nil },
            set: { if !$0 { durationLimitNotice = nil } }
        )) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(durationLimitNotice ?? "")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Interventions")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.heroText)
                        .tracking(-0.8)
                    Text("Add a little friction before the scroll takes over.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.heroText.opacity(0.82))
                        .lineSpacing(4)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(MivoColors.accent.opacity(pulse ? 0.55 : 0.18), lineWidth: 8)
                        .frame(width: pulse ? 62 : 50, height: pulse ? 62 : 50)
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(MivoColors.heroText)
                }
                .frame(width: 64, height: 64)
            }

            HStack(spacing: 10) {
                heroMetric(title: "Session", value: canStart ? "Ready" : "Setup", icon: canStart ? "checkmark" : "slider.horizontal.3")
                heroMetric(title: durationLimit.windowTitle, value: durationLimit.maxMinutes > 0 ? "\(durationLimit.maxMinutes)m left" : "Closed", icon: "timer")
            }
        }
        .padding(20)
        .background(MivoColors.heroBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MivoColors.textPrimary.opacity(0.12), radius: 18, y: 8)
    }

    private var mivoGateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.open.rotation")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set the intervention")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Your selected app is still locked. Choose why you opened it and set a time limit, then Mivo will let the app open with intention.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
            }

            HStack(spacing: 8) {
                Label("Pick a reason", systemImage: selectedIntention == nil ? "1.circle" : "checkmark.circle.fill")
                Label("Set a limit", systemImage: selectedDuration == nil ? "2.circle" : "checkmark.circle.fill")
                Label("Start", systemImage: "play.circle.fill")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(MivoColors.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.62), lineWidth: 1))
        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 16, y: 8)
    }

    private func heroMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 28, height: 28)
                .background(MivoColors.accent.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.heroText.opacity(0.68))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(MivoColors.background.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var sessionBuilderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Session builder", subtitle: statusText, icon: "target")

            VStack(alignment: .leading, spacing: 10) {
                Text("Why are you opening it?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)

                VStack(spacing: 8) {
                    ForEach(Intention.allCases, id: \.rawValue) { intention in
                        intentionRow(intention)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How long?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)

                HStack(spacing: 8) {
                    Image(systemName: durationLimit.maxMinutes > 0 ? "calendar.badge.clock" : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(durationLimit.windowTitle)
                    Spacer(minLength: 0)
                    Text(durationLimit.maxMinutes > 0 ? "\(durationLimit.maxMinutes) min available" : "come back later")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(durationLimit.maxMinutes > 0 ? MivoColors.accent : MivoColors.textMuted)
                .padding(10)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                    ForEach(durations, id: \.value) { item in
                        durationChip(item)
                    }
                }

                customDurationField

                Label(durationLimit.message, systemImage: durationLimit.isLimited ? "sparkles" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.border.opacity(0.65), lineWidth: 1))
    }

    private func intentionRow(_ intention: Intention) -> some View {
        let selected = selectedIntention == intention
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedIntention = intention
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: intentionIcon(intention))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(selected ? MivoColors.heroText : MivoColors.accent)
                    .frame(width: 32, height: 32)
                    .background(selected ? MivoColors.accent : MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(intention.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(selected ? MivoColors.accent : MivoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(selected ? MivoColors.accent : MivoColors.muted)
            }
            .padding(12)
            .background(selected ? MivoColors.background : MivoColors.white.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(selected ? 1.015 : 1)
        }
        .buttonStyle(.plain)
    }

    private func durationChip(_ item: (label: String, value: Int)) -> some View {
        let selected = selectedDuration == item.value
        let locked = item.value > durationLimit.maxMinutes
        return Button {
            guard !locked else {
                durationLimitNotice = durationLimit.maxMinutes == 0
                    ? durationLimit.message
                    : "\(durationLimit.message)\n\nChoose \(durationLimit.maxMinutes) min or less."
                HapticsService.warning()
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectedDuration = item.value
                customDurationText = ""
                customDurationFocused = false
            }
        } label: {
            HStack(spacing: 5) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(item.label)
                    .font(.system(size: 14, weight: .bold))
            }
                .foregroundColor(selected ? MivoColors.heroText : (locked ? MivoColors.textMuted : MivoColors.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? MivoColors.accent : MivoColors.background.opacity(locked ? 0.48 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.clear : MivoColors.border.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var customDurationField: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 30, height: 30)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField("Custom minutes", text: $customDurationText)
                .keyboardType(.numberPad)
                .focused($customDurationFocused)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
                .disabled(durationLimit.maxMinutes == 0)

            Text("min")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
        }
        .padding(12)
        .background(MivoColors.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MivoColors.border.opacity(0.48), lineWidth: 1))
    }

    private var practiceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MivoColors.background)
                    .frame(width: 54, height: 54)
                Image(systemName: "hourglass")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .rotationEffect(.degrees(pulse ? 8 : -8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Practice the pause")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Preview the 5-second moment before it appears over selected apps.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()

            Button {
                showIntervention = true
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var startSessionButton: some View {
        let selection = startSelection
        let buttonText = durationLimit.maxMinutes == 0
            ? "Come back at planned time"
            : (selection.map { "Start \($0.duration) min session" } ?? "Choose intention and duration")

        return NavigationLink {
            if let selection {
                ActiveSessionView(
                    intention: selection.intention,
                    plannedMinutes: selection.duration,
                    urgeReason: nil,
                    urgeNote: nil
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: canStart ? "arrow.right.circle.fill" : "circle.dotted")
                    .font(.system(size: 18, weight: .bold))
                Text(buttonText)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(MivoColors.heroText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(canStart ? MivoColors.accent : MivoColors.muted)
            .clipShape(Capsule())
            .shadow(color: canStart ? MivoColors.accent.opacity(0.28) : .clear, radius: 14, y: 6)
            .scaleEffect(canStart && pulse ? 1.012 : 1)
        }
        .disabled(!canStart)
        .simultaneousGesture(TapGesture().onEnded {
            guard let selection else { return }
            appVM.markMivoLaunchSessionStarted(plannedMinutes: selection.duration)
            HapticsService.success()
        })
    }

    private func sectionTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 30, height: 30)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer()
        }
    }

    private func intentionIcon(_ intention: Intention) -> String {
        switch intention {
        case .killTime: return "clock"
        case .relax: return "leaf"
        case .bored: return "sparkles"
        case .lookingForSomethingSpecific: return "magnifyingglass"
        }
    }

    private func applyCustomDuration(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value {
            customDurationText = digits
            return
        }

        guard let minutes = Int(digits), minutes > 0 else {
            if selectedDuration != nil && customDurationFocused {
                selectedDuration = nil
            }
            return
        }

        let capped = min(minutes, 240)
        if capped != minutes {
            customDurationText = "\(capped)"
        }

        guard capped <= durationLimit.maxMinutes else {
            selectedDuration = nil
            durationLimitNotice = durationLimit.maxMinutes == 0
                ? durationLimit.message
                : "\(durationLimit.message)\n\nChoose \(durationLimit.maxMinutes) min or less."
            return
        }

        selectedDuration = capped
    }

    private func clampSelectedDurationIfNeeded() {
        guard let selectedDuration, selectedDuration > durationLimit.maxMinutes else { return }
        self.selectedDuration = nil
    }

}

extension View {
    func flexibleWrapping() -> some View {
        self
    }
}
