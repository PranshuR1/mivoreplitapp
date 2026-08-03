import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum MivoRulesDocument {
    static var localURL: URL? {
        Bundle.main.url(
            forResource: "Mivo_Referral_Campaign_Official_Rules_Draft",
            withExtension: "pdf"
        )
    }
}

struct MivoPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(MivoColors.background)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

struct CampaignRulesView: View {
    let campaign: ReferralCampaign?
    @Environment(\.dismiss) private var dismiss
    @State private var documentURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let documentURL {
                    MivoPDFView(url: documentURL)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Rules unavailable",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Loading campaign rules...")
                }
            }
            .background(MivoColors.background)
            .navigationTitle(campaign?.hasPublishedFinalRules == true ? "Campaign Rules" : "Campaign Rules - Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if let documentURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: documentURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share campaign rules")
                    }
                }
            }
        }
        .task { await loadDocument() }
    }

    private func loadDocument() async {
        if let remote = campaign?.rulesPdfUrl, !remote.isEmpty {
            do {
                documentURL = try await ReferralCampaignService.downloadRules(remotePath: remote)
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if let local = MivoRulesDocument.localURL {
            documentURL = local
            errorMessage = nil
        } else if errorMessage == nil {
            errorMessage = "The bundled draft rules could not be found."
        }
    }
}

struct ReferralHomeCard: View {
    let summary: ReferralSummary?
    let isLoading: Bool
    let openHub: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.white)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Referral")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                Button(action: openHub) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open referral hub")
            }

            if isLoading && summary == nil {
                ProgressView()
                    .tint(MivoColors.accent)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else if let summary {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR CODE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(MivoColors.textMuted)
                        Text(summary.referralCode)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = summary.referralCode
                        copied = true
                        HapticsService.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(MivoColors.blue)
                            .frame(width: 38, height: 38)
                            .background(MivoColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: shareText(summary)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(MivoColors.white)
                            .frame(width: 38, height: 38)
                            .background(MivoColors.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                HStack(spacing: 8) {
                    referralStat("Qualified", value: "\(summary.qualifiedCount)")
                    referralStat("Pending", value: "\(summary.pendingCount)")
                    referralStat("Next", value: summary.referralsRemaining.map { "\($0) left" } ?? "Complete")
                }

                if let target = summary.nextMilestone {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Next milestone")
                            Spacer()
                            Text("\(summary.qualifiedCount) / \(target)")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MivoColors.textSecondary)
                        ProgressView(value: Double(min(summary.qualifiedCount, target)), total: Double(max(1, target)))
                            .tint(MivoColors.blue)
                    }
                }

                if let campaign = summary.campaign {
                    HStack {
                        Label("Cash prizes", systemImage: "trophy.fill")
                        Spacer()
                        Text("$\(campaign.firstPrizeCents / 100) · $\(campaign.secondPrizeCents / 100) · $\(campaign.thirdPrizeCents / 100)")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)
                    .padding(10)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                Text("Your unique code will appear when the campaign database is connected.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .mivoSectionSurface()
    }

    private var statusText: String {
        guard let campaign = summary?.campaign else { return "Campaign setup in progress" }
        switch campaign.status {
        case "active": return "\(summary?.qualifiedCount ?? 0) qualified - campaign active"
        case "paused": return "Campaign temporarily paused"
        case "ended": return "Final campaign results"
        default: return "Campaign coming soon"
        }
    }

    private func referralStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct ReferralHubView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary: ReferralSummary?
    @State private var isLoading = true
    @State private var message: String?
    @State private var showRules = false
    @State private var copiedValue: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let summary {
                            codePanel(summary)
                            progressPanel(summary)
                            campaignPanel(summary)
                            peoplePanel(summary)
                        } else if isLoading {
                            ProgressView("Loading your referral hub...")
                                .padding(.top, 100)
                        } else {
                            ContentUnavailableView(
                                "Referral hub unavailable",
                                systemImage: "person.2.slash",
                                description: Text(message ?? "Try again in a moment.")
                            )
                            Button("Try Again") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                                .tint(MivoColors.accent)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Referral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRules = true } label: {
                        Label("Rules", systemImage: "doc.text")
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRules) {
            CampaignRulesView(campaign: summary?.campaign)
        }
        .alert("Referral", isPresented: Binding(
            get: { message != nil && summary != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func codePanel(_ summary: ReferralSummary) -> some View {
        VStack(spacing: 14) {
            Text("Your unique code")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
            Text(summary.referralCode)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            HStack(spacing: 10) {
                hubAction("Copy code", icon: copiedValue == "code" ? "checkmark" : "doc.on.doc") {
                    copy(summary.referralCode, marker: "code")
                }
                hubAction("Copy link", icon: copiedValue == "link" ? "checkmark" : "link") {
                    copy(referralLink(summary), marker: "link")
                }
                ShareLink(item: shareText(summary)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1))
    }

    private func progressPanel(_ summary: ReferralSummary) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Campaign progress")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if let rank = summary.privateRank {
                    Text("Private rank #\(rank)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.blue)
                }
            }
            HStack(spacing: 10) {
                metric("Qualified", "\(summary.qualifiedCount)")
                metric("Pending", "\(summary.pendingCount)")
                metric("Next milestone", summary.nextMilestone.map(String.init) ?? "Done")
            }
            if let next = summary.nextMilestone {
                ProgressView(value: Double(summary.qualifiedCount), total: Double(max(next, 1)))
                    .tint(MivoColors.accent)
                Text("\(max(0, next - summary.qualifiedCount)) more qualified referrals to reach \(next)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .padding(16)
        .background(MivoColors.surfaceRaised.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func campaignPanel(_ summary: ReferralSummary) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(summary.campaign?.name ?? "Mivo Referral Campaign")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(summary.campaign?.description ?? "Campaign dates and final rules are being prepared.")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
            HStack(spacing: 8) {
                prize("1st", cents: summary.campaign?.firstPrizeCents ?? 15000)
                prize("2nd", cents: summary.campaign?.secondPrizeCents ?? 10000)
                prize("3rd", cents: summary.campaign?.thirdPrizeCents ?? 5000)
            }
            Button { showRules = true } label: {
                Label("Read campaign rules", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.blue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func peoplePanel(_ summary: ReferralSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who used your code")
                .font(.system(size: 17, weight: .bold))
                .padding(.bottom, 12)
            if summary.referredUsers.isEmpty {
                Text("No one has used your code yet. Share it when the campaign is active.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(summary.referredUsers.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(MivoColors.border.opacity(0.6)) }
                    HStack(spacing: 12) {
                        Text(String(person.firstName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(MivoColors.background)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.firstName)
                                .font(.system(size: 14, weight: .semibold))
                            Text(shortDate(person.date))
                                .font(.system(size: 11))
                                .foregroundColor(MivoColors.textMuted)
                        }
                        Spacer()
                        Text(person.status.capitalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(person.status == "qualified" ? MivoColors.blue : MivoColors.textSecondary)
                    }
                    .padding(.vertical, 11)
                }
            }
        }
        .padding(16)
        .background(MivoColors.surfaceRaised.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hubAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 19, weight: .bold))
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prize(_ place: String, cents: Int) -> some View {
        VStack(spacing: 3) {
            Text(place).font(.system(size: 10, weight: .semibold)).foregroundColor(MivoColors.textMuted)
            Text("$\(cents / 100)").font(.system(size: 17, weight: .bold)).foregroundColor(MivoColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MivoColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copy(_ value: String, marker: String) {
        UIPasteboard.general.string = value
        copiedValue = marker
        HapticsService.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedValue = nil }
    }

    private func load() async {
        isLoading = true
        do {
            summary = try await appVM.loadReferralSummary()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }
}

struct OnboardingReferralCodeView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var code = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var goNext = false
    @State private var showRules = false
    @State private var appear = false
    @State private var checkingCampaign = true

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            if checkingCampaign {
                ProgressView()
                    .tint(MivoColors.accent)
                    .accessibilityLabel("Checking referral campaign")
            } else {
                VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 1,
                            total: 12,
                            eyebrow: "Referral",
                            title: "Did someone invite you?",
                            subtitle: "Enter their Mivo code. You can skip this if you do not have one."
                        )
                        .onboardingEntrance(appear)

                        VStack(alignment: .leading, spacing: 9) {
                            Text("REFERRAL CODE")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(MivoColors.textSecondary)
                            TextField("MIVO-XXXXXX", text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.textPrimary)
                                .padding(.horizontal, 16)
                                .frame(height: 58)
                                .background(MivoColors.white.opacity(0.62))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
                                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
                                .onChange(of: code) { _, value in
                                    code = String(value.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(11))
                                    errorMessage = nil
                                }
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MivoColors.timerRed)
                            }
                        }
                        .onboardingEntrance(appear, delay: 0.08)

                        Button { showRules = true } label: {
                            Label("Campaign Rules - Draft", systemImage: "doc.text")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.blue)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 130)
                }

                OnboardingBottomBar {
                    VStack(spacing: 10) {
                        OnboardingPrimaryButton(code.isEmpty ? "Skip" : (loading ? "Checking code..." : "Use this code")) {
                            Image(systemName: code.isEmpty ? "arrow.right" : "checkmark")
                        } action: { Task { await continueTapped() } }
                        .disabled(loading)

                        if !code.isEmpty {
                            Button("Continue without a code") { goNext = true }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                    }
                }
            }
            }
        }
        .navigationDestination(isPresented: $goNext) { OnboardingWhyView() }
        .sheet(isPresented: $showRules) { CampaignRulesView(campaign: nil) }
        .onboardingNavigationChromeHidden()
        .background(DisableBackSwipe())
        .onAppear {
            code = appVM.onboardingProfile.referralCode ?? UserDefaults.standard.string(forKey: "mivo.prefilledReferralCode") ?? ""
            appear = true
        }
        .task { await checkCampaignAvailability() }
    }

    private func checkCampaignAvailability() async {
        do {
            let summary = try await appVM.loadReferralSummary()
            if summary.campaign == nil {
                goNext = true
                return
            }
        } catch {
            // Do not expose campaign UI when its publication state cannot be verified.
            goNext = true
            return
        }
        checkingCampaign = false
    }

    private func continueTapped() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { goNext = true; return }
        loading = true

        if appVM.onboardingReplayActive {
            var profile = OnboardingProfile()
            profile.referralCode = trimmed
            appVM.saveOnboardingProfile(profile)
            HapticsService.success()
            goNext = true
            loading = false
            return
        }

        do {
            try await appVM.attachReferralCode(trimmed)
            var profile = OnboardingProfile()
            profile.referralCode = trimmed
            appVM.saveOnboardingProfile(profile)
            UserDefaults.standard.removeObject(forKey: "mivo.prefilledReferralCode")
            HapticsService.success()
            goNext = true
        } catch {
            errorMessage = error.localizedDescription
            HapticsService.error()
        }
        loading = false
    }
}

struct RegistrationAgeGateView: View {
    @Binding var isCleared: Bool
    let previewMode: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var checkedAge: Int?
    @State private var parentEmail = ""
    @State private var ticket: ParentalConsentTicket?
    @State private var status: ParentalConsentStatus?
    @State private var loading = false
    @State private var message: String?
    @State private var showRules = false

    init(isCleared: Binding<Bool>, previewMode: Bool = false) {
        _isCleared = isCleared
        self.previewMode = previewMode
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MivoColors.textSecondary)
                                .frame(width: 40, height: 40)
                        }
                        Spacer()
                        MivoLogo(size: 42)
                    }

                    Text("Before creating an account")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Enter the month and year of birth. Mivo asks neutrally so it can apply the correct privacy protections before collecting account information.")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)

                    DatePicker(
                        "Month and year of birth",
                        selection: $birthDate,
                        in: Calendar.current.date(from: DateComponents(year: 1900, month: 1))!...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let checkedAge, checkedAge < 13 {
                        parentConsentPanel
                    } else {
                        Button {
                            evaluateAge()
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showRules = true } label: {
                        Label("Referral Campaign Rules - Draft", systemImage: "doc.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.blue)
                    }
                }
                .padding(24)
                .padding(.bottom, 30)
            }
            if loading { MivoLoadingOverlay(message: "Checking parent consent...") }
        }
        .sheet(isPresented: $showRules) { CampaignRulesView(campaign: nil) }
        .alert("Parent consent", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        .task {
            guard !previewMode else { return }
            if let saved = ParentalConsentTicketStore.load() {
                ticket = saved
                await refreshStatus()
            }
        }
    }

    private var parentConsentPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("A parent must approve this account", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text("Mivo will collect only the parent's email to begin manual verification. No account, Screen Time, referral, or behavioral data is created until approval.")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)

            if ticket == nil {
                TextField("Parent or guardian email", text: $parentEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MivoColors.border, lineWidth: 1))
                Button { Task { await requestConsent() } } label: {
                    Text("Send parent consent request")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(parentEmail.contains("@") ? MivoColors.blue : MivoColors.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!parentEmail.contains("@"))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Status: \((status?.status ?? ticket?.status ?? "pending").replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.system(size: 14, weight: .bold))
                        Text(status?.reviewerNote ?? "Mivo will contact the parent with secure instructions for the signed form and identity review.")
                            .font(.system(size: 12))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                    Spacer()
                    Button { Task { await refreshStatus() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 38, height: 38)
                    }
                }
                if status?.status == "approved" {
                    Button("Continue to create account") {
                        isCleared = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MivoColors.accent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1))
    }

    private func evaluateAge() {
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        checkedAge = years
        if years >= 13 { isCleared = true }
    }

    private func requestConsent() async {
        if previewMode {
            message = "Founder preview only. No parent consent email was sent."
            return
        }
        loading = true
        let components = Calendar.current.dateComponents([.month, .year], from: birthDate)
        do {
            let created = try await ReferralCampaignService.createParentalConsentRequest(
                parentEmail: parentEmail,
                birthMonth: components.month ?? 1,
                birthYear: components.year ?? 2000
            )
            ticket = created
            ParentalConsentTicketStore.save(created)
            status = ParentalConsentStatus(status: created.status, reviewerNote: nil, expiresAt: nil)
            message = "Request created. Mivo will contact the parent at \(parentEmail) with secure manual-verification instructions."
        } catch { message = error.localizedDescription }
        loading = false
    }

    private func refreshStatus() async {
        guard let ticket else { return }
        loading = true
        do {
            status = try await ReferralCampaignService.parentalConsentStatus(ticket: ticket)
            if status?.status == "approved" { HapticsService.success() }
        } catch { message = error.localizedDescription }
        loading = false
    }
}

struct ReferralAdminView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var dashboard: AdminReferralDashboard?
    @State private var campaign: ReferralCampaign?
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var milestonesText = "1, 3, 5, 10, 20"
    @State private var isLoading = true
    @State private var message: String?
    @State private var showRules = false
    @State private var showFinalRulesImporter = false
    @State private var legalReviewConfirmed = false
    @State private var finalRulesVersion = "1.0"

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    campaignHistorySection
                    if let campaign {
                        campaignEditor(campaign)
                    }
                    standingsSection
                    consentSection
                    usersSection
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            if isLoading { MivoLoadingOverlay(message: "Loading campaign controls...") }
        }
        .navigationTitle("Referral Campaign")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRules) { CampaignRulesView(campaign: campaign) }
        .fileImporter(
            isPresented: $showFinalRulesImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await publishFinalRules(from: url) }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Campaign", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func campaignEditor(_ current: ReferralCampaign) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            adminHeader("Campaign settings", icon: "calendar.badge.clock")
            TextField("Campaign name", text: Binding(
                get: { campaign?.name ?? "" }, set: { campaign?.name = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            TextField("Description", text: Binding(
                get: { campaign?.description ?? "" }, set: { campaign?.description = $0 }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)

            DatePicker("Starts", selection: $startDate)
            DatePicker("Ends", selection: $endDate)

            HStack {
                Text("Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Text(current.status.capitalized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(current.status == "active" ? MivoColors.blue : MivoColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 10) {
                moneyField("1st", cents: Binding(get: { campaign?.firstPrizeCents ?? 15000 }, set: { campaign?.firstPrizeCents = $0 }))
                moneyField("2nd", cents: Binding(get: { campaign?.secondPrizeCents ?? 10000 }, set: { campaign?.secondPrizeCents = $0 }))
                moneyField("3rd", cents: Binding(get: { campaign?.thirdPrizeCents ?? 5000 }, set: { campaign?.thirdPrizeCents = $0 }))
            }

            VStack(alignment: .leading, spacing: 9) {
                TextField("Final rules version", text: $finalRulesVersion)
                    .textFieldStyle(.roundedBorder)
                Toggle("Legal review completed", isOn: $legalReviewConfirmed)
                    .tint(MivoColors.accent)
                Button {
                    showFinalRulesImporter = true
                } label: {
                    Label("Publish reviewed final PDF", systemImage: "checkmark.seal")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(MivoColors.accent)
                .disabled(!legalReviewConfirmed || finalRulesVersion.isEmpty)
            }
            .padding(12)
            .background(MivoColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                Text("Milestones").font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
                TextField("1, 3, 5, 10, 20", text: $milestonesText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Button { showRules = true } label: {
                    Label("Preview rules", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MivoColors.blue)

                Button { Task { await uploadDraftRules() } } label: {
                    Label("Upload draft", systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MivoColors.blue)
            }

            Button { Task { await saveCampaign() } } label: {
                Text(current.status == "draft" ? "Save campaign draft" : "Save campaign")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            campaignStateActions(current)

            if current.status == "draft" && !current.hasPublishedFinalRules {
                Label("Activation stays locked until a final dated, legally reviewed rules PDF replaces this draft.", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .adminPanelStyle()
    }

    private var campaignHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            adminHeader("Campaign history", icon: "clock.arrow.circlepath")
            if let campaigns = dashboard?.campaigns, !campaigns.isEmpty {
                Menu {
                    ForEach(campaigns) { item in
                        Button {
                            selectCampaign(item)
                        } label: {
                            Label(item.name, systemImage: item.id == campaign?.id ? "checkmark" : "calendar")
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(campaign?.name ?? "Choose campaign")
                                .font(.system(size: 14, weight: .bold))
                            Text(campaign?.status.capitalized ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(12)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else if !isLoading {
                Button { Task { await createNewCampaign() } } label: {
                    Label("Create Campaign", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(MivoColors.blue)
            }
        }
        .adminPanelStyle()
    }

    @ViewBuilder
    private func campaignStateActions(_ current: ReferralCampaign) -> some View {
        if current.status == "draft" {
            Button { Task { await startCampaign() } } label: {
                Label("Start Campaign", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(MivoColors.blue)
            .disabled(!current.hasPublishedFinalRules || endDate <= startDate)
        } else if current.status == "active" {
            HStack {
                Button("Pause Campaign") { Task { await setCampaignStatus("paused") } }
                    .buttonStyle(.bordered)
                Button("End Campaign", role: .destructive) { Task { await setCampaignStatus("ended") } }
                    .buttonStyle(.bordered)
            }
        } else if current.status == "paused" {
            HStack {
                Button("Resume Campaign") { Task { await setCampaignStatus("active") } }
                    .buttonStyle(.borderedProminent)
                    .tint(MivoColors.blue)
                Button("End Campaign", role: .destructive) { Task { await setCampaignStatus("ended") } }
                    .buttonStyle(.bordered)
            }
        } else if current.status == "ended" {
            Button { Task { await createNewCampaign() } } label: {
                Label("Create New Campaign", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(MivoColors.blue)
        }
    }

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            adminHeader("Private standings", icon: "trophy")
            let standings = (dashboard?.standings ?? []).filter { $0.campaignId == campaign?.id }
            if standings.isEmpty {
                Text("No qualified referrals yet.").font(.system(size: 13)).foregroundColor(MivoColors.textSecondary)
            } else {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 10) {
                        Text("#\(index + 1)").font(.system(size: 14, weight: .black)).foregroundColor(MivoColors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(standing.name).font(.system(size: 14, weight: .bold))
                            Text(standing.referralCode ?? standing.email ?? "")
                                .font(.system(size: 11)).foregroundColor(MivoColors.textMuted)
                        }
                        Spacer()
                        Text("\(standing.qualifiedCount) qualified")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.blue)
                    }
                }
            }
        }
        .adminPanelStyle()
    }

    private var consentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            adminHeader("Parent consent review", icon: "person.crop.circle.badge.checkmark")
            if dashboard?.consentRequests.isEmpty != false {
                Text("No parent consent requests.").font(.system(size: 13)).foregroundColor(MivoColors.textSecondary)
            } else {
                ForEach(dashboard?.consentRequests ?? []) { request in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.parentEmail).font(.system(size: 13, weight: .bold))
                                Text("Birth: \(request.birthMonth)/\(request.birthYear) - \(request.status.capitalized)")
                                    .font(.system(size: 11)).foregroundColor(MivoColors.textMuted)
                            }
                            Spacer()
                            if request.status == "pending" || request.status == "needs_information" {
                                Button("Approve") { Task { await review(request, status: "approved") } }
                                    .font(.system(size: 11, weight: .bold)).tint(MivoColors.blue)
                                Button("Reject") { Task { await review(request, status: "rejected") } }
                                    .font(.system(size: 11, weight: .bold)).tint(.red)
                            }
                        }
                        if request.evidenceStoragePath == nil && request.status == "pending" {
                            Text("Waiting for signed consent and identity evidence.")
                                .font(.system(size: 10)).foregroundColor(MivoColors.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .adminPanelStyle()
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            adminHeader("User progress", icon: "person.3")
            ForEach(dashboard?.users ?? []) { user in
                NavigationLink {
                    AdminUserProgressView(user: user)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.name).font(.system(size: 14, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                            Text(user.email).font(.system(size: 11)).foregroundColor(MivoColors.textMuted)
                            Text("\(user.sessionCount) sessions - \(user.totalMinutes)m - \(user.reflectionCount) reflections")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(MivoColors.textMuted)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .adminPanelStyle()
    }

    private func moneyField(_ title: String, cents: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
            TextField("0", value: Binding(
                get: { cents.wrappedValue / 100 }, set: { cents.wrappedValue = max(0, $0 * 100) }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func adminHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(MivoColors.textPrimary)
    }

    private func load() async {
        isLoading = true
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            await appVM.refreshServerAdminRole()
            guard appVM.isSuperAdminUser else { throw ReferralCampaignError.server("super_admin_required") }
            let loaded = try await ReferralCampaignService.loadAdminDashboard()
            dashboard = loaded
            let selectedID = campaign?.id
            campaign = loaded.campaigns.first(where: { $0.id == selectedID }) ?? loaded.campaigns.first
            if let campaign {
                startDate = campaign.startsAt.flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
                endDate = campaign.endsAt.flatMap(ISO8601DateFormatter().date(from:))
                    ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
            }
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func selectCampaign(_ selected: ReferralCampaign) {
        campaign = selected
        startDate = selected.startsAt.flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        endDate = selected.endsAt.flatMap(ISO8601DateFormatter().date(from:))
            ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        legalReviewConfirmed = false
        finalRulesVersion = "1.0"
    }

    private func createNewCampaign() async {
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            let created = try await ReferralCampaignService.createCampaign()
            campaign = created
            startDate = Date()
            endDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
            milestonesText = "1, 3, 5, 10, 20"
            legalReviewConfirmed = false
            finalRulesVersion = "1.0"
            message = "A new campaign draft was created. Previous campaign results remain in history."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func saveCampaign() async {
        guard var campaign else { return }
        guard endDate > startDate else { message = "The end date must be after the start date."; return }
        let milestones = milestonesText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if campaign.status == "draft" { campaign.status = "draft" }
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            self.campaign = try await ReferralCampaignService.updateCampaign(
                campaign, startsAt: startDate, endsAt: endDate, milestones: milestones
            )
            message = "Campaign settings were saved to Supabase."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func startCampaign() async {
        guard var campaign else { return }
        guard campaign.hasPublishedFinalRules else {
            message = "Publish the final legally reviewed rules before starting the campaign."
            return
        }
        guard endDate > startDate else {
            message = "The end date must be after the start date."
            return
        }
        let milestones = milestonesText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            campaign.status = "draft"
            let saved = try await ReferralCampaignService.updateCampaign(
                campaign, startsAt: startDate, endsAt: endDate, milestones: milestones
            )
            var active = saved
            active.status = "active"
            self.campaign = try await ReferralCampaignService.updateCampaign(
                active, startsAt: startDate, endsAt: endDate, milestones: milestones
            )
            message = "Campaign started. Referrals become available at the configured start date."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func setCampaignStatus(_ status: String) async {
        guard var campaign else { return }
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            campaign.status = status
            let milestones = milestonesText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            self.campaign = try await ReferralCampaignService.updateCampaign(
                campaign, startsAt: startDate, endsAt: endDate, milestones: milestones
            )
            message = status == "active" ? "Campaign resumed." : status == "paused" ? "Campaign paused." : "Campaign ended."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func uploadDraftRules() async {
        guard let campaign, let url = MivoRulesDocument.localURL else {
            message = "The bundled draft rules are missing."
            return
        }
        do {
            _ = try await ReferralCampaignService.uploadDraftRules(campaignID: campaign.id, fileURL: url)
            message = "Draft rules uploaded. The campaign remains locked until a final reviewed version is published."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func publishFinalRules(from url: URL) async {
        guard let campaign else { return }
        guard legalReviewConfirmed else {
            message = "Confirm legal review before publishing final rules."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try await ReferralCampaignService.publishFinalRules(
                campaignID: campaign.id,
                fileURL: url,
                version: finalRulesVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            message = "Final rules v\(finalRulesVersion) were published and version-locked. You can now activate the campaign after saving valid dates."
            legalReviewConfirmed = false
            await load()
        } catch { message = error.localizedDescription }
    }

    private func review(_ request: ParentalConsentRequest, status: String) async {
        do {
            try await ReferralCampaignService.reviewConsent(id: request.id, status: status, note: "Reviewed in Mivo super-admin settings")
            await load()
        } catch { message = error.localizedDescription }
    }
}

struct AdminUserProgressView: View {
    let user: AdminCampaignUser
    @State private var detail: AdminUserDetail?
    @State private var timeline: [AdminTimelineEvent] = []
    @State private var selectedSession: AdminSessionRecord?
    @State private var message: String?
    @State private var showReset = false
    @State private var showDelete = false

    var body: some View {
        List {
            Section("Progress") {
                LabeledContent("Sessions", value: "\(user.sessionCount)")
                LabeledContent("Total time", value: "\(user.totalMinutes) min")
                LabeledContent("Reflections", value: "\(user.reflectionCount)")
                LabeledContent("Onboarding", value: user.onboardingComplete ? "Complete" : "Incomplete")
            }
            Section("Sanitized timeline") {
                if timeline.isEmpty {
                    Text("No account activity is available yet.").foregroundColor(.secondary)
                } else {
                    ForEach(timeline.prefix(40)) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: timelineIcon(event.type))
                                .foregroundColor(MivoColors.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(event.status.capitalized) · \(timelineDate(event.at))")
                                    .font(.caption).foregroundColor(.secondary)
                                if let minutes = event.durationMinutes {
                                    Text("\(minutes) minutes").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("This timeline excludes app identities, intentions, triggers, reflection text, and session notes.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Section("Sessions") {
                if let sessions = detail?.sessions, !sessions.isEmpty {
                    ForEach(sessions) { session in
                        Button { selectedSession = session } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.date).font(.headline)
                                Text("\(session.actualDuration)m actual / \(session.plannedDuration)m planned")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No sessions saved.").foregroundColor(.secondary)
                }
            }
            Section("Administrative actions") {
                Button("Reset all progress", role: .destructive) { showReset = true }
                Button("Delete account", role: .destructive) { showDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MivoColors.background)
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selectedSession) { session in
            AdminSessionEditor(userID: user.userId, session: session) {
                await load()
            }
        }
        .alert("Reset all progress?", isPresented: $showReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Task { await reset() } }
        } message: { Text("This keeps the account but clears sessions, reports, schedules, and onboarding completion. The action is audited.") }
        .alert("Delete account?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: { Text("This permanently removes the Supabase Auth account and associated data. The action is audited.") }
        .alert("Admin action", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func load() async {
        do {
            async let loadedDetail = ReferralCampaignService.loadAdminUserDetail(userID: user.userId)
            async let loadedTimeline = ProductExpansionService.adminUserTimeline(userID: user.userId)
            detail = try await loadedDetail
            timeline = (try? await loadedTimeline) ?? []
        }
        catch { message = error.localizedDescription }
    }

    private func timelineIcon(_ type: String) -> String {
        switch type {
        case "account_created": return "person.crop.circle.badge.checkmark"
        case "onboarding": return "checklist"
        case "session": return "timer"
        case "experiment": return "flask"
        case "support": return "bubble.left.and.exclamationmark.bubble.right"
        default: return "waveform.path.ecg"
        }
    }

    private func timelineDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func reset() async {
        do {
            try await ReferralCampaignService.resetUserProgress(userID: user.userId, reason: "Reset from Mivo super-admin settings")
            message = "Progress reset completed."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func delete() async {
        do {
            try await ReferralCampaignService.deleteUser(userID: user.userId, reason: "Deleted from Mivo super-admin settings")
            message = "Account deleted."
        } catch { message = error.localizedDescription }
    }
}

struct AdminSessionEditor: View {
    let userID: String
    let session: AdminSessionRecord
    let didSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var planned: Int
    @State private var actual: Int
    @State private var reflection: String
    @State private var note: String
    @State private var reason = "Corrected by Mivo super-admin"
    @State private var message: String?

    init(userID: String, session: AdminSessionRecord, didSave: @escaping () async -> Void) {
        self.userID = userID
        self.session = session
        self.didSave = didSave
        _planned = State(initialValue: session.plannedDuration)
        _actual = State(initialValue: session.actualDuration)
        _reflection = State(initialValue: session.reflection ?? "")
        _note = State(initialValue: session.reflectionNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Planned: \(planned) min", value: $planned, in: 0...1440)
                Stepper("Actual: \(actual) min", value: $actual, in: 0...1440)
                Picker("Reflection", selection: $reflection) {
                    Text("None").tag("")
                    Text("Yes").tag("Yes")
                    Text("Kind of").tag("Kind of")
                    Text("No").tag("No")
                }
                TextField("Reflection note", text: $note, axis: .vertical)
                TextField("Audit reason", text: $reason, axis: .vertical)
            }
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(reason.isEmpty) }
            }
            .alert("Session", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }

    private func save() async {
        var updated = session
        updated.plannedDuration = planned
        updated.actualDuration = actual
        updated.reflection = reflection.isEmpty ? nil : reflection
        updated.reflectionNote = note
        do {
            try await ReferralCampaignService.updateSession(userID: userID, session: updated, reason: reason)
            await didSave()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct AnnouncementAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @State private var announcements: [MivoAnnouncement] = []
    @State private var title = ""
    @State private var bodyText = ""
    @State private var publishNow = true
    @State private var hasExpiration = false
    @State private var expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isLoading = true
    @State private var message: String?
    @State private var editingAnnouncement: MivoAnnouncement?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) { composer; history }
                    .padding(16).padding(.bottom, 30)
            }
            if isLoading { MivoLoadingOverlay(message: "Loading announcements...") }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: appVM.canManageAnnouncements) { _, allowed in
            if !allowed { dismiss() }
        }
        .alert("Announcements", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(editingAnnouncement == nil ? "New announcement" : "Edit draft", systemImage: "megaphone.fill")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if editingAnnouncement != nil {
                    Button("Cancel edit") { resetComposer() }
                        .font(.system(size: 12, weight: .bold))
                }
            }
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Message for all Mivo users", text: $bodyText, axis: .vertical)
                .lineLimit(4...8).textFieldStyle(.roundedBorder)
            if appVM.isSuperAdminUser && editingAnnouncement == nil {
                Toggle("Publish immediately", isOn: $publishNow).tint(MivoColors.accent)
            } else if !appVM.isSuperAdminUser {
                Label("Saved as a draft for founder approval", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Toggle("Set expiration", isOn: $hasExpiration).tint(MivoColors.accent)
            if hasExpiration { DatePicker("Expires", selection: $expiration, in: Date()...) }
            Button { Task { await saveAnnouncement() } } label: {
                let willPublish = appVM.isSuperAdminUser && publishNow && editingAnnouncement == nil
                Label(
                    editingAnnouncement == nil ? (willPublish ? "Publish to Everyone" : "Save Draft") : "Update Draft",
                    systemImage: willPublish ? "paperplane.fill" : "doc.fill"
                )
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent).tint(MivoColors.accent)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .adminPanelStyle()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.system(size: 17, weight: .bold)).padding(.bottom, 12)
            if announcements.isEmpty {
                Text("No announcements yet.").font(.system(size: 13)).foregroundColor(MivoColors.textSecondary).padding(.vertical, 12)
            } else {
                ForEach(Array(announcements.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(MivoColors.border) }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(item.title).font(.system(size: 14, weight: .bold))
                            Spacer()
                            Text(item.status.capitalized)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(item.status == "published" ? MivoColors.blue : MivoColors.textMuted)
                        }
                        Text(item.body).font(.system(size: 12)).foregroundColor(MivoColors.textSecondary).lineLimit(3)
                        if item.status == "draft" {
                            HStack(spacing: 16) {
                                Button("Edit") { beginEditing(item) }
                                    .font(.system(size: 12, weight: .bold))
                                if appVM.isSuperAdminUser {
                                    Button("Publish") { Task { await changeStatus(item, to: "published") } }
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                        } else if item.status == "published" {
                            if appVM.isSuperAdminUser {
                                Button("Archive", role: .destructive) { Task { await changeStatus(item, to: "archived") } }
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }.padding(.vertical, 12)
                }
            }
        }.adminPanelStyle()
    }

    private func load() async {
        isLoading = true
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            announcements = try await ReferralCampaignService.adminAnnouncements()
        } catch { message = error.localizedDescription }
        isLoading = false
    }

    private func saveAnnouncement() async {
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editingAnnouncement {
                _ = try await ReferralCampaignService.updateAnnouncementDraft(
                    id: editingAnnouncement.id,
                    title: cleanTitle,
                    body: cleanBody,
                    expiresAt: hasExpiration ? expiration : nil
                )
                message = "Announcement draft updated."
            } else {
                let willPublish = appVM.isSuperAdminUser && publishNow
                _ = try await ReferralCampaignService.createAnnouncement(
                    title: cleanTitle,
                    body: cleanBody,
                    expiresAt: hasExpiration ? expiration : nil,
                    publishNow: willPublish
                )
                message = willPublish ? "Announcement published to Mivo users." : "Announcement draft saved for founder approval."
            }
            resetComposer()
            await load()
        } catch { message = error.localizedDescription }
    }

    private func beginEditing(_ announcement: MivoAnnouncement) {
        editingAnnouncement = announcement
        title = announcement.title
        bodyText = announcement.body
        if let rawDate = announcement.expiresAt,
           let date = ISO8601DateFormatter().date(from: rawDate) {
            hasExpiration = true
            expiration = date
        } else {
            hasExpiration = false
        }
    }

    private func resetComposer() {
        editingAnnouncement = nil
        title = ""
        bodyText = ""
        publishNow = true
        hasExpiration = false
        expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private func changeStatus(_ announcement: MivoAnnouncement, to status: String) async {
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            try await ReferralCampaignService.setAnnouncementStatus(id: announcement.id, status: status)
            await load()
        } catch { message = error.localizedDescription }
    }
}

struct AmbassadorDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @State private var dashboard: AmbassadorDashboard?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let dashboard {
                        HStack(spacing: 8) {
                            ambassadorStat("Total", dashboard.totalCount)
                            ambassadorStat("Complete", dashboard.completedCount)
                            ambassadorStat("Pending", dashboard.pendingCount)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("People attributed to you")
                                .font(.system(size: 17, weight: .bold))
                                .padding(.bottom, 10)
                            if dashboard.people.isEmpty {
                                Text("No one has been assigned to your ambassador names yet.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .padding(.vertical, 18)
                            } else {
                                ForEach(Array(dashboard.people.enumerated()), id: \.element.id) { index, person in
                                    if index > 0 { Divider().overlay(MivoColors.border) }
                                    HStack(spacing: 12) {
                                        Text(String(person.firstName.prefix(1)).uppercased())
                                            .font(.system(size: 15, weight: .bold))
                                            .frame(width: 36, height: 36)
                                            .background(MivoColors.background)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(person.firstName)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(MivoColors.textPrimary)
                                            Text(ambassadorPersonSubtitle(person))
                                                .font(.system(size: 11))
                                                .foregroundColor(MivoColors.textSecondary)
                                        }
                                        Spacer()
                                        Text(person.onboardingComplete ? "Complete" : "Pending")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(person.onboardingComplete ? MivoColors.blue : MivoColors.accent)
                                    }
                                    .padding(.vertical, 11)
                                }
                            }
                        }
                        .adminPanelStyle()
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Ambassador dashboard unavailable",
                            systemImage: "person.2.slash",
                            description: Text(errorMessage)
                        )
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(MivoColors.accent)
                    }
                }
                .padding(16)
            }
            if isLoading { MivoLoadingOverlay(message: "Loading your referrals...") }
        }
        .navigationTitle("Ambassador")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: appVM.isAmbassadorUser) { _, allowed in
            if !allowed { dismiss() }
        }
    }

    private func ambassadorStat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.7)))
    }

    private func ambassadorPersonSubtitle(_ person: AmbassadorPerson) -> String {
        var pieces = [person.referralStatus.capitalized]
        if let joinedAt = person.joinedAt,
           let date = ISO8601DateFormatter().date(from: joinedAt) {
            pieces.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return pieces.joined(separator: " - ")
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            dashboard = try await ReferralCampaignService.loadAmbassadorDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct AmbassadorAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    let user: AdminCampaignUser
    let onSaved: () async -> Void

    @State private var options: AmbassadorAttributionOptions?
    @State private var selectedNames = Set<String>()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose every typed name or spelling that belongs to \(user.name). Future users entering the same name will match automatically.")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textSecondary)

                        if let options {
                            let allOptions = mergedOptions(options)
                            if allOptions.isEmpty {
                                ContentUnavailableView(
                                    "No ambassador names yet",
                                    systemImage: "text.magnifyingglass",
                                    description: Text("Names will appear after users select Ambassador during onboarding.")
                                )
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(allOptions.enumerated()), id: \.element.id) { index, option in
                                        if index > 0 { Divider().overlay(MivoColors.border) }
                                        Button {
                                            if selectedNames.contains(option.normalizedName) {
                                                selectedNames.remove(option.normalizedName)
                                            } else {
                                                selectedNames.insert(option.normalizedName)
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(option.enteredName)
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(MivoColors.textPrimary)
                                                    Text("\(option.count) signup\(option.count == 1 ? "" : "s")")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(MivoColors.textSecondary)
                                                }
                                                Spacer()
                                                Image(systemName: selectedNames.contains(option.normalizedName) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 21))
                                                    .foregroundColor(selectedNames.contains(option.normalizedName) ? MivoColors.accent : MivoColors.textMuted)
                                            }
                                            .padding(.vertical, 12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .adminPanelStyle()
                            }
                        }
                    }
                    .padding(16)
                }
                if isLoading || isSaving {
                    MivoLoadingOverlay(message: isSaving ? "Saving assignments..." : "Loading names...")
                }
            }
            .navigationTitle("Assign Ambassador Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isLoading || isSaving)
                }
            }
            .task { await load() }
            .alert("Ambassador", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }

    private func mergedOptions(_ value: AmbassadorAttributionOptions) -> [AmbassadorNameOption] {
        var byName = Dictionary(uniqueKeysWithValues: value.unassigned.map { ($0.normalizedName, $0) })
        value.assigned.forEach { byName[$0.normalizedName] = $0 }
        return byName.values.sorted {
            if $0.count == $1.count { return $0.enteredName.localizedCaseInsensitiveCompare($1.enteredName) == .orderedAscending }
            return $0.count > $1.count
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            let loaded = try await ReferralCampaignService.ambassadorAttributionOptions(userID: user.userId)
            options = loaded
            selectedNames = Set(loaded.assigned.map(\.normalizedName))
        } catch { message = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func save() async {
        isSaving = true
        do {
            try await ReferralCampaignService.setAmbassadorNames(
                userID: user.userId,
                normalizedNames: Array(selectedNames).sorted()
            )
            await onSaved()
            dismiss()
        } catch { message = error.localizedDescription }
        isSaving = false
    }
}

struct AdminPushUserDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    let userID: String
    @State private var user: AdminCampaignUser?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let user {
                AdminUserProgressView(user: user)
            } else if let errorMessage {
                ContentUnavailableView(
                    "User unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                MivoLoadingOverlay(message: "Loading new account...")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard isLoading else { return }
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            let dashboard = try await ReferralCampaignService.loadAdminDashboard()
            guard let match = dashboard.users.first(where: { $0.userId == userID }) else {
                throw ReferralCampaignError.server("user_not_found")
            }
            user = match
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private extension View {
    func adminPanelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
    }
}

private func referralLink(_ summary: ReferralSummary) -> String {
    "https://usemivo.app/r/\(summary.referralCode)"
}

private func shareText(_ summary: ReferralSummary) -> String {
    "Try Mivo and use my referral code \(summary.referralCode): \(referralLink(summary))\n\nI may win a cash prize if you join Mivo with my referral code. No purchase necessary. Rules are available in Mivo."
}

private func shortDate(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}
