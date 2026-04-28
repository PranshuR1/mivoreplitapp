import SwiftUI
import UIKit

private let availableApps = [
    "Instagram", "TikTok", "Twitter / X", "YouTube",
    "Reddit", "Facebook", "LinkedIn", "Snapchat", "Pinterest", "Threads"
]

struct OnboardingAppsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: Set<String> = []
    @State private var loading = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("3 of 3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                        .tracking(0.5)
                        .padding(.bottom, 12)

                    Text("Which apps do you scroll most?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                        .lineSpacing(4)
                        .padding(.bottom, 6)

                    // Friendly selection count to help users
                    if !selected.isEmpty {
                        Text("\(selected.count) selected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .padding(.bottom, 8)
                    }

                    Text("Mivo doesn't track apps automatically. This just helps you reflect.")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 24)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        FlowLayout(spacing: 10) {
                            ForEach(availableApps, id: \.self) { app in
                                Button {
                                    if selected.contains(app) { selected.remove(app) }
                                    else { selected.insert(app) }
                                } label: {
                                    HStack(spacing: 6) {
                                        if selected.contains(app) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(MivoColors.accent)
                                        }
                                        Text(app)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(selected.contains(app) ? MivoColors.accent : MivoColors.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selected.contains(app) ? MivoColors.accentMuted : MivoColors.card)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(selected.contains(app) ? MivoColors.accent : MivoColors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 24)

                        Text("You can always change this later in Settings.")
                            .font(.system(size: 13).italic())
                            .foregroundColor(MivoColors.textMuted)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }

                VStack(spacing: 0) {
                    Divider().background(MivoColors.border)

                    // Make the visible button itself a NavigationLink to avoid deprecated programmatic API.
                    NavigationLink {
                        AgeOnboardingView_Internal()
                    } label: {
                        HStack(spacing: 8) {
                            Text("I'm ready")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        loading = true
                        var profile = OnboardingProfile()
                        profile.preferredApps = Array(selected)
                        appVM.saveOnboardingProfile(profile)
                    })
                    .disabled(loading)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .background(MivoColors.background)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
            // Add a Skip action to let users finish onboarding quickly
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Skip") {
                    // Save whatever was selected (if anything) and complete
                    var profile = OnboardingProfile()
                    profile.preferredApps = Array(selected)
                    appVM.saveOnboardingProfile(profile)
                    appVM.completeOnboarding()
                }
                .foregroundColor(MivoColors.textSecondary)
            }
        }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var totalHeight: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            totalHeight += rowHeight
            if i < rows.count - 1 { totalHeight += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if rowWidth + w > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(view)
            rowWidth += w + spacing
        }
        return rows
    }
}

// MARK: - Internal onboarding age/result views (embedded to ensure they're in-scope)

private struct AgeOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var ageText = ""
    @State private var selectedRange: String? = nil
    @State private var appear = false
    @State private var highlightCategory: String? = nil
    @State private var lifeCounts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)? = nil

    private let ranges = ["Under 18", "18-24", "25-34", "35-44", "45-54", "55+"]
    private let lifeExpectancy = 80

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                // Header
                VStack(spacing: 6) {
                    Text("About your age")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Helps Mivo personalize suggestions and lifetime visualizations.")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }

                // Card containing the main input
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(MivoColors.card)
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 4)

                    VStack(spacing: 18) {
                        // Large numeric input (UIKit-backed for smoother typing)
                        ZStack(alignment: .center) {
                            if ageText.isEmpty {
                                Text("Enter your age")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                            NumericTextField(text: $ageText, placeholder: "", fontSize: 40)
                                .frame(height: 64)
                        }
                        .padding(.top, 10)

                        // Age range chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ranges, id: \.self) { r in
                                    Button {
                                        withAnimation(.spring()) { selectedRange = (selectedRange == r ? nil : r) }
                                        HapticsService.impact(style: .medium)
                                    } label: {
                                        Text(r)
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(selectedRange == r ? MivoColors.accent : MivoColors.card)
                                            .foregroundColor(selectedRange == r ? Color.white : MivoColors.textPrimary)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule().stroke(selectedRange == r ? Color.clear : MivoColors.border, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }

                        Text("We’ll use this only to show a personalized life view — you can skip.")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 20)

                Spacer()

                // Primary action
                // Only enable navigation when user has entered an age or selected a range
                let hasSelection = (Int(ageText) ?? 0) > 0 || selectedRange != nil

                NavigationLink {
                    let ageVal = Int(ageText)
                    LifeBreakdownView_Internal(providedAge: ageVal, providedAgeRange: selectedRange)
                } label: {
                    Text("Show my life breakdown")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(hasSelection ? MivoColors.accent : MivoColors.border)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
                .disabled(!hasSelection)
                .simultaneousGesture(TapGesture().onEnded {
                    if hasSelection {
                        var profile = appVM.onboardingProfile
                        if let age = Int(ageText), age > 0 { profile.age = age }
                        profile.ageRange = selectedRange
                        appVM.saveOnboardingProfile(profile)
                        HapticsService.success()
                    }
                })
            }
            .padding(.top, 44)
            .onAppear { appear = true }
        }
        .navigationBarBackButtonHidden()
    }
}

