import AVFoundation
import SwiftUI

/// The study flow: name the one thing, prop the phone up across the room and
/// let it film your hands and desk, then get a receipt, a streak and the
/// scroll time the video earned. Face optional — the back camera is used.
struct StudySessionView: View {
    @ObservedObject private var study = StudyService.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @ObservedObject private var plus = MivoPlusStore.shared
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var paywallFeature: PlusFeature?
    @State private var task = ""
    @State private var now = Date()
    @State private var isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            switch study.phase {
            case .idle: idle
            case .running(let active): running(active)
            case .finished(let receipt): finished(receipt)
            }
        }
        .onReceive(ticker) { _ in
            now = Date()
            isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        }
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .sheet(item: $paywallFeature) { feature in
            MivoPlusPaywallView(feature: feature)
                .environmentObject(appVM)
        }
    }

    private var hasPlus: Bool {
        MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
    }

    private var earnsScroll: Bool {
        StudyTrial.earnsScroll(study.trialPhase, hasPlus: hasPlus)
    }

    // MARK: - Before

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                }

                Text("What's the one thing you're doing?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(MivoColors.ink)

                MivoTextField(label: "Task", placeholder: "Chapter 4 notes", text: $task)

                VStack(alignment: .leading, spacing: 10) {
                    setupLine("powerplug", "Plug the phone in and prop it up across the room.")
                    setupLine("camera", "Point it at your hands and desk. Your face is optional.")
                    setupLine("lock.slash", "Leave Mivo open on this screen. Video stays on this phone.")
                    if earnsScroll {
                        setupLine("hourglass", "Every 3 minutes on video earns 1 minute of scroll, up to \(ReelBalance.dailyEarnCapSeconds / 60) a day.")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MivoColors.surface))

                trialNotice

                MivoPrimaryButton(label: "Start") {
                    Task { await study.start(task: task) }
                }
                .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                stats
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// Where the person stands in the free week. Plus never sees it.
    @ViewBuilder
    private var trialNotice: some View {
        if !hasPlus {
            VStack(alignment: .leading, spacing: 8) {
                Text(trialLine)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                if study.trialPhase == .ended {
                    MivoTertiaryButton(label: "See Mivo Plus") { paywallFeature = .studyScroll }
                }
            }
        }
    }

    private var trialLine: String {
        switch study.trialPhase {
        case .notStarted:
            return "Your first \(StudyTrial.days) days earn scroll time free. After that, earning it needs Mivo Plus."
        case .running(let daysLeft):
            return "Free week: \(daysLeft == 1 ? "1 day" : "\(daysLeft) days") left to earn scroll time. After that it needs Mivo Plus."
        case .ended:
            return "Your free week is over. Sessions still count for your streak, but earning scroll time needs Mivo Plus."
        }
    }

    private func setupLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statTile("Today", StudyFormat.minutes(study.studiedTodaySeconds))
            statTile("Streak", study.streak > 0 ? StudyFormat.days(study.streak) : "None yet")
            statTile("Scroll earned", StudyFormat.minutes(study.earnedTodaySeconds))
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MivoColors.surface))
    }

    // MARK: - During

    private func running(_ active: StudyService.Active) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Working on")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
            Text(active.task)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Text(StudyFormat.clock(now.timeIntervalSince(active.startedAt)))
                .font(.system(size: 64, weight: .heavy).monospacedDigit())
                .foregroundColor(MivoColors.ink)
                .padding(.top, 28)

            recordingStatus
                .padding(.top, 18)

            if !isCharging {
                Text("Plug in so the phone lasts the whole session.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 8)
            }

            if study.recorder.isRecording {
                CameraPreview(session: study.recorder.session)
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 20)
            }
            Spacer()

            MivoPrimaryButton(label: "Finish") {
                Task { await study.finish(hasPlus: hasPlus) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var recordingStatus: some View {
        if study.cameraUnavailable {
            Text("No camera, so this round won't earn scroll time.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.secondary)
        } else if study.recorder.wasCutShort {
            Text("Recording stopped. Time after this won't earn scroll time.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.secondary)
        } else if study.recorder.isRecording {
            Label("Recording", systemImage: "record.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.deep)
        }
    }

    // MARK: - After

    private func finished(_ receipt: StudyService.Receipt) -> some View {
        let entry = receipt.entry
        let earnedMinutes = entry.scrollSecondsEarned / 60
        let lockedMinutes = receipt.lockedScrollSeconds / 60
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Session done")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(MivoColors.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("You worked on")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                    Text(entry.task)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text(StudyFormat.minutes(entry.seconds))
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(MivoColors.ink)
                        .padding(.top, 8)
                    Text(entry.startedAt.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                    Text(entry.wasRecorded ? "Verified on video: \(StudyFormat.minutes(entry.recordedSeconds))" : "Not recorded, so not verified")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .padding(.top, 8)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MivoColors.surface))

                HStack(spacing: 12) {
                    statTile("Streak", StudyFormat.days(receipt.streak))
                    statTile("Scroll earned", earnedMinutes > 0 ? "+\(earnedMinutes) min" : (lockedMinutes > 0 ? "Needs Plus" : "None"))
                }

                Text("\(companion.miloName): \(MiloStudyVoice.receipt(earnedScrollMinutes: earnedMinutes, recorded: entry.wasRecorded, capReached: receipt.capReached, streak: receipt.streak, lockedScrollMinutes: lockedMinutes))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)

                if lockedMinutes > 0 {
                    MivoTertiaryButton(label: "Add \(lockedMinutes) min with Mivo Plus") { paywallFeature = .studyScroll }
                }

                Text("A day counts once you have a block of \(StudyLog.dayThresholdSeconds / 60) minutes.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)

                MivoPrimaryButton(label: "Done") {
                    study.reset()
                    task = ""
                    dismiss()
                }
                MivoTertiaryButton(label: "Start another") {
                    study.reset()
                    task = ""
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
}

enum StudyFormat {
    /// "Under a minute", "1 minute", "25 minutes".
    static func minutes(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m < 1 { return "Under a minute" }
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    static func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    /// "04:07" or "1:02:09".
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Presentation and Home tile

struct StudyPresenter: ViewModifier {
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var study = StudyService.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $study.showRequested) {
                StudySessionView()
                    .environmentObject(appVM)
            }
            .onAppear { study.bind() }
            .onChange(of: appVM.user?.email) { _, _ in study.bind() }
    }
}

extension View {
    /// The study flow's presentation layer. Apply once, at the root of the signed-in UI.
    func studyPresentation() -> some View {
        modifier(StudyPresenter())
    }
}

struct StudyHomeRow: View {
    @ObservedObject private var study = StudyService.shared
    @ObservedObject private var plus = MivoPlusStore.shared
    @EnvironmentObject private var appVM: AppViewModel

    private var subtitle: String {
        let earns = StudyTrial.earnsScroll(study.trialPhase, hasPlus: MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser))
        if !earns {
            return study.streak > 0 ? "\(StudyFormat.days(study.streak)) streak. Earning scroll time needs Plus." : "Film it. Keep your streak. Scroll time needs Plus."
        }
        return study.streak > 0 ? "\(StudyFormat.days(study.streak)) streak. Film it, earn scroll time." : "Name one thing. Film it. Earn scroll time."
    }

    var body: some View {
        MivoToolTile(
            icon: "books.vertical",
            title: "Study",
            subtitle: subtitle
        ) {
            study.showRequested = true
        }
    }
}
