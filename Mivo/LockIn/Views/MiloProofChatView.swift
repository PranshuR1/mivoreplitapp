import PhotosUI
import SwiftUI

/// The conversation where the person explains what they did and shows it. Milo reads
/// the words and any photos and decides whether the work looks done. With an active
/// keyholder, Milo's yes is a recommendation and the keyholder has the last word.
struct MiloProofChatView: View {
    @ObservedObject private var manager = LockInManager.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    @State private var draft = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var attachments: [Attachment] = []
    /// Shown as a sent bubble while Milo reads it; the real one replaces it on success.
    @State private var pending: PendingMessage?
    @State private var errorText: String?
    @State private var isAsking = false
    @State private var isChecking = false
    @State private var confirmDirectAsk = false

    private struct Attachment: Identifiable {
        let id = UUID()
        let jpeg: Data
        let thumbnail: UIImage
    }

    private struct PendingMessage: Equatable {
        let text: String
        let imageCount: Int
    }

    private var miloName: String { companion.miloName }

    var body: some View {
        VStack(spacing: 0) {
            if let lock = manager.current {
                transcript(lock)
                composer(lock)
            }
        }
        .background(MivoColors.background.ignoresSafeArea())
        .navigationTitle(miloName)
        .navigationBarTitleDisplayMode(.inline)
        .hidesRoamingCompanion()
        // The lock ended while this was open: the wrap-up takes over.
        .onChange(of: manager.current == nil) { _, ended in
            if ended { dismiss() }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .confirmationDialog(
            "Ask \(manager.keyholder?.name ?? "your keyholder") without \(miloName)?",
            isPresented: $confirmDirectAsk,
            titleVisibility: .visible
        ) {
            Button("Send my request") { askKeyholder() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("They'll be told \(miloName) hasn't reviewed this, and shown what you last wrote.")
        }
    }

    // MARK: Transcript

    private func transcript(_ lock: LockIn) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    greeting(lock)

                    ForEach(lock.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if let pending {
                        bubble(LockInMessage(role: .user, text: pending.text, imageCount: pending.imageCount))
                            .opacity(0.7)
                            .id("pending")
                    }

                    if manager.isReviewing {
                        typingIndicator
                            .id("typing")
                    }

                    keyholderPanel(lock)
                        .padding(.top, 6)
                        .id("panel")

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: lock.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: manager.isReviewing) { _, _ in scrollToBottom(proxy) }
            .onChange(of: pending) { _, _ in scrollToBottom(proxy) }
            .onChange(of: lock.pendingRequest?.id) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(MivoMotion.standard(0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func greeting(_ lock: LockIn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                LockInMiloFigure(state: manager.isReviewing ? .curious : .idle, height: 110)
                Spacer()
            }
            miloBubble("Hi, it's \(miloName). You set out to “\(lock.task)”. Tell me what you did. Specifics help, and a photo or screenshot helps more.")
            LockInFootnote("Photos are checked by an AI and then dropped. Mivo doesn't keep them.")
                .padding(.horizontal, 4)
        }
    }

    // MARK: Bubbles

    @ViewBuilder
    private func bubble(_ message: LockInMessage) -> some View {
        switch message.role {
        case .user: userBubble(message.text, imageCount: message.imageCount)
        case .milo: miloBubble(message.text)
        }
    }

    private func miloBubble(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(MivoColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(MivoColors.hairline, lineWidth: 1)
                )
            Spacer(minLength: 44)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(miloName) says: \(text)")
    }

    private func userBubble(_ text: String, imageCount: Int) -> some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 6) {
                if imageCount > 0 {
                    Label(imageCount == 1 ? "1 photo" : "\(imageCount) photos", systemImage: "photo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.background.opacity(0.85))
                }
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.background)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(MivoColors.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You said: \(text)")
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(miloName) is looking…")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Keyholder panel

    @ViewBuilder
    private func keyholderPanel(_ lock: LockIn) -> some View {
        let name = lock.keyholder?.name ?? "your keyholder"
        if let request = lock.pendingRequest {
            MivoCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sent to \(name)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text("Your apps open as soon as they approve. Sent at \(LockInFormat.clock(request.sentAt)).")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    MivoTertiaryButton(label: isChecking ? "Checking…" : "Check now", height: 34) {
                        guard !isChecking else { return }
                        isChecking = true
                        Task {
                            await manager.pollKeyholderRequest()
                            isChecking = false
                        }
                    }
                }
            }
        } else if lock.canRequestKeyholder {
            if lock.miloIsConvinced {
                MivoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(miloName) is convinced")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        Text("\(name) has the last word. They'll be emailed what \(miloName) saw, in a sentence. No photos.")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        MivoPrimaryButton(label: isAsking ? "Sending…" : "Ask \(name) to unlock", disabled: isAsking) {
                            askKeyholder()
                        }
                    }
                }
            } else if lock.userMessageCount > 0 {
                MivoTertiaryButton(label: "Ask \(name) without \(miloName)", color: MivoColors.inkBody) {
                    confirmDirectAsk = true
                }
            }
        }
    }

    // MARK: Composer

    @ViewBuilder
    private func composer(_ lock: LockIn) -> some View {
        VStack(spacing: 8) {
            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if lock.pendingRequest != nil {
                LockInFootnote("Waiting on \(lock.keyholder?.name ?? "your keyholder"). You can't add more until they answer.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if lock.userMessageCount >= LockInRules.maxUserMessages {
                LockInFootnote("This chat is full. The lock ends at the check-in time, or when your keyholder approves.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !attachments.isEmpty { attachmentStrip }
                HStack(alignment: .bottom, spacing: 10) {
                    photoButton
                    TextField("What did you do?", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.system(size: 15, weight: .medium))
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(MivoColors.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(MivoColors.hairline, lineWidth: 1)
                        )
                        .submitLabel(.return)
                    sendButton
                }
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(MivoColors.background.shadow(color: .black.opacity(0.05), radius: 6, y: -2))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !manager.isReviewing
    }

    private var photoButton: some View {
        let remaining = max(0, LockInRules.maxImagesPerMessage - attachments.count)
        return PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, remaining),
            matching: .images
        ) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(remaining == 0 ? MivoColors.inkMuted : MivoColors.deep)
                .frame(width: 44, height: 44)
                .background(MivoColors.surfaceV2)
                .clipShape(Circle())
        }
        .disabled(remaining == 0 || manager.isReviewing)
        .accessibilityLabel("Add a photo or screenshot")
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(canSend ? .white : MivoColors.inkMuted)
                .frame(width: 44, height: 44)
                .background(canSend ? MivoColors.accent : MivoColors.ink.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(MivoPressStyle())
        .disabled(!canSend)
        .accessibilityLabel("Send to \(miloName)")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Image(uiImage: attachment.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo")
                        }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 6)
        }
        .frame(height: 70)
    }

    // MARK: Actions

    private func send() {
        let text = draft
        let pictures = attachments
        guard canSend else { return }
        errorText = nil
        composerFocused = false
        pending = PendingMessage(text: LockInRules.cleanMessage(text), imageCount: pictures.count)
        HapticsService.selection()

        Task {
            let outcome = await manager.send(text: text, images: pictures.map(\.jpeg))
            pending = nil
            switch outcome {
            case .sent:
                draft = ""
                attachments = []
            case .failed(let error):
                errorText = error == .offline || error == .failed
                    ? "\(miloName) couldn't look just now. Your message is still here. Try again."
                    : error.message
                HapticsService.warning()
            case .notAllowed:
                errorText = "That couldn't be sent."
            }
        }
    }

    private func askKeyholder() {
        guard !isAsking else { return }
        isAsking = true
        errorText = nil
        Task {
            let result = await manager.askKeyholder()
            if case .failure(let error) = result {
                errorText = error.message
                HapticsService.warning()
            } else {
                HapticsService.success()
            }
            isAsking = false
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var added: [Attachment] = []
        for item in items {
            guard attachments.count + added.count < LockInRules.maxImagesPerMessage else { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = LockInImagePrep.jpeg(fromData: data),
                  let thumbnail = UIImage(data: jpeg) else { continue }
            added.append(Attachment(jpeg: jpeg, thumbnail: thumbnail))
        }
        attachments.append(contentsOf: added)
        pickerItems = []
    }
}