// Full-screen life breakdown view: large grid fills screen; other UI appears after a delay
private struct LifeBreakdownView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Accept explicit provided age/range to avoid reading from appVM too early
    let providedAge: Int?
    let providedAgeRange: String?

    // AI-provided counts (in years) for categories — computed for the visualized life span (boxesCount)
    @State private var lifeCounts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)? = nil
    // Precomputed mapping of each box index to category to avoid recomputing
    @State private var lifeMap: [String] = []

    // visual states
    @State private var started: Bool = false // user pressed "Let's visualize..." -> starts fetch & reveal
    @State private var loading: Bool = false
    @State private var appear = false
    @State private var showDetails = false

    // reveal sequence
    @State private var visibleCells: Int = 0          // how many cells are currently visible in the grid (left->right)
    @State private var highlightedCategory: String? = nil

    // floating textbox while highlighting a category
    @State private var floatingText: String? = nil
    @State private var showFloatingText: Bool = false

    // batch reveal size to reduce frequent UI updates (tuneable)
    private let revealBatchSize = 4

    // computed grid parameters
    private func boxesForAge(_ age: Int?, ageRange: String?) -> Int {
        // Prefer explicit provided age/range over appVM stored values
        if let a = age {
            switch a {
            case 0...17: return 60
            case 18...24: return 60
            case 25...34: return 50
            case 35...44: return 40
            case 45...54: return 30
            default: return 20
            }
        }
        if let range = ageRange {
            switch range {
            case "Under 18": return 60
            case "18-24": return 60
            case "25-34": return 50
            case "35-44": return 40
            case "45-54": return 30
            case "55+": return 20
            default: return 50
            }
        }
        // fallback to stored profile age if nothing provided
        if let storedAge = appVM.onboardingProfile.age { return boxesForAge(storedAge, ageRange: nil) }
        if let storedRange = appVM.onboardingProfile.ageRange { return boxesForAge(nil, ageRange: storedRange) }
        return 50
    }

    // Build an array mapping each year index to a category string based on lifeCounts (order preserved)
    private func buildCategoryMap(for counts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int), totalBoxes: Int) -> [String] {
        var map: [String] = Array(repeating: "free", count: max(0, totalBoxes))
        var idx = 0
        let buckets: [(String, Int)] = [ ("sleep", counts.sleepYears), ("work", counts.workYears), ("eat", counts.eatYears), ("basics", counts.basicsYears), ("scroll", counts.scrollYears), ("free", counts.freeYears) ]
        for (cat, years) in buckets {
            for _ in 0..<max(0, years) {
                if idx >= totalBoxes { break }
                map[idx] = cat
                idx += 1
            }
            if idx >= totalBoxes { break }
        }
        // If anything left, keep as free
        return map
    }

    // Short floating label text for a category using computed counts (e.g., "17 years — Sleeping")
    private func floatingLabelFor(category: String, counts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)) -> String {
        func yrs(_ n: Int) -> String { return "\(n) \(n == 1 ? "year" : "years")" }
        switch category {
        case "sleep": return "\(yrs(counts.sleepYears)) — Sleeping"
        case "work": return "\(yrs(counts.workYears)) — Working"
        case "eat": return "\(yrs(counts.eatYears)) — Eating"
        case "basics": return "\(yrs(counts.basicsYears)) — Basics"
        case "scroll":
            // Prefer explicit user input (minutes/day) when available
            if let minutes = appVM.onboardingProfile.scrollEstimateMinutes, minutes > 0 {
                let hrs = Double(minutes) / 60.0
                return String(format: "On track to spend %.1f hrs/day on your phone", hrs)
            }
            // Fallback: estimate daily hours from the fraction of life spent scrolling
            let boxes = boxesForAge(providedAge, ageRange: providedAgeRange)
            if boxes > 0 {
                let fraction = Double(counts.scrollYears) / Double(boxes)
                let dailyHours = fraction * 24.0
                return String(format: "On track to spend %.1f hrs/day on your phone", dailyHours)
            }
            return "\(yrs(counts.scrollYears)) — Phone Scrolling"
        default: return "\(yrs(counts.freeYears)) — Free time"
        }
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 12)

                Text("Let’s visualize the rest of your life")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text("We’ll show a year-by-year view based on your profile. Tap Next when you’re ready.")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer()

                // Show a preview of how many boxes will be visualized based on age or age range
                let boxes = boxesForAge(providedAge, ageRange: providedAgeRange)
                Text("We’ll show \(boxes) years")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)

                Spacer()

                if !started {
                    Button(action: {
                        started = true
                        loading = true
                        // kick off AI fetch + reveal sequence
                        Task {
                            // call AI to get a life breakdown for the requested number of boxes
                            let counts = await AIService.estimateLifeBreakdown(profile: appVM.onboardingProfile, lifeExpectancy: boxes)

                            // ensure freeYears respects any small rounding differences by forcing sum == boxes
                            var s = counts.sleepYears, w = counts.workYears, e = counts.eatYears, b = counts.basicsYears, sc = counts.scrollYears, f = counts.freeYears
                            let total = s + w + e + b + sc + f
                            if total != boxes {
                                let diff = boxes - total
                                f += diff
                            }
                            lifeCounts = (s,w,e,b,sc,f)

                            // Build category map
                            let map = buildCategoryMap(for: lifeCounts!, totalBoxes: boxes)
                            // Assign to state once so the grid doesn't rebuild the map on every render
                            await MainActor.run {
                                lifeMap = map
                            }

                            // reveal cells left-to-right in batches (reduce main-thread updates)
                            visibleCells = 0
                            highlightedCategory = nil
                            let categoriesOrder = ["sleep","work","eat","basics","scroll","free"]
                            var startIdx = 0
                            for cat in categoriesOrder {
                                let catCount = map.filter { $0 == cat }.count
                                if catCount == 0 { continue }

                                // show floating label for the category
                                if let counts = lifeCounts {
                                    await MainActor.run {
                                        floatingText = floatingLabelFor(category: cat, counts: counts)
                                        showFloatingText = true
                                        highlightedCategory = cat
                                    }
                                }

                                // Reveal in batches to reduce per-frame churn
                                var revealedForCat = 0
                                while revealedForCat < catCount {
                                    let revealNow = min(revealBatchSize, catCount - revealedForCat)
                                    revealedForCat += revealNow
                                    let newVisible = startIdx + revealedForCat
                                    // update visibleCells on main actor once per batch
                                    await MainActor.run {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            visibleCells = newVisible
                                        }
                                    }
                                    // grouped haptic for the batch
                                    HapticsService.impact(style: .medium)
                                    // short pause between batches
                                    try? await Task.sleep(nanoseconds: UInt64(120_000_000)) // 120ms
                                }

                                // after finishing this category, pause before next
                                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000)) // 2s pause between categories

                                // small hide gap for floating label
                                await MainActor.run {
                                    showFloatingText = false
                                }
                                try? await Task.sleep(nanoseconds: UInt64(200_000_000))

                                startIdx += catCount
                            }

                            // reveal complete
                            highlightedCategory = nil
                            showDetails = true
                            loading = false
                        }
                    }) {
                        Text("Next")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 28)
                    }
                    .disabled(loading)
                } else {
                    ZStack(alignment: .top) {
                        // While loading/revealing, show a simplified grid that grows as visibleCells increases
                        GeometryReader { geo in
                            let cols = 10
                            let spacing: CGFloat = 6
                            let total = boxes
                            let cellSize = max(12, (geo.size.width - CGFloat(cols + 1) * spacing) / CGFloat(cols))

                            // Build the category map (defensive when lifeCounts is not yet available)
                            let counts = lifeCounts ?? (sleepYears: 0, workYears: 0, eatYears: 0, basicsYears: 0, scrollYears: 0, freeYears: boxes)
                            let map = lifeMap.isEmpty ? buildCategoryMap(for: counts, totalBoxes: total) : lifeMap

                            ScrollView(.vertical) {
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: cols), spacing: spacing) {
                                    ForEach(0..<total, id: \.self) { idx in
                                        let cat = map[idx]
                                        // cell is visible if idx < visibleCells
                                        let isVisible = idx < visibleCells
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isVisible ? colorForCategory(cat) : MivoColors.card)
                                                .frame(width: cellSize, height: cellSize)
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MivoColors.border, lineWidth: isVisible ? 1 : 0.5))

                                            if isVisible {
                                                Text("—")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .scaleEffect(highlightedCategory == cat && isVisible ? 1.06 : 1.0)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visibleCells)
                                    }
                                }
                                .padding(12)
                                .frame(minHeight: geo.size.height)
                            }
                        }
                        .padding(.horizontal, 8)

                        // Floating label while a category is being revealed
                        if showFloatingText, let text = floatingText {
                            VStack {
                                Text(text)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(BlurView(style: .systemMaterialDark))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 6)
                                    .padding(.top, 12)
                                Spacer()
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.easeOut, value: showFloatingText)
                        }

                        // Legend/key appears only after full reveal; no long descriptive text blocks
                        if showDetails, let counts = lifeCounts {
                            VStack(spacing: 12) {
                                Spacer().frame(height: 16)
                                // Adaptive legend grid so labels don't truncate
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 10) {
                                    legendItem(color: colorForCategory("sleep"), label: "Sleep — \(counts.sleepYears) yrs")
                                    legendItem(color: colorForCategory("work"), label: "Work — \(counts.workYears) yrs")
                                    legendItem(color: colorForCategory("eat"), label: "Eat — \(counts.eatYears) yrs")
                                    legendItem(color: colorForCategory("basics"), label: "Basics — \(counts.basicsYears) yrs")
                                    legendItem(color: colorForCategory("scroll"), label: "Phone — \(counts.scrollYears) yrs")
                                    legendItem(color: colorForCategory("free"), label: "Free — \(counts.freeYears) yrs")
                                }

                                Spacer()

                                // Navigate to the result wheel; pass the provided age/range so the Result view computes remaining years consistently
                                NavigationLink {
                                    ResultOnboardingView_Internal(providedAge: providedAge, providedAgeRange: providedAgeRange)
                                } label: {
                                    Text("Next")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(MivoColors.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .padding(.horizontal, 28)
                                        .padding(.bottom, 40)
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.easeOut, value: showDetails)
                        }
                    }
                }

                Spacer()
            }
            .opacity(appear ? 1 : 0)
            .onAppear {
                appear = true
            }
        }
        .navigationBarBackButtonHidden()
    }

    // Helper to choose a color for a category
    func colorForCategory(_ cat: String) -> Color {
        switch cat {
        case "sleep": return Color(red: 0.91, green: 0.31, blue: 0.35) // red-ish for sleep
        case "work": return MivoColors.accent
        case "eat": return Color(red: 0.96, green: 0.65, blue: 0.22)
        case "basics": return MivoColors.card
        case "scroll": return Color(red: 0.20, green: 0.65, blue: 0.44)
        default: return MivoColors.background
        }
    }
}

