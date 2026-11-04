#if DEBUG
import SwiftUI

/// Debug-only launch targets for reviewing the Lock-in screens without signing in or
/// touching real Screen Time: `-MivoPreviewLockIn <home|setup|active|chat|waiting|wrapup|guide|keyholder>`.
/// Runs on scripted state: nothing is shielded, no email is sent, and Milo answers from
/// a short script (first "show me more", then "that looks done").
struct LockInPreviewHost: View {
    let mode: String

    @MainActor private static var installed = false

    init(mode: String) {
        self.mode = mode
        Self.installIfNeeded()
        // Seeded here as well as after launch, so screens that read the manager when
        // they are created (the setup flow's remembered apps) already see it.
        Self.seed(mode: mode)
    }

    var body: some View {
        Group {
            switch mode {
            case "setup":
                LockInSetupFlowView()
            case "chat":
                NavigationStack { MiloProofChatView() }
            case "wrapup":
                LockInWrapUpView(lock: Self.sampleReleased())
            case "guide":
                NavigationStack { LockInScreenTimeGuideView() }
            case "keyholder":
                NavigationStack { LockInKeyholderView() }
            default:
                NavigationStack { LockInEntryView() }
            }
        }
        .task {
            // The app may run its sign-out cleanup a moment after launch when no one
            // is signed in, which would clear the scripted state; seed once more.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            Self.seed(mode: mode)
        }
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        let backend = InMemoryLockInBackend()
        backend.reviews = [
            MiloReview(
                verdict: .needsMore,
                reply: "That sounds right. Can you show me the outline itself? A photo or screenshot is fine.",
                summary: ""
            ),
            MiloReview(
                verdict: .convinced,
                reply: "I can see all four sections with notes under each. That's done.",
                summary: "Showed a four-section essay outline with notes under each heading."
            )
        ]
        LockInManager.installPreview(LockInManager(
            persistence: InMemoryLockInPersistence(),
            screenTime: NoopLockInScreenTime(),
            backend: backend
        ))
    }

    // MARK: Scripted state

    @MainActor
    private static func seed(mode: String) {
        let manager = LockInManager.shared
        let keyholder = LockInKeyholder(id: "kh-preview", name: "Dana", emailMasked: "d***@example.com", status: .active)
        let history = [sampleReleased(), sampleReleased(reason: .timeRanOut, task: "Study chapter 4")]

        switch mode {
        case "active":
            manager.seedPreview(current: sampleLock(keyholder: nil), history: history)
        case "chat":
            var lock = sampleLock(keyholder: nil)
            lock.messages = [
                LockInMessage(role: .user, text: "I finished the outline. Four sections, intro to conclusion.", sentAt: Date().addingTimeInterval(-300)),
                LockInMessage(role: .milo, text: "That sounds right. Can you show me the outline itself? A photo or screenshot is fine.", sentAt: Date().addingTimeInterval(-290))
            ]
            manager.seedPreview(current: lock, history: history)
        case "waiting":
            var lock = sampleLock(keyholder: keyholder)
            lock.miloSummary = "Showed a four-section essay outline with notes under each heading."
            lock.requests = [LockInUnlockRequest(
                id: "req-preview", sentAt: Date().addingTimeInterval(-120), status: .pending,
                keyholderNote: nil, summary: lock.miloSummary ?? ""
            )]
            manager.seedPreview(current: lock, history: history, keyholder: keyholder)
        case "keyholder":
            manager.seedPreview(current: nil, history: history, keyholder: keyholder)
        case "setup", "guide", "wrapup":
            manager.seedPreview(current: nil, history: history, lastApps: sampleApps)
        default:
            manager.seedPreview(current: nil, history: history)
        }
    }

    static let sampleApps = ScreenTimeAppSelection(
        data: nil,
        appNames: ["Instagram", "TikTok", "YouTube"],
        applicationCount: 3,
        categoryCount: 0,
        webDomainCount: 0
    )

    private static func sampleLock(keyholder: LockInKeyholder?) -> LockIn {
        let started = Date().addingTimeInterval(-25 * 60)
        return LockIn(
            id: "lock-preview",
            task: "Finish my essay outline",
            startedAt: started,
            endsAt: started.addingTimeInterval(2 * 3600),
            keyholder: keyholder,
            apps: sampleApps
        )
    }

    private static func sampleReleased(
        reason: LockInReleaseReason = .miloConvinced,
        task: String = "Finish my essay outline"
    ) -> LockIn {
        let started = Date().addingTimeInterval(-3 * 3600)
        var lock = LockIn(
            id: UUID().uuidString,
            task: task,
            startedAt: started,
            endsAt: started.addingTimeInterval(2 * 3600),
            keyholder: nil,
            apps: sampleApps
        )
        lock.releasedAt = started.addingTimeInterval(reason == .timeRanOut ? 2 * 3600 : 75 * 60)
        lock.releaseReason = reason
        return lock
    }
}
#endif
