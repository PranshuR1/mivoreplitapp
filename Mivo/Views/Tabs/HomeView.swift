import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var protectionEnabled = false
    @State private var reflectionText = ""
    @State private var reflectionSaved = false
    @State private var showFocus = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 12) {
                        MivoLogo(size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(greeting()), \(firstName)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                                .tracking(-0.5)
                            Text(dateLabel)
                                .font(.system(size: 13))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 20)

                    // You Have Scrolled card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You have scrolled")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                        Text(formatDuration(appVM.deviceActivityMinutesToday ?? appVM.todaysTotalMinutes))
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-2)
                        HStack {
                            Text("\(appVM.todaysSessions.count) \(appVM.todaysSessions.count == 1 ? "unlock" : "unlocks")")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                            if appVM.deviceActivityMinutesToday != nil {
                                Text("(device)")
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)
                    .padding(.bottom, 14)

                    // Mini cards row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pattern")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                            Text("\(appVM.patternPercent >= 0 ? "+" : "")\(appVM.patternPercent)% vs previous week")
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Protection")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                            Toggle("", isOn: $protectionEnabled)
                                .tint(MivoColors.accent)
                                .labelsHidden()
                            if protectionEnabled {
                                Text("Delay before apps")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(MivoColors.accent)
                                Text("Delay: 10s")
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: MivoColors.textPrimary.opacity(0.06), radius: 8, y: 2)
                    }
                    .padding(.bottom, 28)

                    // Reflection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reflection")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.3)
                        Text("One sentence is enough.")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textMuted)
                            .padding(.bottom, 4)

                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                if reflectionText.isEmpty {
                                    Text("What were you avoiding?")
                                        .font(.system(size: 15))
                                        .foregroundColor(MivoColors.textMuted)
                                        .padding(.horizontal, 18)
                                        .padding(.top, 18)
                                }
                                TextEditor(text: $reflectionText)
                                    .font(.system(size: 15))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 110)
                            }
                            Divider().background(MivoColors.border)
                            HStack {
                                Spacer()
                                if reflectionSaved {
                                    Text("Saved")
                                        .font(.system(size: 13))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                Button {
                                    saveReflection()
                                } label: {
                                    Text("Save")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(MivoColors.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(MivoColors.accent)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .background(MivoColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(MivoColors.border, lineWidth: 1)
                        )
                    }
                    .padding(.bottom, 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Enter Focus FAB
            VStack {
                Spacer()
                NavigationLink {
                    FocusView()
                } label: {
                    Text("Enter Focus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .tracking(0.3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(MivoColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: MivoColors.accent.opacity(0.3), radius: 12, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
    }

    var firstName: String {
        appVM.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: Date())
    }

    func saveReflection() {
        guard !reflectionText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        reflectionSaved = true
        reflectionText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            reflectionSaved = false
        }
    }
}