private struct ResultOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Accept provided age/range so remaining life matches the visualization
    let providedAge: Int?
    let providedAgeRange: String?

    @State private var estimateMinutes: Int? = nil
    @State private var estimateYears: Double? = nil
    @State private var displayYears: Double = 0.0
    @State private var appear = false
    @State private var spin = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Don’t worry — you can recover time")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)

                Text("We used your answers to estimate how much time per day we can help you save, then converted that into recovered years across your remaining life.")
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                ZStack {
                    Circle()
                        .stroke(MivoColors.border, lineWidth: 14)
                        .frame(width: 300, height: 300)

                    // Draw the arc proportional to yearsRecovered / remainingYears (so wheel reflects years saved)
                    Circle()
                        .trim(from: 0, to: CGFloat(trimFraction()))
                        .stroke(AngularGradient(gradient: Gradient(colors: [MivoColors.accent, MivoColors.accentLight]), center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : -90))
                        .frame(width: 300, height: 300)
                        .animation(.interpolatingSpring(stiffness: 70, damping: 10).speed(0.45), value: estimateYears)

                    VStack(spacing: 6) {
                        // Display animated years number (falls back to estimateYears if displayYears hasn't animated yet)
                        Text((estimateYears != nil || displayYears > 0) ? String(format: "%.2f yrs", displayYears > 0 ? displayYears : (estimateYears ?? 0)) : "—")
                            .font(.system(size: 36, weight: .bold).monospacedDigit())
                            .foregroundColor(MivoColors.textPrimary)
                        Text("estimated recovered time")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textMuted)
                    }
                }
                .padding(8)
                .onTapGesture {
                    // very strong tactile sequence
                    for i in 0..<6 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { HapticsService.impact(style: .heavy) } }
                    withAnimation(.easeOut(duration: 2.0)) { spin.toggle() }
                }

                if let mins = estimateMinutes, let years = estimateYears {
                    Text("We estimate you could save \(mins) minutes per day. That's about \(String(format: "%.2f", years)) years across your remaining life.")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer()

                Button {
                    // Dismiss first, then mark onboarding complete to avoid navigation race conditions
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        appVM.completeOnboarding()
                        // celebratory haptic
                        for i in 0..<5 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) { HapticsService.impact(style: .heavy) } }
                        HapticsService.success()
                    }
                 } label: {
                     Text("Finish setup")
                         .font(.system(size: 16, weight: .semibold))
                         .foregroundColor(.white)
                         .frame(maxWidth: .infinity)
                         .padding(.vertical, 16)
                         .background(MivoColors.accent)
                         .clipShape(RoundedRectangle(cornerRadius: 14))
                 }
                 .padding(.horizontal, 28)
                 .padding(.bottom, 40)
             }
             .opacity(appear ? 1 : 0)
             .onAppear {
                 appear = true
                 computeEstimates()
             }
         }
         .navigationBarBackButtonHidden(true)
    }

    // Compute the trim fraction for the wheel: yearsRecovered / remainingYears (clamped 0..1)
    func trimFraction() -> Double {
        guard let yrs = estimateYears else { return 0.0 }
        let life = 80
        let age = providedAge ?? appVM.onboardingProfile.age ?? 30
        var remaining = Double(life - age)
        if remaining <= 0 { remaining = Double(life) }
        if remaining <= 0 { return 0 }
        return min(1.0, yrs / remaining)
    }

    func computeEstimates() {
        // Use AI service to estimate saved minutes, with fallback to offline heuristic
        let profile = appVM.onboardingProfile
        Task {
            // Get AI estimate (may be remote or offline heuristic inside AIService)
            let aiSaved = await AIService.estimateSavedMinutes(profile: profile)

            // Local heuristic so recovered minutes are always tied to user input
            let scroll = Double(profile.scrollEstimateMinutes ?? 60)
            var multiplier: Double = 0.10
            if !profile.intentions.isEmpty {
                multiplier += Double(min(profile.intentions.count, 4)) * 0.03
                if profile.intentions.contains(.killTime) || profile.intentions.contains(.bored) { multiplier += 0.18 }
                if profile.intentions.contains(.relax) { multiplier += 0.06 }
            }
            multiplier += min(Double(profile.preferredApps.count) * 0.02, 0.12)
            var ageFactor: Double = 1.0
            let ageForFactor = providedAge ?? profile.age ?? 30
            if ageForFactor < 25 { ageFactor = 1.12 }
            else if ageForFactor > 54 { ageFactor = 0.92 }
            else if ageForFactor >= 35 && ageForFactor <= 44 { ageFactor = 0.97 }
            multiplier = max(0.06, min(multiplier, 0.75))
            var heuristicSaved = Int((scroll * multiplier * ageFactor).rounded())
            if let primary = profile.primaryIntention {
                if primary == .killTime || primary == .bored { heuristicSaved += Int(Double(max(heuristicSaved, 1)) * 0.12) }
            }
            if heuristicSaved < 3 { heuristicSaved = 3 }

            // Use the stronger of the AI or heuristic so the recovered time reflects onboarding answers
            var saved = max(aiSaved, heuristicSaved)
            if saved < 3 { saved = 3 }
            if saved > 240 { saved = 240 }

            // Compute years recovered using remaining life based on providedAge (or profile)
            let life = 80
            let age = providedAge ?? profile.age ?? 30
            var remaining = life - age
            if remaining <= 0 { remaining = life }
            let yearsRecovered = (Double(saved) / (60.0 * 24.0)) * Double(remaining)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // animate setting the raw states used by other UI
                withAnimation(.easeOut(duration: 1.6)) { estimateMinutes = saved; estimateYears = yearsRecovered }
                // animate a small numeric count for the years in the wheel center
                displayYears = 0
                let steps = 40
                let duration: Double = 1.4
                for i in 0...steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (duration / Double(steps))) {
                        let pct = Double(i) / Double(steps)
                        displayYears = pct * yearsRecovered
                    }
                }
                // stronger haptics
                for i in 0..<6 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + Double(i) * 0.06) { HapticsService.impact(style: .heavy) } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { HapticsService.success() }

                // save AI summary (include the computed numeric estimates)
                var parts: [String] = []
                if !profile.intentions.isEmpty { let names = profile.intentions.map { $0.rawValue }; parts.append("Intentions: \(names.joined(separator: ", "))") }
                if let s = profile.scrollEstimateMinutes { parts.append("RawEstimate: \(s) min/day") }
                parts.append("PredictedSavedMinPerDay: \(saved)")
                parts.append(String(format: "PredictedRecoveredYears: %.2f", yearsRecovered))
                if let a = profile.age { parts.append("Age: \(a)") }
                let summary = parts.joined(separator: " | ")
                appVM.appendAISummary(summary)
            }
        }
    }
}

