import SwiftUI

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Screen Time Usage View
// Displays screen time usage data in a user-friendly format

@available(iOS 16.0, *)
struct ScreenTimeUsageView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var report: ScreenTimeReport?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("Screen Time Today")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                    
                    if isLoading {
                        // Loading state
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let error = errorMessage {
                        // Error state
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundColor(MivoColors.textSecondary)
                                .multilineTextAlignment(.center)
                            Button(action: loadReport) {
                                Text("Retry")
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(MivoColors.accentLight)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let report = report {
                        // Data display
                        totalTimeCard(report: report)
                        
                        if !report.topApps.isEmpty {
                            appBreakdownSection(report: report)
                        }
                        
                        comparisonCard(report: report)
                    } else {
                        // No data state
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 40))
                                .foregroundColor(MivoColors.textSecondary)
                            Text("No usage data available yet")
                                .font(.system(size: 15))
                                .foregroundColor(MivoColors.textSecondary)
                            Text("Start monitoring in Settings to see your screen time")
                                .font(.system(size: 13))
                                .foregroundColor(MivoColors.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .onAppear {
            loadReport()
        }
        .refreshable {
            await refreshReport()
        }
    }
    
    // MARK: - Components
    
    private func totalTimeCard(report: ScreenTimeReport) -> some View {
        VStack(spacing: 16) {
            // Large time display
            VStack(spacing: 4) {
                Text(report.formattedDuration())
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Total screen time today")
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            
            // Stats row
            HStack(spacing: 0) {
                statCell(
                    value: "\(report.topApps.count)",
                    label: "Apps used"
                )
                Divider()
                    .frame(height: 40)
                    .background(MivoColors.border)
                statCell(
                    value: report.totalMinutes > 0 ? "\(report.totalMinutes)" : "0",
                    label: "Minutes"
                )
                Divider()
                    .frame(height: 40)
                    .background(MivoColors.border)
                statCell(
                    value: String(format: "%.1f", report.totalHours),
                    label: "Hours"
                )
            }
        }
        .padding(20)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MivoColors.border, lineWidth: 1)
        )
    }
    
    private func appBreakdownSection(report: ScreenTimeReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Apps")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
            
            VStack(spacing: 0) {
                ForEach(Array(report.topApps.prefix(10).enumerated()), id: \.offset) { index, app in
                    appRow(
                        bundleID: app.bundleID,
                        seconds: app.seconds,
                        totalSeconds: report.totalSeconds,
                        rank: index + 1
                    )
                    
                    if index < min(9, report.topApps.count - 1) {
                        Divider()
                            .background(MivoColors.border)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MivoColors.border, lineWidth: 1)
            )
        }
    }
    
    private func appRow(bundleID: String, seconds: Int, totalSeconds: Int, rank: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .frame(width: 24)
            
            // App name
            VStack(alignment: .leading, spacing: 2) {
                Text(appName(from: bundleID))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.textPrimary)
                Text(bundleID)
                    .font(.system(size: 11))
                    .foregroundColor(MivoColors.textMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Time and percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(seconds: seconds))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                if totalSeconds > 0 {
                    let percentage = Double(seconds) / Double(totalSeconds) * 100
                    Text(String(format: "%.0f%%", percentage))
                        .font(.system(size: 11))
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func comparisonCard(report: ScreenTimeReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(MivoColors.accentLight)
                Text("Insights")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }
            
            // Compare with user's estimate
            if let estimate = appVM.onboardingProfile.scrollEstimateMinutes {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your estimate")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textSecondary)
                        Text("\(estimate) min")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(MivoColors.textMuted)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actual today")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textSecondary)
                        Text("\(report.totalMinutes) min")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(report.totalMinutes > estimate ? .red : MivoColors.accentLight)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(MivoColors.border, lineWidth: 1)
                )
            }
            
            // General insight
            Text(generateInsight(report: report))
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(MivoColors.border, lineWidth: 1)
                )
        }
    }
    
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helpers
    
    private func loadReport() {
        isLoading = true
        errorMessage = nil
        
        ScreenTimeDataCollector.shared.requestTodayUsageData { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let fetchedReport):
                    self.report = fetchedReport
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func refreshReport() async {
        await withCheckedContinuation { continuation in
            loadReport()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
    
    private func appName(from bundleID: String) -> String {
        // Try to extract a readable name from bundle ID
        // In a real implementation, you might want to use a mapping or query the system
        let components = bundleID.split(separator: ".")
        if let last = components.last {
            return String(last).capitalized
        }
        return bundleID
    }
    
    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func generateInsight(report: ScreenTimeReport) -> String {
        let hours = report.totalHours
        
        if hours < 1 {
            return "Great job! You're using your device mindfully today."
        } else if hours < 2 {
            return "You're keeping your screen time under control."
        } else if hours < 4 {
            return "Consider taking breaks to reduce screen fatigue."
        } else if hours < 6 {
            return "Your screen time is quite high today. Try setting limits."
        } else {
            return "Very high screen time detected. Consider reducing usage for better well-being."
        }
    }
}

// MARK: - Preview

@available(iOS 16.0, *)
struct ScreenTimeUsageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScreenTimeUsageView()
                .environmentObject(AppViewModel())
        }
    }
}
