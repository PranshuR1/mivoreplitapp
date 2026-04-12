import SwiftUI

private let durations: [(label: String, value: Int)] = [
    ("5 min", 5), ("10 min", 10), ("15 min", 15), ("20 min", 20), ("30 min", 30)
]

struct InterventionsView: View {
    @State private var delayEnabled = false
    @State private var selectedIntention: Intention? = nil
    @State private var selectedDuration: Int? = nil
    @State private var showIntervention = false
    @State private var showSession = false

    var canStart: Bool { selectedIntention != nil && selectedDuration != nil }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Start a Session")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)

                    Text("Set your intention and a limit before you open the app.")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(6)

                    // Why card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Why are you opening it?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)

                        VStack(spacing: 8) {
                            ForEach(Intention.allCases, id: \.rawValue) { intention in
                                Button {
                                    selectedIntention = intention
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                                                .frame(width: 20, height: 20)
                                            if selectedIntention == intention {
                                                Circle().fill(MivoColors.accent).frame(width: 20, height: 20)
                                                Circle().fill(MivoColors.white).frame(width: 8, height: 8)
                                            }
                                        }
                                        Text(intention.rawValue)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(selectedIntention == intention ? MivoColors.accent : MivoColors.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(selectedIntention == intention ? MivoColors.accentMuted : MivoColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // Duration card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How long?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)

                        HStack(spacing: 8) {
                            ForEach(durations, id: \.value) { item in
                                Button {
                                    selectedDuration = item.value
                                } label: {
                                    Text(item.label)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedDuration == item.value ? .white : MivoColors.textSecondary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(selectedDuration == item.value ? MivoColors.accent : MivoColors.background)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .flexibleWrapping()
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // Delay card
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Delay before apps")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(MivoColors.textPrimary)
                                Text("A 10s pause before your session begins")
                                    .font(.system(size: 13))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $delayEnabled)
                                .tint(MivoColors.accent)
                                .labelsHidden()
                        }
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // Practice pause card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Practice a pause")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text("See what a 5-second intervention feels like before you actually need one.")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(4)
                        Button {
                            showIntervention = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "pause.circle")
                                    .font(.system(size: 14))
                                Text("Try it now")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(MivoColors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(MivoColors.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                    // Start link — destination depends on whether delay is enabled
                    NavigationLink {
                        // destination chosen at time of navigation
                        if delayEnabled {
                            InterventionView(intention: nil, duration: nil)
                        } else {
                            ActiveSessionView(intention: selectedIntention ?? .relax, plannedMinutes: selectedDuration ?? 10)
                        }
                    } label: {
                        Text(canStart ? "Start \(selectedDuration!) min session" : "Choose intention and duration")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MivoColors.white)
                            .tracking(0.3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(canStart ? MivoColors.accent : MivoColors.accentLight)
                            .clipShape(Capsule())
                            .shadow(color: canStart ? MivoColors.accent.opacity(0.3) : .clear, radius: 12, y: 4)
                    }
                    .disabled(!canStart)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
        }
        .navigationBarHidden(true)
    }
}

extension View {
    func flexibleWrapping() -> some View {
        self
    }
}