// Small UIKit-backed blur wrapper for SwiftUI
private struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    init(style: UIBlurEffect.Style = .systemMaterial) { self.style = style }
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// Lightweight UIKit-backed numeric text field for smoother entry
private struct NumericTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 36

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .center
        tf.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        tf.textColor = UIColor(dynamicColor: MivoColors.textPrimary)
        tf.placeholder = placeholder
        tf.delegate = context.coordinator

        // Add a toolbar with Done button to dismiss number pad
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.doneTapped))
        toolbar.items = [flex, done]
        tf.inputAccessoryView = toolbar

        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        // keep placeholder and font in sync
        uiView.placeholder = placeholder
        uiView.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericTextField
        init(_ p: NumericTextField) { parent = p }

        @objc func editingChanged(_ tf: UITextField) {
            // keep only digits
            let filtered = tf.text?.filter { $0.isNumber } ?? ""
            if filtered != parent.text { parent.text = filtered }
        }

        @objc func doneTapped() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// Helper to convert SwiftUI Color to UIColor safely
private extension UIColor {
    convenience init(dynamicColor color: Color) {
        if #available(iOS 15.0, *) {
            self.init(ciColor: CIColor(color: UIColor(color)))
        } else {
            // Fallback: use fixed color
            let components = UIColor.black.cgColor.components ?? [0,0,0]
            self.init(red: components[0], green: components.count > 1 ? components[1] : 0, blue: components.count > 2 ? components[2] : 0, alpha: 1)
        }
    }
}

// Shared legend item helper view used by multiple onboarding views
@ViewBuilder
private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 18, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(MivoColors.border, lineWidth: 1))
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(MivoColors.textSecondary)
    }
}
