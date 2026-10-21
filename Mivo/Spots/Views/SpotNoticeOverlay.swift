import SwiftUI

/// The quiet confirmation after a tag tap: "Study Desk activated — Focus for the
/// next hour." It appears over whatever is on screen, asks for nothing, and goes.
struct SpotNoticeOverlay: View {
    @ObservedObject private var manager = SpotManager.shared
    @State private var visible: SpotNotice?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let notice = visible {
                toast(notice)
                    .padding(.horizontal, MivoMetrics.screenPadding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .allowsHitTesting(visible != nil)
        .onAppear { present(manager.notice) }
        .onChange(of: manager.notice) { _, notice in present(notice) }
    }

    private func toast(_ notice: SpotNotice) -> some View {
        Button {
            HapticsService.selection()
            hide(notice)
            if notice.spotID != nil { manager.showActiveSpotRequested = true }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let icon = notice.icon {
                    SpotIconView(icon: icon, size: 40)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                    if let message = notice.message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .multilineTextAlignment(.leading)
                    }
                    if let caveat = notice.caveat {
                        Text(caveat)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.inkMuted)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .background(MivoColors.background.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func present(_ notice: SpotNotice?) {
        guard let notice else { return }
        // A notice that was raised while nothing could show it is stale by now.
        guard Date().timeIntervalSince(notice.createdAt) < 8 else {
            manager.notice = nil
            return
        }
        dismissTask?.cancel()
        withAnimation(MivoMotion.sheetPresent) { visible = notice }
        let seconds: Double = notice.caveat == nil && !notice.isError ? 3.4 : 6
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            hide(notice)
        }
    }

    private func hide(_ notice: SpotNotice) {
        dismissTask?.cancel()
        withAnimation(MivoMotion.sheetPresent) { visible = nil }
        if manager.notice?.id == notice.id { manager.notice = nil }
    }
}
