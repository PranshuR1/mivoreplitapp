import SwiftUI

private let intentionPrompts = [
    "What are you hoping to find right now?",
    "Is this the best use of this moment?",
    "What will you do after you close the app?",
    "You've been here before. What's different this time?",
    "What was the last thing you scrolled past that mattered?",
]

struct InterventionView: View {
    @Environment(\.dismiss) var dismiss
    let intention: Intention?
    let duration: Int?
    let canCloseEarly: Bool
    let completionTitle: String
    let onComplete: (() -> Void)?

    @State private var countdown = 5
    @State private var canProceed = false
    @State private var prompt: String
    @State private var opacity = 0.0
    @State private var showSession = false
    @State private var selectedUrge: UrgeReason? = nil
    @State private var urgeNote = ""

    var isSessionStart: Bool { intention != nil && duration != nil }

    init(
        intention: Intention?,
        duration: Int?,
        canCloseEarly: Bool = true,
        completionTitle: String = "Open the app",
        onComplete: (() -> Void)? = nil
    ) {
        self.intention = intention
        self.duration = duration
        self.canCloseEarly = canCloseEarly
        self.completionTitle = completionTitle
        self.onComplete = onComplete
        _prompt = State(initialValue: intentionPrompts.randomElement() ?? "Take one breath before you continue.")
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if canCloseEarly {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18))
                                .foregroundColor(MivoColors.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    Spacer()
                }

                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(MivoColors.accentMuted)
                            .frame(width: 80, height: 80)
                        Image(systemName: "pause.circle")
                            .font(.system(size: 34))
                            .foregroundColor(MivoColors.accent)
                    }

                    Text("Just a moment.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)

                    Text(prompt)
                        .font(.system(size: 18))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 8)

                    // Countdown
                    VStack(spacing: 4) {
                        if !canProceed {
                            Text("\(countdown)")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(MivoColors.accent)
                                .tracking(-2)
                                .monospacedDigit()
                            Text("seconds")
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textMuted)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(MivoColors.timerGreen)
                                Text("Pause complete")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MivoColors.timerGreen)
                            }
                            .frame(height: 72)
                        }
                    }
                    .frame(minHeight: 72)

                    Text("Mivo doesn't stop you from using your apps.\nIt just asks you to notice before you do.")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 8)

                    if isSessionStart && canProceed {
                        urgeJournal
                    }
                }
                .opacity(opacity)

                Spacer()

                // Actions
                VStack(spacing: 10) {
                    if let intention, let duration {
                        NavigationLink {
                            ActiveSessionView(
                                intention: intention,
                                plannedMinutes: duration,
                                urgeReason: selectedUrge,
                                urgeNote: selectedUrge == .other ? urgeNote.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                        } label: {
                            Text(sessionButtonTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canBeginSession ? MivoColors.accent : MivoColors.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canBeginSession)
                    } else {
                        Button {
                            complete()
                        } label: {
                            Text(canProceed ? completionTitle : "Wait \(countdown)s...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canProceed ? MivoColors.accent : MivoColors.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canProceed)
                    }

                    if canCloseEarly {
                        Button { dismiss() } label: {
                            Text("Close")
                                .font(.system(size: 15))
                                .foregroundColor(MivoColors.textMuted)
                                .padding(.vertical, 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
            startCountdown()
        }
    }

    private var canBeginSession: Bool {
        guard canProceed else { return false }
        guard isSessionStart else { return true }
        return selectedUrge != nil
    }

    private var sessionButtonTitle: String {
        if !canProceed { return "Wait \(countdown)s..." }
        if selectedUrge == nil { return "Choose why first" }
        return "Begin session"
    }

    private var urgeJournal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why did you open this?")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(UrgeReason.allCases) { reason in
                    Button {
                        selectedUrge = reason
                        HapticsService.selection()
                    } label: {
                        Text(reason.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedUrge == reason ? MivoColors.white : MivoColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedUrge == reason ? MivoColors.accent : MivoColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selectedUrge == reason ? MivoColors.accent : MivoColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedUrge == .other {
                TextField("Optional note", text: $urgeNote)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MivoColors.border, lineWidth: 1))
            }
        }
        .padding(14)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown <= 1 {
                timer.invalidate()
                canProceed = true
            } else {
                countdown -= 1
            }
        }
    }

    private func complete() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}
