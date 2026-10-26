import SwiftUI

/// Settings → Lock-in → Keyholder: invite the friend who approves unlocks, see
/// whether they've agreed, or take them away between locks.
struct LockInKeyholderView: View {
    @ObservedObject private var manager = LockInManager.shared
    @ObservedObject private var companion = CompanionStateManager.shared

    @State private var name = ""
    @State private var email = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var confirmRemove = false

    private var miloName: String { companion.miloName }

    private var formFilled: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && LockInManager.isPlausibleEmail(email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    LockInTitle(
                        title: "Keyholder",
                        detail: "A friend who has the last word on your unlocks. \(miloName) checks your work first, then asks them."
                    )
                    .padding(.top, 8)

                    if let keyholder = manager.keyholder {
                        keyholderCard(keyholder)
                    } else {
                        inviteForm
                    }

                    whatTheySee
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Keyholder")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRoamingCompanion()
        .task { await manager.refreshKeyholder() }
        .confirmationDialog("Remove your keyholder?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await manager.removeKeyholder() }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("They can no longer approve unlocks. You can invite someone else.")
        }
    }

    // MARK: Keyholder

    private func keyholderCard(_ keyholder: LockInKeyholder) -> some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(keyholder.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Spacer()
                    LockInStatusPill(
                        text: keyholder.status == .active ? "Agreed" : "Invited",
                        tone: keyholder.status == .active ? .good : .warning
                    )
                }
                Text(keyholder.emailMasked)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)

                if keyholder.status == .active {
                    LockInFootnote("\(keyholder.name) has the last word on every lock you start from now on.")
                } else {
                    LockInFootnote("\(keyholder.name) hasn't opened the email and agreed yet. Until they do, \(miloName) decides.")
                    MivoTertiaryButton(label: isWorking ? "Checking…" : "Check now", height: 34) {
                        guard !isWorking else { return }
                        isWorking = true
                        Task {
                            await manager.refreshKeyholder()
                            isWorking = false
                        }
                    }
                }

                MivoHairline()

                if manager.isLocked {
                    LockInFootnote("You can't change your keyholder while a lock is running.")
                } else {
                    MivoTertiaryButton(label: "Remove keyholder", color: MivoColors.timerRed, height: 34) {
                        confirmRemove = true
                    }
                }
            }
        }
    }

    // MARK: Invite

    private var inviteForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Their name", text: $name, content: .givenName, keyboard: .default)
            field("Their email", text: $email, content: .emailAddress, keyboard: .emailAddress)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
            }

            MivoPrimaryButton(
                label: isWorking ? "Sending…" : "Send invite",
                disabled: !formFilled || isWorking || !manager.isBackendAvailable
            ) {
                invite()
            }
            .padding(.top, 8)

            if !manager.isBackendAvailable {
                LockInFootnote("Keyholders need Mivo's online service, which isn't set up on this build.", tone: MivoColors.timerRed)
            } else {
                LockInFootnote("They get one email asking if they'll be your keyholder. They don't need the app.")
            }
        }
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        content: UITextContentType,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16, weight: .semibold))
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .padding(16)
            .background(MivoColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
    }

    private func invite() {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            let result = await manager.inviteKeyholder(name: name, email: email)
            isWorking = false
            switch result {
            case .success:
                HapticsService.success()
                name = ""
                email = ""
            case .failure(let error):
                HapticsService.warning()
                errorText = error.message
            }
        }
    }

    // MARK: Privacy

    private var whatTheySee: some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoSectionTitle(text: "What they see")
            MivoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("The task you committed to", systemImage: "checkmark.circle")
                    Label("One sentence from \(miloName) about what you showed", systemImage: "text.bubble")
                    Label("When your check-in time is", systemImage: "clock")
                    Label("Never your photos, your apps, or your messages", systemImage: "eye.slash")
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .labelStyle(LockInInfoLabelStyle())
            }
        }
    }
}

private struct LockInInfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .foregroundColor(MivoColors.deep)
                .frame(width: 18)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Make it hard to undo

/// The full "Make it hard to undo" page, reached from the Lock-in home screen.
struct LockInScreenTimeGuideView: View {
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    LockInTitle(
                        title: "Make it hard to undo",
                        detail: "Mivo locks the apps. But anyone can open Settings and switch off Mivo's Screen Time access. A Screen Time code a friend sets closes that door."
                    )
                    .padding(.top, 8)
                    LockInScreenTimeGuideContent()
                        .padding(.top, 22)
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Hard to undo")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRoamingCompanion()
    }
}

/// The steps, shared by the setup flow and the guide page. Honest about two things:
/// the lock needs iOS 26.4, and Mivo cannot tell whether it has been turned on.
struct LockInScreenTimeGuideContent: View {
    @AppStorage("mivo.lockin.screenTimeLockConfirmed") private var confirmed = false

    private let version = ProcessInfo.processInfo.operatingSystemVersion

    private var supported: Bool { LockInRules.supportsScreenTimeLock(version) }

    private var versionLabel: String {
        "iOS \(version.majorVersion).\(version.minorVersion)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            availability

            VStack(alignment: .leading, spacing: 16) {
                if !supported {
                    MivoEyebrow(text: "Once you're on iOS 26.4")
                }
                LockInStepRow(number: 1, title: "Open Settings, then Screen Time")
                LockInStepRow(
                    number: 2,
                    title: "Tap “Lock Screen Time Settings” at the bottom"
                )
                LockInStepRow(
                    number: 3,
                    title: "Have a friend type a new Screen Time code",
                    detail: "Don't look. If you know the code, it doesn't work."
                )
                LockInStepRow(
                    number: 4,
                    title: "When it asks for an Apple ID, your friend enters their own",
                    detail: "Otherwise “Forgot Passcode” can reset the code with yours."
                )
            }
            .opacity(supported ? 1 : 0.6)

            if supported {
                Toggle(isOn: $confirmed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My friend set the code")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.ink)
                        Text("Mivo can't check this. It's a reminder for you.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MivoColors.inkMuted)
                    }
                }
                .tint(MivoColors.accent)
                .padding(14)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            }

            LockInFootnote("Once it's on, Screen Time can't be switched off and Mivo can't be deleted until the code is entered. Erasing the phone, or a friend who gives you the code, still gets around it. one sec and Freedom document the same steps.")
        }
    }

    private var availability: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: supported ? "checkmark.circle.fill" : "arrow.up.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(supported ? MivoColors.kept : MivoColors.deep)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(supported ? "Your iPhone can do this" : "Your iPhone needs an update first")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                Text(supported
                     ? "You're on \(versionLabel). This lock needs iOS 26.4 or later."
                     : "You're on \(versionLabel). This lock needs iOS 26.4 or later. Update in Settings → General → Software Update. Until then Lock-in works, but you could switch Mivo's Screen Time access off in Settings.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MivoColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }
}
