import SwiftUI

/// Shown only when a game's award exceeds what's left of today's *flexible*
/// allowance and no hard protection is active (that case routes to
/// `ProtectedTimeActiveView` instead, never here). `borrowMinutes` is
/// already clamped to what tomorrow can actually cover — never more than
/// the game awarded, and never more than tomorrow has room for.
struct TimeLoanConfirmationView: View {
    let awardedMinutes: Int
    let todayRemaining: Int
    let borrowMinutes: Int
    let tomorrowProjectedBefore: Int
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var grantedMinutes: Int { todayRemaining + borrowMinutes }
    private var tomorrowProjectedAfter: Int { max(0, tomorrowProjectedBefore - borrowMinutes) }
    private var fallsShortOfAward: Bool { grantedMinutes < awardedMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { onDecline() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .padding(.top, 8)

            MivoEyebrow(text: "TIME LOAN")
                .padding(.top, 12)

            Text("Borrow from tomorrow?")
                .font(.system(size: 25, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 25))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)

            Text("You earned \(awardedMinutes) min, but today only has \(todayRemaining) min left\(fallsShortOfAward ? " and tomorrow doesn't have the full difference to lend" : "").")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(13.5 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            balanceCard
                .padding(.top, 22)

            Text("Borrowing \(borrowMinutes) minute\(borrowMinutes == 1 ? "" : "s") means tomorrow starts with \(borrowMinutes) minute\(borrowMinutes == 1 ? "" : "s") less.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MivoColors.deep)
                .lineSpacing(12.5 * 0.4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 20)

            MivoPrimaryButton(label: "Borrow \(borrowMinutes) min and unlock") {
                HapticsService.impact(style: .medium)
                onConfirm()
            }

            declineOptions
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
    }

    private var balanceCard: some View {
        VStack(spacing: 0) {
            balanceRow(label: "Today remaining", value: "\(todayRemaining)m")
            Divider().overlay(MivoColors.hairline)
            balanceRow(label: "Borrowed from tomorrow", value: "+\(borrowMinutes)m")
            Divider().overlay(MivoColors.hairline)
            balanceRow(label: "Tomorrow starts with", value: "\(tomorrowProjectedAfter)m", emphasized: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(MivoColors.ink.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }

    private func balanceRow(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(emphasized ? MivoColors.deep : MivoColors.ink)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var declineOptions: some View {
        HStack(spacing: 8) {
            declineTextButton(label: "Stay protected")
            declineTextButton(label: "Try later")
        }
    }

    private func declineTextButton(label: String) -> some View {
        Button { onDecline() } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(MivoPressStyle())
    }
}
