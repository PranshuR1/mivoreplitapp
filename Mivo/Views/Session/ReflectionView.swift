import SwiftUI

private let reflectionOptions: [(label: ReflectionChoice, desc: String)] = [
    (.yes, "Got what I came for"),
    (.kindOf, "Kind of, but not really"),
    (.no, "I just kept scrolling"),
]

private let outcomeOptions: [(label: SessionOutcomeScore, desc: String)] = [
    (.worthIt, "This felt useful"),
    (.mixed, "Some value, some drift"),
    (.notWorthIt, "Mostly automatic scrolling"),
]

struct ReflectionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    let sessionID: String
    let intention: Intention
    let plannedDuration: Int
    let actualDuration: Int
    let startTime: String
    let endTime: String
    let extendedOnce: Bool
    let urgeReason: UrgeReason?
    let urgeNote: String?
    let emergencyUnlockUsed: Bool
    let emergencyUnlockReason: String?
    var onSaved: (() -> Void)? = nil

    @State private var reflection: ReflectionChoice? = nil
    @State private var outcomeScore: SessionOutcomeScore? = nil
    @State private var note = ""
    @State private var saving = false
    @State private var recordedBaseSession = false

    var overBy: Int { actualDuration - plannedDuration }
    private var sessionDateKey: String {
        // Keyed off the start time so a session that ends after midnight still
        // counts toward the day it began.
        let startedAt = ISO8601DateFormatter().date(from: startTime) ?? Date()
        return MivoDay.key(startedAt)
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Session complete")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                        .padding(.bottom, 20)
                    summarySection
                    reflectionSection
                    outcomeSection
                    noteSection
                    actionSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            recordBaseSessionIfNeeded()
        }
    }

    private var summarySection: some View {
        VStack(spacing: 12) {
            summaryRow("Time scrolled", value: formatDuration(actualDuration))
            summaryRow("Planned", value: formatDuration(plannedDuration))
            if overBy > 0 {
                summaryRow("Over by", value: formatDuration(overBy), valueColor: MivoColors.timerOrange)
            }
            summaryRow("Reason", value: intention.rawValue)
            if let urgeReason {
                summaryRow("Opened because", value: urgeReason.rawValue)
            }
            if emergencyUnlockUsed {
                summaryRow("Emergency unlock", value: "Used", valueColor: MivoColors.timerOrange)
            }
            if extendedOnce {
                Label("Extended once", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.timerOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MivoColors.timerOrange.opacity(0.1))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
        .padding(.bottom, 28)
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Did you get what you came for?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(reflectionOptions, id: \.label.rawValue) { option in
                    reflectionOptionButton(option)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func reflectionOptionButton(_ option: (label: ReflectionChoice, desc: String)) -> some View {
        Button {
            reflection = option.label
        } label: {
            optionRow(
                title: option.label.rawValue,
                description: option.desc,
                selected: reflection == option.label
            )
        }
        .buttonStyle(.plain)
    }

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Was this worth it?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(outcomeOptions, id: \.label.rawValue) { option in
                    Button {
                        outcomeScore = option.label
                    } label: {
                        optionRow(
                            title: option.label.rawValue,
                            description: option.desc,
                            selected: outcomeScore == option.label
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func optionRow(title: String, description: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selected ? MivoColors.accent : MivoColors.textPrimary)
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(selected ? MivoColors.accentMuted : MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? MivoColors.accent : MivoColors.border, lineWidth: 1)
        )
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything else? (optional)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("What were you actually doing...")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                }
                TextEditor(text: $note)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 90)
            }
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MivoColors.border, lineWidth: 1))
        }
        .padding(.bottom, 24)
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button("Save session") { saveSession(withReflection: true) }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MivoColors.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(saving)
            Button("Skip reflection") { saveSession(withReflection: false) }
                .font(.system(size: 15))
                .foregroundColor(MivoColors.textMuted)
                .padding(.vertical, 14)
                .disabled(saving)
        }
    }

    @ViewBuilder
    func summaryRow(_ label: String, value: String, valueColor: Color = MivoColors.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(valueColor)
        }
    }

    func saveSession(withReflection: Bool) {
        saving = true
        let session = makeSession(withReflection: withReflection)
        let inserted = appVM.upsertSession(session)
        if inserted {
            appVM.appendAISummary(sessionAISummary(session))
        }
        appVM.finishMivoSession()
        // Pop back to the tab root via the onSaved callback
        onSaved?()
        dismiss()
    }

    private func recordBaseSessionIfNeeded() {
        guard !recordedBaseSession else { return }
        recordedBaseSession = true
        let session = makeSession(withReflection: false)
        let inserted = appVM.upsertSession(session)
        if inserted {
            appVM.appendAISummary(sessionAISummary(session))
        }
    }

    private func makeSession(withReflection: Bool) -> Session {
        Session(
            id: sessionID,
            date: sessionDateKey,
            startTime: startTime,
            endTime: endTime,
            plannedDuration: plannedDuration,
            actualDuration: actualDuration,
            intention: intention,
            extendedOnce: extendedOnce,
            reflection: withReflection ? reflection : nil,
            reflectionNote: withReflection ? note.trimmingCharacters(in: .whitespaces) : "",
            urgeReason: urgeReason,
            urgeNote: urgeNote,
            outcomeScore: withReflection ? outcomeScore : nil,
            emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockReason
        )
    }

    private func sessionAISummary(_ session: Session) -> String {
        var parts: [String] = [
            "Session: \(session.actualDuration)m actual / \(session.plannedDuration)m planned",
            "Intention: \(session.intention.rawValue)"
        ]
        if let urge = session.urgeReason { parts.append("Urge: \(urge.rawValue)") }
        if let outcome = session.outcomeScore { parts.append("Outcome: \(outcome.rawValue)") }
        if session.emergencyUnlockUsed == true { parts.append("EmergencyUnlock: true") }
        if session.extendedOnce { parts.append("Extended: true") }
        return parts.joined(separator: " | ")
    }
}
