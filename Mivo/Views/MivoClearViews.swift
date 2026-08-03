import SwiftUI
import WebKit
#if canImport(FamilyControls)
import FamilyControls
#endif

struct MivoClearHomeCard: View {
    @ObservedObject private var clearStore = MivoClearStore.shared
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 44, height: 44)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mivo Clear BETA")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Messages, profiles, and long videos without endless feeds")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                HStack(spacing: 7) {
                    Text("\(clearStore.minutesToday)m")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.textMuted)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .mivoSectionSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Mivo Clear BETA")
    }
}

struct MivoClearPatternsCard: View {
    @ObservedObject private var store = MivoClearStore.shared
    let rangeDays: Int

    init(rangeDays: Int = 7) {
        self.rangeDays = max(1, rangeDays)
    }

    private var dailySeconds: [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<rangeDays).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return store.sessions.reduce(0) { total, session in
                guard let date = ISO8601DateFormatter().date(from: session.startedAt),
                      calendar.isDate(date, inSameDayAs: day) else { return total }
                return total + session.activeSeconds
            }
        }
    }

    var body: some View {
        let values = dailySeconds
        let peak = max(1, values.max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mivo Clear BETA", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                Text("\(values.reduce(0, +) / 60)m · \(rangeDays) days")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.accent)
            }
            HStack(alignment: .bottom, spacing: rangeDays > 7 ? 3 : 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, seconds in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(seconds == 0 ? MivoColors.border.opacity(0.35) : MivoColors.accent)
                            .frame(height: max(5, 54 * CGFloat(seconds) / CGFloat(peak)))
                        if rangeDays <= 7 || index % 5 == 0 || index == values.count - 1 {
                            Text(shortDayLabel(daysAgo: values.count - 1 - index))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(MivoColors.textMuted)
                        } else {
                            Text(" ")
                                .font(.system(size: 9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
            Text("Focused social visits are shown separately so they do not distort your Screen Time truth checks.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
        }
        .mivoSectionSurface()
    }

    private func shortDayLabel(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

struct MivoClearHubView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MivoClearStore.shared
    let initialRoute: MivoClearRoute?

    @State private var selectedRoute: MivoClearRoute?
    @State private var showDisclosure = false
    @State private var showTutorial = false
    @State private var showAgeConfirmation = false
    @State private var ageBlocked = false

    init(initialRoute: MivoClearRoute? = nil) {
        self.initialRoute = initialRoute
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        ForEach(MivoClearPlatform.supportedCases) { platform in
                            platformRow(platform)
                        }
                        usageCard
                        privacyCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Mivo Clear BETA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await ProductExpansionStore.shared.prepare(for: appVM)
            await store.prepare(for: appVM)
            guard let initialRoute else { return }
            open(initialRoute)
        }
        .fullScreenCover(item: $selectedRoute) { route in
            if let platform = route.platform,
               let config = store.configuration(for: platform) {
                switch platform {
                case .youtube:
                    MivoClearBrowserView(route: route, configuration: config)
                case .tiktok:
                    MivoClearBrowserView(
                        route: defaultTikTokRouteIfNeeded(route),
                        configuration: config
                    )
                case .instagram:
                    MivoClearBrowserView(route: route, configuration: config)
                case .snapchat:
                    MivoClearUnavailableView()
                }
            } else {
                MivoClearUnavailableView()
            }
        }
        .sheet(isPresented: $showDisclosure) {
            MivoClearDisclosureView {
                store.acceptDisclosure()
                showDisclosure = false
                continueAfterDisclosure()
            }
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showTutorial) {
            MivoClearTutorialView {
                store.completeTutorial()
                showTutorial = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    continueOpening()
                }
            }
            .interactiveDismissDisabled()
        }
        .alert("Confirm age", isPresented: $showAgeConfirmation) {
            Button("I am 13 or older") {
                store.confirmAge13OrOlder()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    beginFirstUseFlow()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Social platforms require users to meet their minimum age requirements. Mivo Clear BETA is not available to users under 13.")
        }
        .alert("Mivo Clear BETA unavailable", isPresented: $ageBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mivo Clear BETA is available to users age 13 and older.")
        }
    }

    private func defaultTikTokRouteIfNeeded(_ route: MivoClearRoute) -> MivoClearRoute {
        guard route.quickActionID == nil, route.directURL == nil else { return route }
        return MivoClearRoute(
            platform: .tiktok,
            quickActionID: "profile",
            entryPoint: route.entryPoint
        )
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Useful social tools. Less automatic scrolling.", systemImage: "sparkles")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            Text("Your native social apps stay protected. Choose what you came to do and Mivo opens the focused version.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func platformRow(_ platform: MivoClearPlatform) -> some View {
        let configuration = store.configuration(for: platform)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard configuration != nil else { return }
                open(MivoClearRoute(platform: platform, entryPoint: initialRoute?.entryPoint ?? .home))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: platform.icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(configuration == nil ? MivoColors.textMuted : MivoColors.accent)
                        .frame(width: 40, height: 40)
                        .background((configuration == nil ? MivoColors.textMuted : MivoColors.accent).opacity(0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(configuration == nil ? "Temporarily unavailable" : platformDescription(platform))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    if configuration != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.heroText)
                            .frame(width: 32, height: 32)
                            .background(MivoColors.accent)
                            .clipShape(Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(configuration == nil)

            if let configuration {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(configuration.userFacingQuickActions) { action in
                            Button {
                                open(MivoClearRoute(platform: platform, quickActionID: action.id, entryPoint: initialRoute?.entryPoint ?? .home))
                            } label: {
                                Label(action.title, systemImage: action.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .padding(.horizontal, 11)
                                    .frame(height: 36)
                                    .background(MivoColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.4)))
    }

    private var usageCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(MivoColors.blue)
                .frame(width: 38, height: 38)
                .background(MivoColors.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Clear use")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("\(store.minutesToday) minutes across \(store.sessionsToday) focused visits")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer()
        }
        .padding(15)
        .background(MivoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var privacyCard: some View {
        Label {
            Text("Sign-in data stays in Apple's browser storage on this device. Mivo never reads or uploads passwords, cookies, messages, searches, or viewed content.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        } icon: {
            Image(systemName: "hand.raised.fill").foregroundColor(MivoColors.accent)
        }
        .padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func open(_ route: MivoClearRoute) {
        guard store.configuration(for: route.platform ?? .instagram) != nil else { return }
        switch store.isEligible(profile: appVM.onboardingProfile) {
        case .some(false): ageBlocked = true
        case .none: showAgeConfirmation = true; pendingRoute = route
        case .some(true):
            pendingRoute = route
            beginFirstUseFlow()
        }
    }

    @State private var pendingRoute: MivoClearRoute?

    private func continueOpening() {
        guard let pendingRoute else { return }
        self.pendingRoute = nil
        selectedRoute = pendingRoute
    }

    private func beginFirstUseFlow() {
        if !store.hasSeenDisclosure() {
            showDisclosure = true
        } else {
            continueAfterDisclosure()
        }
    }

    private func continueAfterDisclosure() {
        let needsTutorial = !store.hasCompletedTutorial()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if needsTutorial {
                showTutorial = true
            } else {
                continueOpening()
            }
        }
    }

    private func platformDescription(_ platform: MivoClearPlatform) -> String {
        switch platform {
        case .instagram: return "Messages, Stories, search, profiles, and posting"
        case .tiktok: return "Create, search, and profiles"
        case .youtube: return "Subscriptions, playlists, and videos over 3 minutes"
        case .snapchat: return "Chat, calls, camera, and friends' Stories"
        }
    }
}

#if DEBUG
struct MivoClearAppStorePreviewView: View {
    private let configurations = MivoClearDefaults.configurations.filter {
        MivoClearPlatform.supportedCases.contains($0.platform)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Useful social tools. Less automatic scrolling.", systemImage: "sparkles")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.textPrimary)
                            Text("Choose what you came to do. Mivo opens a focused version while endless short-form paths stay filtered.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MivoColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        ForEach(configurations) { configuration in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: configuration.platform.icon)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(MivoColors.accent)
                                        .frame(width: 40, height: 40)
                                        .background(MivoColors.accent.opacity(0.11))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(configuration.platform.title)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(MivoColors.textPrimary)
                                        Text(description(for: configuration.platform))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(MivoColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(MivoColors.heroText)
                                        .frame(width: 32, height: 32)
                                        .background(MivoColors.accent)
                                        .clipShape(Circle())
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(configuration.userFacingQuickActions) { action in
                                            Label(action.title, systemImage: action.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(MivoColors.textPrimary)
                                                .padding(.horizontal, 11)
                                                .frame(height: 36)
                                                .background(MivoColors.background)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .padding(15)
                            .background(MivoColors.surfaceRaised.opacity(0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.4)))
                        }

                        Label("Mivo Clear BETA never stores your social passwords, messages, searches, or viewed content.", systemImage: "hand.raised.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .padding(15)
                            .background(MivoColors.surfaceRaised.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Mivo Clear BETA")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func description(for platform: MivoClearPlatform) -> String {
        switch platform {
        case .instagram: return "Messages, search, profile, and settings without Reels or Explore"
        case .tiktok: return "Create, search, and profiles without the feed"
        case .youtube: return "Subscriptions, playlists, and longer videos"
        case .snapchat: return "Focused communication tools"
        }
    }
}
#endif

struct MivoClearSettingsView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var showHub = false
    @State private var errorMessage: String?
    @State private var mappedPlatforms: Set<MivoClearPlatform> = []
    #if canImport(FamilyControls)
    @State private var pickerPlatform: MivoClearPlatform?
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var showPicker = false
    #endif

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Map each social app once. Its native app stays protected, while the shield offers Mivo Clear BETA or a timed session.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)

                    VStack(spacing: 0) {
                        ForEach(Array(MivoClearPlatform.supportedCases.enumerated()), id: \.element.id) { index, platform in
                            mappingRow(platform)
                            if index < MivoClearPlatform.supportedCases.count - 1 {
                                Divider().overlay(MivoColors.border.opacity(0.35)).padding(.leading, 60)
                            }
                        }
                    }
                    .background(MivoColors.surfaceRaised.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.4)))

                    Button { showHub = true } label: {
                        Label("Open Mivo Clear BETA", systemImage: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(MivoColors.heroText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Label("Mappings and social sign-in sessions stay on this device. Mivo never receives your social password.", systemImage: "lock.shield.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
                .padding(20)
            }
        }
        .navigationTitle("Mivo Clear BETA")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshMappings)
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showPicker, selection: $pickerSelection)
        .onChange(of: showPicker) { _, isPresented in
            guard !isPresented, let platform = pickerPlatform else { return }
            defer {
                pickerPlatform = nil
                pickerSelection = FamilyActivitySelection()
            }
            do {
                try FamilyControlsManager.shared.saveMivoClearMapping(pickerSelection, for: platform)
                FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
                refreshMappings()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif
        .fullScreenCover(isPresented: $showHub) {
            MivoClearHubView().environmentObject(appVM)
        }
        .alert("Could not map app", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func mappingRow(_ platform: MivoClearPlatform) -> some View {
        HStack(spacing: 12) {
            Image(systemName: platform.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 40, height: 40)
                .background(MivoColors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(mappedPlatforms.contains(platform) ? "Mapped and protected" : "Choose the native app")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(mappedPlatforms.contains(platform) ? MivoColors.timerGreen : MivoColors.textSecondary)
            }
            Spacer()
            if mappedPlatforms.contains(platform) {
                Button {
                    #if canImport(FamilyControls)
                    FamilyControlsManager.shared.clearMivoClearMapping(for: platform)
                    refreshMappings()
                    #endif
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(MivoColors.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(platform.title) mapping")
            } else {
                Button {
                    #if canImport(FamilyControls)
                    pickerPlatform = platform
                    pickerSelection = FamilyActivitySelection()
                    showPicker = true
                    #endif
                } label: {
                    Text("Map")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(MivoColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    private func refreshMappings() {
        #if canImport(FamilyControls)
        mappedPlatforms = Set(MivoClearPlatform.supportedCases.filter {
            FamilyControlsManager.shared.hasMivoClearMapping(for: $0)
        })
        #endif
    }
}

private struct MivoClearDisclosureView: View {
    let accept: () -> Void

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Image(systemName: "hand.raised.square.fill")
                    .font(.system(size: 42))
                    .foregroundColor(MivoColors.accent)
                Text("Before you use Mivo Clear BETA")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                disclosureRow("Social platforms handle their own sign-in inside Apple's secure WebKit session.")
                disclosureRow("Apple's browser storage keeps sign-in cookies on this device. Mivo never reads or uploads them, passwords, messages, searches, or viewed content.")
                disclosureRow("Platform pages can change. Mivo disables a platform instead of intentionally loading an unfiltered experience.")
                Spacer()
                Button(action: accept) {
                    Text("Continue to Mivo Clear BETA")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }

    private func disclosureRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(MivoColors.accent)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
    }
}

/// Looping storyboards that act out what Mivo Clear does, instead of showing a
/// static icon. Each scene is driven off a shared clock so the motion keeps
/// running for as long as the page is on screen.
private struct MivoClearScene: View {
    let scene: Int
    var systemImage: String = "checkmark.shield.fill"

    private static let beat: TimeInterval = 1.0

    private var phaseCount: Int {
        switch scene {
        case 0: return 3
        case 1: return 4
        case 2: return 5
        case 3: return 3
        default: return 2
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.beat)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.beat)
            let phase = ((tick % phaseCount) + phaseCount) % phaseCount
            phoneFrame {
                switch scene {
                case 0: shortcutScene(phase)
                case 1: blockedSwipeScene(phase)
                case 2: returnToChatScene(phase)
                case 3: controlsScene(phase)
                default: privacyScene(phase)
                }
            }
            .animation(.spring(response: 0.46, dampingFraction: 0.78), value: phase)
        }
    }

    private func phoneFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MivoColors.surfaceRaised)
            content()
        }
        .frame(width: 150, height: 246)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: Scene 0 — an endless feed collapsing into named shortcuts

    private func shortcutScene(_ phase: Int) -> some View {
        let showsShortcuts = phase >= 1
        return ZStack {
            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MivoColors.border.opacity(0.5))
                        .frame(height: 44)
                        .offset(y: showsShortcuts ? CGFloat(12 * (index + 1)) : 0)
                        .opacity(showsShortcuts ? 0 : 1)
                }
            }
            .padding(12)

            VStack(spacing: 8) {
                shortcutRow("message.fill", "Messages")
                shortcutRow("magnifyingglass", "Search")
                shortcutRow("plus.app.fill", "Post")
            }
            .padding(12)
            .opacity(showsShortcuts ? 1 : 0)
            .scaleEffect(showsShortcuts ? 1 : 0.86)
        }
    }

    private func shortcutRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(MivoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Scene 1 — the next-video swipe being refused

    private func blockedSwipeScene(_ phase: Int) -> some View {
        let isSwiping = phase == 1
        let isBlocked = phase >= 2
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MivoColors.primary)
                .padding(10)
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .opacity(isBlocked ? 0 : 1)

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(MivoColors.heroText.opacity(0.85))
                .offset(x: 44, y: isSwiping ? -18 : 70)
                .opacity(isSwiping ? 1 : 0)

            VStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                Text("Next video blocked")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .opacity(isBlocked ? 1 : 0)
            .scaleEffect(isBlocked ? 1 : 0.8)
        }
    }

    // MARK: Scene 2 — a suggested reel appearing, then the trip back to the chat

    private func returnToChatScene(_ phase: Int) -> some View {
        let suggestedVisible = phase == 1
        let returning = phase == 2 || phase == 3
        let inChat = phase == 4
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MivoColors.primary)
                .padding(10)
                .opacity(inChat ? 0 : 1)

            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .opacity(suggestedVisible || returning || inChat ? 0 : 1)

            VStack(spacing: 6) {
                Text("Suggested")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.heroText.opacity(0.75))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MivoColors.heroText.opacity(0.22))
                    .frame(width: 96, height: 108)
            }
            .offset(y: suggestedVisible ? 0 : 150)
            .opacity(suggestedVisible ? 1 : 0)

            chatScene
                .opacity(inChat ? 1 : 0)

            ZStack {
                Color.black.opacity(0.88)
                VStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Returning to chat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .opacity(returning ? 1 : 0)
        }
    }

    private var chatScene: some View {
        VStack(alignment: .leading, spacing: 7) {
            chatBubble(width: 74, isMine: false)
            chatBubble(width: 92, isMine: true)
            chatBubble(width: 60, isMine: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private func chatBubble(width: CGFloat, isMine: Bool) -> some View {
        HStack {
            if isMine { Spacer(minLength: 0) }
            Capsule()
                .fill(isMine ? MivoColors.accent : MivoColors.border.opacity(0.6))
                .frame(width: width, height: 22)
            if !isMine { Spacer(minLength: 0) }
        }
    }

    // MARK: Scene 3 — the control pill, and full screen taking over

    private func controlsScene(_ phase: Int) -> some View {
        let isFullScreen = phase >= 2
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MivoColors.primary)
                .padding(isFullScreen ? 0 : 10)
                .padding(.top, isFullScreen ? 0 : 34)

            HStack(spacing: 3) {
                ForEach(["chevron.left", "speaker.wave.2.fill", isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right", "xmark"], id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                }
            }
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.top, phase >= 1 ? 8 : -34)
            .opacity(phase >= 1 ? 1 : 0)
        }
    }

    // MARK: Scene 4 — nothing leaves the device

    private func privacyScene(_ phase: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(MivoColors.blue)
                .scaleEffect(phase == 1 ? 1.08 : 1)
            Text("Time used only")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
        }
    }
}

private struct MivoClearTutorialView: View {
    private struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let detail: String
        let systemImage: String
    }

    private let pages = [
        Page(
            id: 0,
            eyebrow: "CHOOSE",
            title: "Start with what you came to do",
            detail: "Open Messages, Search, Profile, Post, or Settings directly instead of landing in an endless feed.",
            systemImage: "scope"
        ),
        Page(
            id: 1,
            eyebrow: "FILTER",
            title: "One video stays one video",
            detail: "A video shared by a friend can still play. Mivo blocks the next-video swipe and keeps Reels, Shorts, and For You routes out.",
            systemImage: "hand.raised.fill"
        ),
        Page(
            id: 2,
            eyebrow: "RETURN",
            title: "Scroll past it and you land back in the chat",
            detail: "If the app slips a suggested video in after the one you opened, Mivo stops it and takes you straight back to the conversation you came from.",
            systemImage: "arrow.uturn.backward"
        ),
        Page(
            id: 3,
            eyebrow: "NAVIGATE",
            title: "The controls stay close",
            detail: "Back, Home, Reload, Forward, sound, and full screen stay one tap away — even while a single video is playing.",
            systemImage: "slider.horizontal.3"
        ),
        Page(
            id: 4,
            eyebrow: "CONTROL",
            title: "Leave whenever you are done",
            detail: "Tap Close to return to Mivo. Clear records only time used and blocked routes, never passwords, messages, searches, or viewed content.",
            systemImage: "checkmark.shield.fill"
        )
    ]

    let finish: () -> Void

    @State private var page = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Label("Mivo Clear BETA", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip") { completeTutorial() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        tutorialPage(item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages) { item in
                        Capsule()
                            .fill(item.id == page ? MivoColors.accent : MivoColors.border.opacity(0.45))
                            .frame(width: item.id == page ? 26 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                    }
                }
                .padding(.bottom, 20)

                Button(action: advance) {
                    HStack(spacing: 10) {
                        Text(page == pages.count - 1 ? "Start Mivo Clear BETA" : "Next")
                        Image(systemName: page == pages.count - 1 ? "arrow.up.right" : "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                isAnimating = true
            }
        }
        .onChange(of: page) { _, _ in
            HapticsService.selection()
        }
    }

    private func tutorialPage(_ item: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 22)

            tutorialVisual(for: item.id, systemImage: item.systemImage)
                .frame(maxWidth: .infinity)
                .scaleEffect(isAnimating ? 1 : 0.92)
                .opacity(isAnimating ? 1 : 0)

            Spacer(minLength: 28)

            Text(item.eyebrow)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text(item.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.detail)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func tutorialVisual(for page: Int, systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(MivoColors.accent.opacity(0.1))
                .frame(width: 226, height: 226)
            Circle()
                .stroke(MivoColors.accent.opacity(0.24), lineWidth: 2)
                .frame(width: 174, height: 174)

            MivoClearScene(scene: page, systemImage: systemImage)
        }
        .frame(height: 250)
        .accessibilityHidden(true)
    }

    private func advance() {
        HapticsService.impact(style: .medium)
        guard page < pages.count - 1 else {
            completeTutorial()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            page += 1
        }
    }

    private func completeTutorial() {
        HapticsService.success()
        finish()
    }
}

private struct MivoClearYouTubePortalView: View {
    @Environment(\.dismiss) private var dismiss
    let route: MivoClearRoute
    let configuration: MivoClearPlatformConfiguration

    @State private var searchText = ""
    @State private var browserRoute: MivoClearRoute?

    private let youtubeRed = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(youtubeRed)
                    Text("YouTube")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.black)

                    Spacer()

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .frame(height: 74)

                Spacer(minLength: 42)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 82, weight: .bold))
                    .foregroundColor(youtubeRed)
                    .accessibilityHidden(true)

                HStack(spacing: 10) {
                    TextField("Search YouTube", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(search)
                        .font(.system(size: 17, weight: .medium))
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())

                    Button(action: search) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 52, height: 52)
                            .background(Color.black.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Search to get started")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    Text("Open the video you came for without loading the Shorts feed.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.58))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
                .padding(.horizontal, 24)
                .padding(.top, 42)

                Spacer()

                Text("Search-only mode · Shorts removed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.48))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1) }
            }
        }
        .task { openInitialRouteIfNeeded() }
        .fullScreenCover(item: $browserRoute) { browserRoute in
            MivoClearBrowserView(route: browserRoute, configuration: configuration)
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              var components = URLComponents(string: "https://www.youtube.com/results") else { return }
        HapticsService.selection()
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let url = components.url else { return }
        browserRoute = MivoClearRoute(platform: .youtube, directURL: url, entryPoint: route.entryPoint)
    }

    private func open(actionID: String) {
        HapticsService.selection()
        browserRoute = MivoClearRoute(platform: .youtube, quickActionID: actionID, entryPoint: route.entryPoint)
    }

    private func openInitialRouteIfNeeded() {
        if route.directURL != nil || (route.quickActionID != nil && route.quickActionID != "search") {
            browserRoute = route
        }
    }
}

private func mivoClearTikTokLoginURL() -> URL? {
    var components = URLComponents(string: "https://www.tiktok.com/login/phone-or-email/email")
    components?.queryItems = [
        URLQueryItem(name: "redirect_url", value: "https://www.tiktok.com/profile")
    ]
    return components?.url
}

private struct MivoClearTikTokPortalView: View {
    @Environment(\.dismiss) private var dismiss
    let route: MivoClearRoute
    let configuration: MivoClearPlatformConfiguration

    @State private var searchText = ""
    @State private var browserRoute: MivoClearRoute?

    private let tiktokPink = Color(red: 0.996, green: 0.173, blue: 0.333)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Button("Close Mivo Clear BETA", role: .destructive) { dismiss() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text("TikTok")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 14)
                .frame(height: 66)

                HStack(spacing: 10) {
                    TextField("Search people", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(search)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())

                    Button(action: search) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(tiktokPink)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 18) {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)
                    Text("Log in for creating and profiles")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("Mivo Clear BETA removes Home, For You, Following, Live, Shop, and continuous video routes.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    Button {
                        open(url: mivoClearTikTokLoginURL())
                    } label: {
                        Text("Log in with email or phone")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(tiktokPink)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 34)

                Spacer()

                HStack(spacing: 10) {
                    tiktokTab("plus.circle.fill", title: "Create", actionID: "create", emphasized: true)
                    tiktokTab("person.crop.circle.fill", title: "Profile", actionID: "profile")
                }
                .padding(.horizontal, 22)
                .frame(height: 88)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1) }
            }
        }
        .task { openInitialRouteIfNeeded() }
        .fullScreenCover(item: $browserRoute) { browserRoute in
            MivoClearBrowserView(route: browserRoute, configuration: configuration)
        }
    }

    private func tiktokTab(_ icon: String, title: String, actionID: String, emphasized: Bool = false) -> some View {
        Button { open(actionID: actionID) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(emphasized ? tiktokPink : Color.white.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              var components = URLComponents(string: "https://www.tiktok.com/search/user") else { return }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        open(url: components.url)
    }

    private func open(actionID: String) {
        HapticsService.selection()
        browserRoute = MivoClearRoute(platform: .tiktok, quickActionID: actionID, entryPoint: route.entryPoint)
    }

    private func open(url: URL?) {
        guard let url else { return }
        HapticsService.selection()
        browserRoute = MivoClearRoute(platform: .tiktok, directURL: url, entryPoint: route.entryPoint)
    }

    private func openInitialRouteIfNeeded() {
        if route.directURL != nil || (route.quickActionID != nil && route.quickActionID != "search") {
            browserRoute = route
        } else if route.quickActionID == nil {
            browserRoute = MivoClearRoute(
                platform: .tiktok,
                quickActionID: "profile",
                entryPoint: route.entryPoint
            )
        }
    }
}

struct MivoClearBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = MivoClearStore.shared
    let route: MivoClearRoute
    let configuration: MivoClearPlatformConfiguration

    @StateObject private var controller = MivoClearWebController()
    @State private var ruleList: WKContentRuleList?
    @State private var isPreparing = true
    @State private var preparationFailed = false
    @State private var helpCollapsed = false
    @State private var showBrowserSettings = false
    @State private var isImmersive = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if !hidesBrowserChrome {
                    browserHeader
                    browserHelpStrip
                    if controller.isSingleMediaMode {
                        singleMediaBanner
                    } else if configuration.platform != .tiktok && configuration.platform != .instagram {
                        browserShortcutBar
                    }
                }
                browserContent
                if !hidesBrowserChrome {
                    browserToolbar
                    if configuration.platform == .tiktok, !controller.isSingleMediaMode {
                        tiktokBottomNavigation
                    } else if configuration.platform == .instagram, !controller.isSingleMediaMode {
                        instagramBottomNavigation
                    }
                }
            }
            .ignoresSafeArea(.container, edges: isImmersive ? .bottom : [])
            if hidesBrowserChrome {
                floatingControls
            }
            if let notice = controller.returnNotice {
                MivoClearReturnOverlay(title: notice.title)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: controller.returnNotice)
        .statusBarHidden(isImmersive)
        .sheet(isPresented: $showBrowserSettings) {
            browserSettings
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $controller.presentedMedia) { media in
            MivoClearSingleVideoView(media: media)
        }
        .task {
            do {
                ruleList = try await MivoClearContentRuleCompiler.compile(configuration: configuration)
                store.beginSession(platform: configuration.platform, entryPoint: route.entryPoint, filterVersion: configuration.version)
            } catch {
                preparationFailed = true
                store.lastError = error.localizedDescription
            }
            isPreparing = false
        }
        .onDisappear { store.endActiveSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resumeActiveSession() }
            else { store.pauseActiveSession() }
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if isPreparing {
            ProgressView("Preparing focused view...")
                .tint(MivoColors.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if preparationFailed {
            MivoClearUnavailableView()
        } else if let startURL = startingURL {
            MivoClearWebView(
                controller: controller,
                configuration: configuration,
                startURL: startURL,
                ruleList: ruleList,
                allowInitialBlockedPath: route.quickActionID != nil,
                initialActionID: route.quickActionID,
                singleMediaURL: route.directURL,
                blocked: { store.recordBlockedRoute() }
            )
        } else {
            MivoClearUnavailableView()
        }
    }

    private var hidesBrowserChrome: Bool {
        isImmersive || (configuration.platform == .instagram && controller.isSingleMediaMode)
    }

    private var browserHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(configuration.platform.title)
                    .font(.system(size: 15, weight: .bold))
                Label(
                    controller.isSingleMediaMode ? singleMediaTitle : "Short-form paths filtered",
                    systemImage: "checkmark.shield.fill"
                )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
            }
            Spacer()
            if controller.isLoading { ProgressView().tint(MivoColors.accent) }
            Button {
                HapticsService.selection()
                controller.unmuteMedia()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unmute media")
            Button {
                HapticsService.selection()
                withAnimation(.easeInOut(duration: 0.2)) { isImmersive = true }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter full screen")
        }
        .foregroundColor(MivoColors.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(MivoColors.surface)
    }

    private var startingURL: URL? {
        if configuration.platform == .instagram, route.quickActionID == "profile" {
            // Instagram has no stable self-profile URL, so the session starts on
            // Messages and the runtime taps the account's own profile link.
            return configuration.url(for: "messages")
        }
        if configuration.platform == .tiktok,
           route.directURL == nil,
           route.quickActionID == "messages" || route.quickActionID == "create" {
            return configuration.url(for: "profile")
        }
        return route.directURL ?? configuration.url(for: route.quickActionID)
    }

    private var browserToolbar: some View {
        HStack(spacing: 0) {
            // Always enabled: social sites route client side, so `canGoBack`
            // under-reports, and with no history left this falls back home.
            browserButton("chevron.left", label: "Back", enabled: true) {
                controller.goBack()
            }
            if configuration.platform != .tiktok {
                browserButton(homeIcon, label: homeLabel, enabled: true) {
                    controller.load(homeDestination)
                }
            }
            browserButton("arrow.clockwise", label: "Reload", enabled: true) {
                controller.reload()
            }
            browserButton("chevron.right", label: "Forward", enabled: controller.canGoForward) {
                controller.goForward()
            }
            browserButton("gearshape.fill", label: "Mivo Clear BETA settings", enabled: true) {
                showBrowserSettings = true
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 58)
        .background(MivoColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(MivoColors.background)
    }

    /// YouTube's configured home is an empty results page, which is a dead end
    /// once a long video is playing. Prefer the last real search results.
    private var isYouTubeWatchPage: Bool {
        configuration.platform == .youtube
            && controller.currentURL?.path.hasPrefix("/watch") == true
    }

    private var homeDestination: URL? {
        if configuration.platform == .youtube, let results = controller.lastResultsURL {
            return results
        }
        return configuration.url(for: nil)
    }

    private var homeIcon: String {
        isYouTubeWatchPage && controller.lastResultsURL != nil
            ? "list.bullet.rectangle.portrait.fill"
            : "house.fill"
    }

    private var homeLabel: String {
        isYouTubeWatchPage && controller.lastResultsURL != nil ? "Back to results" : "Home"
    }

    private var tiktokBottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(configuration.userFacingQuickActions) { action in
                Button {
                    openQuickAction(action)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.system(size: action.id == "create" ? 22 : 18, weight: .bold))
                            .frame(width: 34, height: 25)
                            .background(action.id == "create" ? Color(red: 0.996, green: 0.173, blue: 0.333) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(action.title)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
        }
    }

    private var instagramBottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(configuration.userFacingQuickActions.filter { $0.id != "settings" }) { action in
                Button {
                    openQuickAction(action)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 34, height: 25)
                        Text(action.title)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(MivoColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .background(MivoColors.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.55)).frame(height: 1)
        }
    }

    /// Shown whenever the standard chrome is hidden — full screen, and also
    /// Instagram's single-reel mode, which otherwise leaves no Mivo controls.
    private var floatingControls: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        HapticsService.selection()
                        controller.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Back")

                    Button {
                        HapticsService.selection()
                        controller.unmuteMedia()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Unmute media")

                    Button {
                        HapticsService.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { isImmersive.toggle() }
                    } label: {
                        Image(systemName: isImmersive
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(isImmersive ? "Exit full screen" : "Enter full screen")

                    Button {
                        HapticsService.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Close Mivo Clear BETA")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.top, isImmersive ? 2 : 6)
            .padding(.trailing, 10)
            Spacer()
        }
        .ignoresSafeArea(.container, edges: isImmersive ? .top : [])
        .transition(.opacity)
    }

    private var singleMediaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MivoColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(singleMediaTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(singleMediaDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer()
            Button(singleMediaReturnTitle) {
                let action = configuration.platform == .tiktok ? "profile" : "messages"
                controller.load(configuration.url(for: action) ?? configuration.url(for: nil))
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(MivoColors.heroText)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(MivoColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(MivoColors.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.42)).frame(height: 1)
        }
    }

    private var singleMediaTitle: String {
        configuration.platform == .tiktok ? "One TikTok only" : "One reel only"
    }

    private var singleMediaDetail: String {
        configuration.platform == .tiktok
            ? "The selected video plays, but swiping to another is blocked."
            : "Swiping and next-reel navigation are blocked."
    }

    private var singleMediaReturnTitle: String {
        configuration.platform == .tiktok ? "Back to Profile" : "Back to Messages"
    }

    @ViewBuilder
    private var browserHelpStrip: some View {
        if helpCollapsed {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        helpCollapsed = false
                    }
                } label: {
                    Label("Help", systemImage: "questionmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(MivoColors.background)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .frame(width: 34, height: 34)
                    .background(MivoColors.blue.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(helpTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(helpDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        helpCollapsed = true
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(MivoColors.border.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize help")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MivoColors.surfaceRaised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MivoColors.border.opacity(0.42)).frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var helpTitle: String {
        if controller.currentURL?.path.localizedCaseInsensitiveContains("login") == true {
            return "Need help logging in?"
        }
        return "Using \(configuration.platform.title) in Mivo Clear BETA"
    }

    private var helpDetail: String {
        switch configuration.platform {
        case .instagram:
            return "Sign in normally. Mivo keeps messages and search while filtering Reels and feed routes."
        case .tiktok:
            return "Use email or phone to sign in. Home, For You, Live, and continuous videos stay filtered."
        case .youtube:
            return "Search and open longer videos. Shorts routes remain unavailable."
        case .snapchat:
            return "This platform is not currently available in Mivo Clear BETA."
        }
    }

    private var browserSettings: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(MivoColors.accent)
                                .frame(width: 42, height: 42)
                                .background(MivoColors.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Filtering is active")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(MivoColors.textPrimary)
                                Text("Rules version \(configuration.version) for \(configuration.platform.title)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(MivoColors.textSecondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("QUICK PLACES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(MivoColors.textMuted)
                                .padding(.bottom, 10)

                            ForEach(Array(configuration.userFacingQuickActions.enumerated()), id: \.element.id) { index, action in
                                Button {
                                    openQuickAction(action)
                                    showBrowserSettings = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: action.icon)
                                            .foregroundColor(MivoColors.accent)
                                            .frame(width: 28)
                                        Text(action.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(MivoColors.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(MivoColors.textMuted)
                                    }
                                    .frame(height: 48)
                                }
                                .buttonStyle(.plain)
                                if index < configuration.userFacingQuickActions.count - 1 {
                                    Divider().overlay(MivoColors.border.opacity(0.4)).padding(.leading, 40)
                                }
                            }
                        }
                        .padding(14)
                        .background(MivoColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Label(
                            "Mivo never reads or uploads passwords, messages, searches, cookies, or viewed content.",
                            systemImage: "hand.raised.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)

                        Button(role: .destructive) {
                            showBrowserSettings = false
                            dismiss()
                        } label: {
                            Label("Close Mivo Clear BETA", systemImage: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Mivo Clear BETA Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showBrowserSettings = false }
                }
            }
        }
    }

    private var browserShortcutBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(configuration.userFacingQuickActions) { action in
                    Button { openQuickAction(action) } label: {
                        Label(action.title, systemImage: action.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(MivoColors.surfaceRaised.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 46)
        .background(MivoColors.background)
    }

    private func openQuickAction(_ action: MivoClearQuickAction) {
        HapticsService.selection()
        if configuration.platform == .tiktok {
            guard let destination = configuration.url(for: action.id) else { return }
            controller.isSingleMediaMode = false
            controller.openTikTokUtility(actionID: action.id, fallback: destination)
        } else if configuration.platform == .instagram, action.id == "profile" {
            controller.openInstagramProfile(fallback: configuration.url(for: "profile"))
        } else {
            controller.load(configuration.url(for: action.id))
        }
    }

    private func browserButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticsService.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(enabled ? MivoColors.textPrimary : MivoColors.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct MivoClearPresentedMedia: Identifiable, Equatable {
    let id = UUID()
    let platform: MivoClearPlatform
    let sourceURL: URL

    var isDirectVideoSource: Bool {
        MivoClearSingleMediaPolicy.instagramReelIdentifier(in: sourceURL.path) == nil
    }

    var instagramEmbedURL: URL {
        guard let identifier = MivoClearSingleMediaPolicy.instagramReelIdentifier(
            in: sourceURL.path
        ) else {
            return sourceURL
        }
        var output = URLComponents()
        output.scheme = "https"
        output.host = "www.instagram.com"
        output.path = "/reel/\(identifier)/embed/"
        return output.url ?? sourceURL
    }
}

private struct MivoClearReturnOverlay: View {
    let title: String

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(isVisible ? 1 : 0.7)
                    .opacity(isVisible ? 1 : 0)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(isVisible ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { isVisible = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct MivoClearReturnNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let destination: URL?
}

@MainActor
final class MivoClearWebController: ObservableObject {
    weak var webView: WKWebView?
    private var platform: MivoClearPlatform?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var isSingleMediaMode = false
    @Published var presentedMedia: MivoClearPresentedMedia?
    @Published var returnNotice: MivoClearReturnNotice?

    /// The most recent YouTube search-results page, so a long video always has
    /// somewhere to return to without closing Mivo Clear.
    private(set) var lastResultsURL: URL?
    private var backNavigationDeadline = Date.distantPast
    private var returnWorkItem: DispatchWorkItem?
    private var returnNavigationStarted = false
    private var homeURL: URL?

    var isBackNavigationActive: Bool { Date() < backNavigationDeadline }

    func attach(_ webView: WKWebView, platform: MivoClearPlatform, homeURL: URL? = nil) {
        self.webView = webView
        self.platform = platform
        self.homeURL = homeURL
    }

    func rememberResultsURL(_ url: URL?) {
        guard let url, url.path.hasPrefix("/results") else { return }
        lastResultsURL = url
    }

    func goBack() {
        guard let webView else { return }
        beginBackNavigation()
        if webView.canGoBack {
            webView.goBack()
            return
        }
        // Social sites route client side, so a native back entry is not always
        // available even when the page itself has somewhere to go.
        webView.evaluateJavaScript("history.length") { [weak self] value, _ in
            let length = (value as? NSNumber)?.intValue ?? 0
            if length > 1 {
                webView.evaluateJavaScript("history.back()")
            } else {
                self?.loadHome()
            }
        }
    }

    private func beginBackNavigation() {
        backNavigationDeadline = Date().addingTimeInterval(2.5)
        let until = Int(backNavigationDeadline.timeIntervalSince1970 * 1000)
        webView?.evaluateJavaScript(
            "try { sessionStorage.setItem('mivo.clear.back.until', '\(until)'); } catch (e) {}"
        )
    }

    private func loadHome() {
        if let homeURL {
            load(homeURL)
            return
        }
        guard let platform,
              let configuration = MivoClearStore.shared.configuration(for: platform) else { return }
        load(configuration.url(for: nil))
    }

    func announceReturn(title: String, destination: URL?) {
        guard returnNotice == nil else { return }
        returnWorkItem?.cancel()
        isSingleMediaMode = false
        presentedMedia = nil
        returnNavigationStarted = false
        HapticsService.impact(style: .medium)
        returnNotice = MivoClearReturnNotice(title: title, destination: destination)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.returnNavigationStarted = true
            if let destination {
                self.load(destination)
            } else {
                self.loadHome()
            }
        }
        returnWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        // Safety net: never strand the viewer behind the overlay if the
        // destination never reports a finished navigation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.returnNavigationStarted = true
            self?.clearReturnNotice()
        }
    }

    /// Ignored until the return navigation is actually under way, so an
    /// in-flight load from the page being left cannot dismiss the overlay early.
    func clearReturnNotice() {
        guard returnNotice != nil, returnNavigationStarted else { return }
        returnNotice = nil
    }

    func goForward() { webView?.goForward() }
    func reload() {
        guard let webView, let url = webView.url else { return }
        if platform == .instagram, url.path.lowercased().hasPrefix("/direct") {
            webView.load(MivoClearWebSession.request(url: url, platform: .instagram, forceRefresh: true))
        } else {
            webView.reload()
        }
    }
    func load(_ url: URL?) {
        guard let url, let platform else { return }
        webView?.load(
            MivoClearWebSession.request(
                url: url,
                platform: platform
            )
        )
    }
    func openTikTokUtility(actionID: String, fallback: URL?) {
        guard platform == .tiktok else {
            load(fallback)
            return
        }
        let targetPath = actionID == "messages" ? "/messages" : "/upload"
        let fallbackValue = fallback?.absoluteString ?? "https://www.tiktok.com\(targetPath)"
        guard let payload = try? JSONSerialization.data(
            withJSONObject: [targetPath, fallbackValue]
        ),
        let encoded = String(data: payload, encoding: .utf8) else {
            load(fallback)
            return
        }
        let script = """
        (() => {
          const [targetPath, fallback] = \(encoded);
          let attempts = 0;
          const openUtility = () => {
            const selectors = [
              `a[href='${targetPath}']`,
              `a[href^='${targetPath}?']`,
              targetPath === '/messages' ? "[data-e2e='nav-messages']" : "[data-e2e='nav-upload']"
            ];
            for (const selector of selectors) {
              const control = document.querySelector(selector);
              const link = control && (control.closest('a[href]') || control.querySelector('a[href]') || control);
              if (link && typeof link.click === 'function') {
                link.click();
                return true;
              }
            }
            attempts += 1;
            if (attempts < 12) {
              setTimeout(openUtility, 200);
            } else {
              location.assign(fallback);
            }
            return false;
          };
          return openUtility();
        })();
        """
        webView?.evaluateJavaScript(script)
    }
    func presentSingleMedia(_ url: URL, platform: MivoClearPlatform) {
        guard presentedMedia?.sourceURL != url else { return }
        presentedMedia = MivoClearPresentedMedia(platform: platform, sourceURL: url)
    }
    func openInstagramProfile(fallback: URL?) {
        let fallbackValue = fallback?.absoluteString ?? "https://www.instagram.com/accounts/edit/"
        guard let fallbackData = try? JSONSerialization.data(withJSONObject: [fallbackValue]),
              let encodedFallback = String(data: fallbackData, encoding: .utf8) else {
            load(fallback)
            return
        }
        let script = """
        (() => {
          let attempts = 0;
          const fallback = \(encodedFallback)[0];
          const findProfile = () => {
            const selectors = [
              "a[aria-label='Profile'][href]",
              "a[role='link'][aria-label*='Profile' i][href]",
              "a[href]:has(svg[aria-label='Profile'])",
              "a[href]:has(img[alt*='your profile picture' i])",
              "a[href]:has(img[alt*='profile picture' i])"
            ];
            for (const selector of selectors) {
              let link = null;
              try { link = document.querySelector(selector); } catch (_) { continue; }
              if (link && link.href) {
                link.click();
                return true;
              }
            }
            attempts += 1;
            if (attempts < 12) {
              setTimeout(findProfile, 250);
            } else {
              location.assign(fallback);
            }
            return false;
          };
          return findProfile();
        })();
        """
        webView?.evaluateJavaScript(script)
    }
    func unmuteMedia() {
        let script = """
        (() => {
          let changed = 0;
          const visited = new WeakSet();
          const unmuteRoot = root => {
            if (!root || visited.has(root)) return;
            visited.add(root);
            root.querySelectorAll('video, audio').forEach(media => {
              try {
                media.muted = false;
                media.defaultMuted = false;
                media.volume = 1;
                media.removeAttribute('muted');
                const result = media.play();
                if (result && result.catch) result.catch(() => {});
                changed += 1;
              } catch (_) {}
            });
            root.querySelectorAll('button, [role="button"]').forEach(control => {
              const marker = ((control.getAttribute('aria-label') || '') + ' ' +
                (control.getAttribute('title') || '') + ' ' +
                (control.textContent || '')).trim().toLowerCase();
              if (marker.includes('unmute') || marker.includes('sound on') || marker.includes('turn on sound')) {
                try { control.click(); changed += 1; } catch (_) {}
              }
            });
            root.querySelectorAll('*').forEach(node => {
              if (node.shadowRoot) unmuteRoot(node.shadowRoot);
            });
            root.querySelectorAll('iframe').forEach(frame => {
              try { if (frame.contentDocument) unmuteRoot(frame.contentDocument); } catch (_) {}
            });
          };
          unmuteRoot(document);
          if (changed === 0) {
            const candidates = Array.from(document.elementsFromPoint(
              Math.max(1, innerWidth - 36),
              Math.max(1, 44)
            ));
            for (const control of candidates) {
              const marker = ((control.getAttribute && control.getAttribute('aria-label')) || '').toLowerCase();
              if (marker.includes('mute') || marker.includes('sound')) {
                try { control.click(); changed += 1; } catch (_) {}
                break;
              }
            }
          }
          return changed;
        })();
        """
        webView?.evaluateJavaScript(script)
    }
}

private struct MivoClearSingleVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = MivoClearWebController()
    let media: MivoClearPresentedMedia

    @State private var isImmersive = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if !isImmersive {
                    HStack(spacing: 10) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Close video")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("One Reel")
                                .font(.system(size: 17, weight: .bold))
                            Text("No next video or swipe feed")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.68))
                        }
                        Spacer()
                        Button {
                            HapticsService.selection()
                            controller.unmuteMedia()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Unmute video")

                        Button {
                            HapticsService.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { isImmersive = true }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Enter full screen")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 62)
                }

                MivoClearSingleVideoWebView(
                    controller: controller,
                    url: media.instagramEmbedURL,
                    platform: media.platform,
                    isDirectVideoSource: media.isDirectVideoSource
                )
                .background(Color.black)
            }
            .ignoresSafeArea(.container, edges: isImmersive ? .all : [])

            if isImmersive {
                HStack(spacing: 2) {
                    Button {
                        HapticsService.selection()
                        controller.unmuteMedia()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Unmute video")

                    Button {
                        HapticsService.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { isImmersive = false }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Exit full screen")

                    Button {
                        HapticsService.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Close video")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 6)
                .padding(.trailing, 10)
                .transition(.opacity)
            }
        }
        .statusBarHidden(isImmersive)
    }
}

private struct MivoClearSingleVideoWebView: UIViewRepresentable {
    @ObservedObject var controller: MivoClearWebController
    let url: URL
    let platform: MivoClearPlatform
    let isDirectVideoSource: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(allowedURL: url, isDirectVideoSource: isDirectVideoSource)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let source = """
        (() => {
          const apply = () => {
            document.documentElement.style.setProperty('overflow', 'hidden', 'important');
            document.documentElement.style.setProperty('overscroll-behavior', 'none', 'important');
            if (document.body) {
              document.body.style.setProperty('overflow', 'hidden', 'important');
              document.body.style.setProperty('overscroll-behavior', 'none', 'important');
              document.body.style.setProperty('margin', '0', 'important');
            }
          };
          new MutationObserver(apply).observe(document.documentElement, { childList: true, subtree: true });
          apply();
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let panBlocker = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.blockPan(_:))
        )
        panBlocker.maximumNumberOfTouches = 1
        panBlocker.cancelsTouchesInView = true
        panBlocker.delegate = context.coordinator
        webView.addGestureRecognizer(panBlocker)
        webView.scrollView.panGestureRecognizer.require(toFail: panBlocker)

        controller.attach(webView, platform: platform)
        if isDirectVideoSource {
            webView.loadHTMLString(Self.directVideoHTML(for: url), baseURL: nil)
        } else {
            webView.load(MivoClearWebSession.request(url: url, platform: platform, forceRefresh: true))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.scrollView.isScrollEnabled = false
        uiView.scrollView.bounces = false
    }

    private static func directVideoHTML(for url: URL) -> String {
        let encodedURL = (try? JSONSerialization.data(withJSONObject: [url.absoluteString]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <style>
            html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
            video { width: 100%; height: 100%; object-fit: contain; background: #000; }
          </style>
        </head>
        <body>
          <video id="mivo-video" controls autoplay playsinline></video>
          <script>
            const source = \(encodedURL)[0];
            const video = document.getElementById('mivo-video');
            video.src = source;
            video.play().catch(() => {});
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        let allowedURL: URL
        let isDirectVideoSource: Bool

        init(allowedURL: URL, isDirectVideoSource: Bool) {
            self.allowedURL = allowedURL
            self.isDirectVideoSource = isDirectVideoSource
        }

        @objc func blockPan(_ gesture: UIPanGestureRecognizer) {}

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) >= abs(velocity.x)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if isDirectVideoSource, target.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            guard isMainFrame else {
                decisionHandler(.allow)
                return
            }
            let allowedHost = target.host?.lowercased().hasSuffix("instagram.com") == true
            let allowedPath = target.path == allowedURL.path || target.path.hasPrefix("/accounts/login")
            decisionHandler(allowedHost && allowedPath ? .allow : .cancel)
        }
    }
}

private enum MivoClearWebSession {
    static func request(url: URL, platform: MivoClearPlatform, forceRefresh: Bool = false) -> URLRequest {
        let refreshInstagramDirect = platform == .instagram
            && url.path.lowercased().hasPrefix("/direct")
        var request = URLRequest(
            url: url,
            cachePolicy: forceRefresh || refreshInstagramDirect
                ? .reloadIgnoringLocalCacheData
                : .useProtocolCachePolicy,
            timeoutInterval: 25
        )
        if forceRefresh || refreshInstagramDirect {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        return request
    }
}

private struct MivoClearWebView: UIViewRepresentable {
    @ObservedObject var controller: MivoClearWebController
    let configuration: MivoClearPlatformConfiguration
    let startURL: URL
    let ruleList: WKContentRuleList?
    let allowInitialBlockedPath: Bool
    let initialActionID: String?
    let singleMediaURL: URL?
    let blocked: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, allowInitialBlockedPath: allowInitialBlockedPath, initialActionID: initialActionID, singleMediaURL: singleMediaURL, blocked: blocked, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback =
            configuration.platform == .instagram || configuration.platform == .tiktok ? [] : .all
        if configuration.platform == .tiktok {
            // TikTok's mobile site omits parts of direct messaging. Desktop
            // content mode keeps the first-party message composer available.
            config.defaultWebpagePreferences.preferredContentMode = .desktop
            config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        } else if configuration.platform == .instagram {
            config.defaultWebpagePreferences.preferredContentMode = .mobile
        }
        // Meta and TikTok authentication move through first-party subdomains that
        // are not consistently treated as one app-bound domain. The navigation
        // delegate still rejects every host outside each platform's allowlist.
        config.limitsNavigationsToAppBoundDomains = configuration.platform != .tiktok
            && configuration.platform != .instagram
        if let ruleList { config.userContentController.add(ruleList) }
        if let guardScript = try? MivoClearRuntimeGuard.script(configuration: configuration, singleMediaURL: singleMediaURL) {
            config.userContentController.addUserScript(guardScript)
        }
        config.userContentController.add(context.coordinator, name: "mivoClearSingleMedia")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        let mediaPanBlocker = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.blockSingleMediaPan(_:))
        )
        mediaPanBlocker.maximumNumberOfTouches = 1
        mediaPanBlocker.cancelsTouchesInView = true
        mediaPanBlocker.delegate = context.coordinator
        mediaPanBlocker.isEnabled = false
        view.addGestureRecognizer(mediaPanBlocker)
        view.scrollView.panGestureRecognizer.require(toFail: mediaPanBlocker)
        context.coordinator.mediaPanBlocker = mediaPanBlocker
        controller.attach(
            view,
            platform: configuration.platform,
            homeURL: configuration.url(for: nil)
        )
        view.load(MivoClearWebSession.request(url: startURL, platform: configuration.platform))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let disablesWebScroll = controller.isSingleMediaMode && configuration.platform != .instagram
        uiView.scrollView.isScrollEnabled = !disablesWebScroll
        uiView.scrollView.bounces = !controller.isSingleMediaMode
        context.coordinator.mediaPanBlocker?.isEnabled = controller.isSingleMediaMode
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mivoClearSingleMedia")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        private let policy: MivoClearNavigationPolicy
        private var allowInitialBlockedPath: Bool
        private let initialActionID: String?
        private var performedInitialAction = false
        private var singleMediaPath: String?
        private let blocked: () -> Void
        private weak var controller: MivoClearWebController?
        private var recoveryAttempts = 0
        private var navigationGeneration = 0
        private var backHops = 0
        weak var mediaPanBlocker: UIPanGestureRecognizer?

        init(configuration: MivoClearPlatformConfiguration, allowInitialBlockedPath: Bool, initialActionID: String?, singleMediaURL: URL?, blocked: @escaping () -> Void, controller: MivoClearWebController) {
            policy = MivoClearNavigationPolicy(configuration: configuration)
            self.allowInitialBlockedPath = allowInitialBlockedPath
            self.initialActionID = initialActionID
            singleMediaPath = singleMediaURL.flatMap {
                MivoClearSingleMediaPolicy.singleMediaPath(for: $0, configuration: configuration)
            }
            self.blocked = blocked
            self.controller = controller
        }

        @objc func blockSingleMediaPan(_ gesture: UIPanGestureRecognizer) {
            // Recognizing the gesture at the native WebView level prevents an
            // embedded social viewer from consuming it as "next video."
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === mediaPanBlocker,
                  controller?.isSingleMediaMode == true,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) >= abs(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            // Instagram only serves the post composer to a desktop user agent.
            if policy.configuration.platform == .instagram,
               navigationAction.request.url?.path.lowercased().hasPrefix("/create") == true {
                preferences.preferredContentMode = .desktop
            }
            decidePolicy(for: navigationAction, in: webView) { decision in
                decisionHandler(decision, preferences)
            }
        }

        private func decidePolicy(
            for navigationAction: WKNavigationAction,
            in webView: WKWebView,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if policy.configuration.platform == .instagram,
               isMainFrame,
               MivoClearSingleMediaPolicy.instagramReelIdentifier(in: url.path) != nil {
                decisionHandler(.cancel)
                controller?.isSingleMediaMode = false
                controller?.presentSingleMedia(url, platform: .instagram)
                return
            }
            if isMainFrame, let mediaPath = MivoClearSingleMediaPolicy.singleMediaPath(
                for: url,
                configuration: policy.configuration
            ) {
                if let singleMediaPath, singleMediaPath != mediaPath {
                    blocked()
                    decisionHandler(.cancel)
                    webView.load(MivoClearWebSession.request(url: focusedFallbackURL, platform: policy.configuration.platform))
                    return
                }
                singleMediaPath = mediaPath
                controller?.isSingleMediaMode = true
                persistSingleMediaPath(mediaPath, in: webView) {
                    decisionHandler(.allow)
                }
                return
            } else if isMainFrame,
                      (policy.configuration.platform == .instagram || policy.configuration.platform == .tiktok),
                      policy.configuration.allows(host: url.host) {
                singleMediaPath = nil
                controller?.isSingleMediaMode = false
            }
            let permitInitial = allowInitialBlockedPath
            allowInitialBlockedPath = false
            switch policy.decision(for: url, allowBlockedQuickAction: permitInitial) {
            case .allow: decisionHandler(.allow)
            case .redirect(let fallback):
                blocked()
                decisionHandler(.cancel)
                // Stepping back onto a filtered route should keep walking the
                // history rather than dumping the viewer at the home route.
                if controller?.isBackNavigationActive == true,
                   webView.canGoBack,
                   backHops < 5 {
                    backHops += 1
                    webView.goBack()
                    return
                }
                backHops = 0
                webView.load(MivoClearWebSession.request(url: fallback, platform: policy.configuration.platform))
            case .external:
                blocked()
                decisionHandler(.cancel)
            case .cancel: decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            navigationGeneration += 1
            let generation = navigationGeneration
            update(webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak webView] in
                guard let self, let webView,
                      self.navigationGeneration == generation,
                      webView.isLoading else { return }
                self.recover(webView)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            navigationGeneration += 1
            recoveryAttempts = 0
            backHops = 0
            update(webView)
            controller?.clearReturnNotice()
            guard !performedInitialAction else { return }

            if policy.configuration.platform == .instagram,
               initialActionID == "profile" {
                performedInitialAction = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.controller?.openInstagramProfile(
                        fallback: self?.policy.configuration.url(for: "settings")
                    )
                }
                return
            }

            if policy.configuration.platform == .tiktok,
               let initialActionID,
               initialActionID == "messages" || initialActionID == "create",
               webView.url?.path.localizedCaseInsensitiveContains("/login") != true {
                performedInitialAction = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self,
                          let fallback = self.policy.configuration.url(for: initialActionID) else { return }
                    self.controller?.openTikTokUtility(
                        actionID: initialActionID,
                        fallback: fallback
                    )
                }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            handleFailure(error, in: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            handleFailure(error, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            recover(webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mivoClearSingleMedia",
                  let payload = message.body as? [String: Any] else { return }
            if payload["escapedSingleMedia"] as? Bool == true {
                blocked()
                singleMediaPath = nil
                let origin = (payload["origin"] as? String).flatMap(URL.init(string:))
                let destination = policy.configuration.allows(host: origin?.host)
                    ? origin
                    : focusedFallbackURL
                controller?.announceReturn(
                    title: returnNoticeTitle(for: destination),
                    destination: destination
                )
                return
            }
            if policy.configuration.platform == .instagram,
               let rawURL = payload["instagramMediaURL"] as? String,
               let url = URL(string: rawURL),
               policy.configuration.allows(host: url.host),
               MivoClearSingleMediaPolicy.instagramReelIdentifier(in: url.path) != nil {
                controller?.isSingleMediaMode = false
                controller?.presentSingleMedia(url, platform: .instagram)
                return
            }
            if policy.configuration.platform == .instagram,
               let rawURL = payload["instagramVideoSource"] as? String,
               let url = URL(string: rawURL),
               url.scheme?.lowercased() == "https",
               Self.isAllowedInstagramVideoHost(url.host) {
                controller?.isSingleMediaMode = false
                controller?.presentSingleMedia(url, platform: .instagram)
                return
            }
            if policy.configuration.platform == .instagram,
               let active = payload["instagramDirectViewer"] as? Bool {
                controller?.isSingleMediaMode = active
                return
            }
            guard let inlineActive = payload["active"] as? Bool else { return }
            var active = inlineActive
            if !active,
               let url = message.webView?.url,
               let mediaPath = MivoClearSingleMediaPolicy.singleMediaPath(
                    for: url,
                    configuration: policy.configuration
               ) {
                active = singleMediaPath == mediaPath
            }
            controller?.isSingleMediaMode = active
        }

        private func returnNoticeTitle(for destination: URL?) -> String {
            guard let path = destination?.path.lowercased() else { return "Returning" }
            if isInstagramConversationPath(path) { return "Returning to chat" }
            if path.hasPrefix("/direct") { return "Returning to messages" }
            if path.hasPrefix("/messages") || path.hasPrefix("/inbox") { return "Returning to inbox" }
            if path.hasPrefix("/notification") { return "Returning to activity" }
            return "Returning"
        }

        private static func isAllowedInstagramVideoHost(_ rawHost: String?) -> Bool {
            guard let host = rawHost?.lowercased() else { return false }
            return host == "instagram.com"
                || host.hasSuffix(".instagram.com")
                || host == "cdninstagram.com"
                || host.hasSuffix(".cdninstagram.com")
                || host == "fbcdn.net"
                || host.hasSuffix(".fbcdn.net")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if policy.configuration.platform == .instagram,
               MivoClearSingleMediaPolicy.instagramReelIdentifier(in: url.path) != nil {
                controller?.isSingleMediaMode = false
                controller?.presentSingleMedia(url, platform: .instagram)
                return nil
            }
            if let mediaPath = MivoClearSingleMediaPolicy.singleMediaPath(
                for: url,
                configuration: policy.configuration
            ) {
                if singleMediaPath == nil || singleMediaPath == mediaPath {
                    singleMediaPath = mediaPath
                    controller?.isSingleMediaMode = true
                    persistSingleMediaPath(mediaPath, in: webView) {
                        webView.load(MivoClearWebSession.request(url: url, platform: self.policy.configuration.platform))
                    }
                } else {
                    blocked()
                    webView.load(MivoClearWebSession.request(url: focusedFallbackURL, platform: policy.configuration.platform))
                }
                return nil
            }
            switch policy.decision(for: url) {
            case .allow:
                webView.load(MivoClearWebSession.request(url: url, platform: policy.configuration.platform))
            case .redirect(let fallback):
                blocked()
                webView.load(MivoClearWebSession.request(url: fallback, platform: policy.configuration.platform))
            case .external, .cancel:
                blocked()
            }
            return nil
        }

        private func update(_ webView: WKWebView) {
            controller?.canGoBack = webView.canGoBack
            controller?.canGoForward = webView.canGoForward
            controller?.isLoading = webView.isLoading
            controller?.currentURL = webView.url
            controller?.rememberResultsURL(webView.url)
            if let url = webView.url,
               let path = MivoClearSingleMediaPolicy.singleMediaPath(
                    for: url,
                    configuration: policy.configuration
               ) {
                controller?.isSingleMediaMode = singleMediaPath == path
            } else if policy.configuration.platform == .tiktok {
                controller?.isSingleMediaMode = false
            }
        }

        private func handleFailure(_ error: Error, in webView: WKWebView) {
            navigationGeneration += 1
            update(webView)
            let nsError = error as NSError
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            recover(webView)
        }

        private func recover(_ webView: WKWebView) {
            guard recoveryAttempts < 2 else {
                update(webView)
                return
            }
            recoveryAttempts += 1
            navigationGeneration += 1
            let fallback = webView.url ?? policy.configuration.url(for: initialActionID) ?? focusedFallbackURL
            webView.stopLoading()
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(recoveryAttempts) * 0.35) {
                webView.load(
                    MivoClearWebSession.request(
                        url: fallback,
                        platform: self.policy.configuration.platform,
                        forceRefresh: true
                    )
                )
            }
        }

        private var focusedFallbackURL: URL {
            if policy.configuration.platform == .tiktok {
                return policy.configuration.url(for: "profile") ?? policy.configuration.url(for: nil)!
            }
            return policy.configuration.url(for: "messages") ?? policy.configuration.url(for: nil)!
        }

        private func isInstagramConversationPath(_ path: String) -> Bool {
            let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
            return normalized.hasPrefix("/direct/t/")
                || (normalized.hasPrefix("/direct/")
                    && normalized != "/direct"
                    && normalized != "/direct/inbox")
        }

        private func persistSingleMediaPath(_ path: String, in webView: WKWebView, completion: @escaping () -> Void) {
            let key: String
            switch policy.configuration.platform {
            case .instagram: key = "mivo.clear.single.instagram.reel"
            case .tiktok: key = "mivo.clear.single.tiktok.video"
            case .youtube, .snapchat:
                completion()
                return
            }
            guard let data = try? JSONSerialization.data(withJSONObject: [path]),
                  let encoded = String(data: data, encoding: .utf8) else {
                completion()
                return
            }
            webView.evaluateJavaScript(
                "sessionStorage.setItem('\(key)', \(encoded)[0]);"
            ) { _, _ in completion() }
        }
    }
}

struct YouTubeFocusView: View {
    let route: MivoClearRoute
    let configuration: MivoClearPlatformConfiguration

    var body: some View {
        MivoClearYouTubePortalView(route: route, configuration: configuration)
    }
}

private struct YouTubeOfficialPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let video: YouTubeFocusVideo

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundColor(.white).frame(width: 44, height: 44) }
                    Text(video.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Spacer()
                }
                YouTubePlayerWebView(videoID: video.id)
            }
        }
    }
}

private struct YouTubePlayerWebView: UIViewRepresentable {
    let videoID: String
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.limitsNavigationsToAppBoundDomains = true
        let view = WKWebView(frame: .zero, configuration: config)
        if let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1") {
            var request = URLRequest(url: url)
            request.setValue("https://usemivo.app", forHTTPHeaderField: "Referer")
            view.load(request)
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct MivoClearUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "Mivo Clear BETA unavailable",
            systemImage: "exclamationmark.shield.fill",
            description: Text("This platform is paused until its focused filters are ready.")
        )
    }
}
