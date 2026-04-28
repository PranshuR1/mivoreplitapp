import SwiftUI

struct TwoFactorView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let challenge: TwoFactorChallenge
    @State private var code = ""
    @State private var loading = false
    @State private var message = ""

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    MivoLogo(size: 52)
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Enter the 6-digit code sent to \(challenge.email).")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(5)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Verification code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)

                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .foregroundColor(MivoColors.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.timerRed)
                }

                Button {
                    verify()
                } label: {
                    Text(loading ? "Verifying..." : "Verify")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(MivoColors.accent)
                        .clipShape(Capsule())
                }
                .disabled(loading || code.count < 6)
                .opacity(loading || code.count < 6 ? 0.7 : 1)

                Button {
                    resend()
                } label: {
                    Text("Send a new code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.accent)
                        .frame(maxWidth: .infinity)
                }
                .disabled(loading)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 60)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
        .toolbarBackground(MivoColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var title: String {
        switch challenge.purpose {
        case .login: return "Two-factor code"
        case .registration: return "Verify account"
        case .passwordReset: return "Verify reset"
        }
    }

    private func verify() {
        loading = true
        message = ""
        do {
            try appVM.verifyTwoFactorCode(code, for: challenge)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
        loading = false
    }

    private func resend() {
        loading = true
        message = ""
        Task {
            do {
                try await appVM.resendTwoFactorCode(for: challenge)
                await MainActor.run {
                    message = "A new code was sent."
                    loading = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}
