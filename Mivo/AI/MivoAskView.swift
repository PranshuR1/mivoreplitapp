import SwiftUI

/// Home tile for configured, signed-in accounts. Service outages fall back to bundled notes.
struct MivoAskRow: View {
    @State private var showAsk = false

    var body: some View {
        if MivoAI.isInstalled {
            MivoToolTile(icon: "bubble.left.and.text.bubble.right", title: "Ask Milo", subtitle: "Questions about Mivo, answered by Milo.") {
                showAsk = true
            }
            .sheet(isPresented: $showAsk) {
                NavigationStack {
                    MivoAskView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showAsk = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// A small chat with Milo about Mivo. Answers come from Mivo's notes, run on Mivo's own server;
/// selected notes and the question are sent through Mivo's authenticated AI service.
struct MivoAskView: View {
    private struct Line: Identifiable {
        let id = UUID()
        let fromMilo: Bool
        let text: String
    }

    private static let starters = [
        "What does Mivo Plus include?",
        "How does studying earn scroll time?",
        "How do I protect a commitment with Lock-in?",
        "How does Mivo Still work?",
    ]

    @State private var lines: [Line] = [
        Line(fromMilo: true, text: "Hi, I'm Milo. Ask me about Plus, studying, Lock-in or how Mivo works. I answer from what I know, and I'll say so when I don't.")
    ]
    @State private var draft = ""
    @State private var isThinking = false
    @State private var answerTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            bubble(line).id(line.id)
                        }
                        if isThinking {
                            Text("Milo is thinking…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(MivoColors.inkMuted)
                                .padding(.leading, 4)
                        }
                        if lines.count == 1 {
                            starterChips
                        }
                    }
                    .padding(16)
                }
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            inputBar
            Text("Your question is sent to Mivo's AI service.")
                .font(.system(size: 11))
                .foregroundColor(MivoColors.inkMuted)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(MivoColors.background.ignoresSafeArea())
        .navigationTitle("Ask Milo")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { answerTask?.cancel() }
    }

    private func bubble(_ line: Line) -> some View {
        HStack {
            if !line.fromMilo { Spacer(minLength: 40) }
            Text(line.text)
                .font(.system(size: 15))
                .foregroundColor(line.fromMilo ? MivoColors.ink : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(line.fromMilo ? MivoColors.surfaceRaised : MivoColors.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if line.fromMilo { Spacer(minLength: 40) }
        }
    }

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.starters, id: \.self) { question in
                Button(question) { send(question) }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.deep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MivoColors.surfaceV2)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about Mivo", text: $draft, axis: .vertical)
                .focused($focused)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(MivoColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .foregroundColor(canSend ? MivoColors.secondary : MivoColors.muted)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(MivoColors.background)
    }

    private var canSend: Bool {
        !isThinking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let question = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        lines.append(Line(fromMilo: false, text: question))
        isThinking = true
        answerTask = Task {
            let reply = await MivoAI.shared.answer(question)
            guard !Task.isCancelled else { return }
            lines.append(Line(
                fromMilo: true,
                text: reply ?? "I couldn't get an answer ready just now. Try again in a moment."
            ))
            isThinking = false
            answerTask = nil
        }
    }
}
