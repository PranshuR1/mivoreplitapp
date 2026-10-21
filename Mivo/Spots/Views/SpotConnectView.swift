import SwiftUI
import UIKit

/// "Connect a Mivo Spot" — attaches an official Mivo Spot to a Spot setup that
/// already exists (a Digital Spot), so the person keeps its apps, behavior and
/// history. The person never writes anything to a tag: they hold the phone to
/// the Mivo Spot, Mivo reads its ID, and the claim flow takes it from there.
struct SpotPairSheet: View {
    let spotID: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = SpotManager.shared
    @ObservedObject private var nfc = SpotNFCService.shared

    @State private var message: String?
    @State private var showGuide = false

    private var spot: MivoSpot? { manager.spot(id: spotID) }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        MivoEyebrow(text: "Connect")
                            .padding(.top, 28)

                        Text("Connect a Mivo Spot")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(Font.mivoTracking(-0.025, at: 27))
                            .foregroundColor(MivoColors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)

                        Text("Hold your iPhone near your Mivo Spot. From then on, tapping it starts \(spot?.name ?? "this Spot") — with the apps, behavior and history it already has.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)

                        if let message {
                            Text(message)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(MivoColors.inkBody)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 18)
                        }

                        MivoPrimaryButton(
                            label: nfc.isWorking ? "Waiting for your Mivo Spot…" : "Scan your Mivo Spot",
                            disabled: nfc.isWorking || spot == nil || !SpotNFCService.isAvailable
                        ) {
                            scan()
                        }
                        .padding(.top, 24)

                        if !SpotNFCService.isAvailable {
                            Text(SpotNFCError.unavailable.message)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(MivoColors.inkMuted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }

                        MivoTertiaryButton(label: "How tapping works") { showGuide = true }
                            .padding(.top, 4)
                    }
                }
                MivoInkButton(label: "Not now") { dismiss() }
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showGuide) {
            SpotTapGuideView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func scan() {
        message = nil
        Task {
            do {
                let target = try await SpotNFCService.shared.scanSpot()
                guard case .physical(let physicalID) = target else {
                    message = SpotNFCError.notAMivoSpot.message
                    return
                }
                dismiss()
                await manager.presentPhysicalSpot(physicalID, pairWith: spotID)
            } catch let error as SpotNFCError {
                if error != .cancelled { message = error.message }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// The honest explanation of what a tap does on iOS, and the way to skip the banner.
struct SpotTapGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MivoEyebrow(text: "How tapping works")
                        .padding(.top, 28)

                    Text("What happens when you tap")
                        .font(.system(size: 27, weight: .bold))
                        .tracking(Font.mivoTracking(-0.025, at: 27))
                        .foregroundColor(MivoColors.ink)
                        .padding(.top, 10)

                    block(
                        title: "The standard tap",
                        body: "On iPhone XS and later, hold your Mivo Spot to the top of your iPhone with the screen on. iOS shows a Mivo banner — tap it and the Spot starts. iOS always asks before an NFC tag opens an app; Mivo can't skip that step, and no app can. Tap the Mivo Spot again to end it."
                    )
                    block(
                        title: "No banner: a Shortcut",
                        body: "Shortcuts can run Mivo the moment your Mivo Spot is scanned.\n\n1. Open Shortcuts → Automation → New Automation → NFC.\n2. Tap Scan and hold your Mivo Spot to your iPhone.\n3. Choose Run Immediately.\n4. Add the action “Tap a Spot” from Mivo and pick this Spot.\n\nThe Mivo Spot still works the normal way too."
                    )
                    block(
                        title: "Older iPhones",
                        body: "iPhone 7, 8 and X can't read NFC in the background. Add the NFC Tag Reader to Control Center, or use Scan your Mivo Spot at the top of Mivo Spots."
                    )
                    block(
                        title: "Changing what a Spot does",
                        body: "Your Mivo Spot only holds its own ID. Rename it, change its apps or turn a Study Spot into a Sleep Spot in Mivo any time — the Mivo Spot itself never needs to change."
                    )

                    MivoInkButton(label: "Done") { dismiss() }
                        .padding(.top, 28)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
            }
        }
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Text(body)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }
}

/// "Skip the banner" — the four steps that make a tap start a Spot with no banner.
///
/// iOS always shows a banner before an NFC tag opens an app, and an app can't
/// switch that off. A Shortcuts automation can (NFC trigger → Run Immediately), but
/// only the person can create it, so Mivo explains it where it matters: at the end
/// of setting up a Mivo Spot, and any time later from the Spot's page.
struct SpotInstantSteps: View {
    let spotName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Optional · about a minute")

            Text("Skip the banner")
                .font(.system(size: 22, weight: .bold))
                .tracking(Font.mivoTracking(-0.02, at: 22))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 10)

            Text("iOS shows a Mivo banner every time you tap a Mivo Spot, and only you can switch that off. Set up a Shortcut once and a tap starts \(spotName) straight away.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Open Shortcuts, tap Automation, then +, and choose NFC.")
                step(2, "Tap Scan and hold your Mivo Spot to the top of your iPhone. Name it “\(spotName)”.")
                step(3, "Add the action “Tap a Mivo Spot” and choose \(spotName).")
                step(4, "Choose Run Immediately (turn off Ask Before Running), then tap Done.")
            }
            .padding(.top, 20)

            MivoInkButton(label: "Open Shortcuts") {
                HapticsService.selection()
                if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
            }
            .padding(.top, 20)

            Text("Do this once for each Mivo Spot. Tapping it again ends the Spot, just like before.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
                .frame(width: 24, height: 24)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The same steps on their own, from a Spot's page.
struct SpotInstantSheet: View {
    let spotName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SpotInstantSteps(spotName: spotName)
                        .padding(.top, 28)

                    MivoTertiaryButton(label: "Done") { dismiss() }
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
            }
        }
    }
}
