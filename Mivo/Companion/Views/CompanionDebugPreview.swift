#if DEBUG
import SwiftUI

/// Debug-only launch targets for reviewing the Companion screens without
/// signing in: `-MivoPreviewCompanion <home|settings|onboarding|pause|sleeping>`.
/// Uses a throwaway account key, wiped on each launch.
struct CompanionPreviewHost: View {
    let mode: String
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                switch mode {
                case "onboarding":
                    NavigationStack { CompanionEntryView() }
                case "settings":
                    NavigationStack { CompanionSettingsView() }
                case "pause":
                    MidScrollCheckInView(seconds: 600)
                default:
                    NavigationStack { CompanionEntryView() }
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard !ready else { return }
            seed()
            ready = true
        }
        .task {
            // With no signed-in account the app may run its sign-out cleanup a
            // moment after launch, which clears the companion; seed once more.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            seed()
        }
    }

    private func seed() {
        let email = "companion-preview@mivo.test"
        let manager = CompanionStateManager.shared
        CompanionDeviceActivityAdapter.previewAccountEmail = email
        manager.prepare(forEmail: nil)
        StorageService.removeUserScopedMivoData(email: email)
        manager.prepare(forEmail: email)
        if mode != "onboarding" {
            manager.completeOnboarding(name: "Milo", personality: .gentle)
        }
        if mode == "sleeping" {
            manager.updatePreferences { $0.quietHours = CompanionTimeWindow(isEnabled: true, start: .init(hour: 0), end: .init(hour: 23, minute: 59)) }
        }
    }
}
#endif
