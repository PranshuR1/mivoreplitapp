import SwiftUI

/// The week as a card worth sending: what was kept to, out of what was said.
/// Framed on sessions kept rather than time lost, because people share a week
/// they're a bit proud of, not one that shames them. Rendered to an image for
/// the share sheet; nothing about which videos or people is on it.
struct GapReceiptCard: View {
    let report: AppPurposeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MY \(report.periodName.uppercased()) IN MIVO")
                .font(.system(size: 11, weight: .bold))
                .tracking(11 * 0.14)
                .foregroundColor(MivoColors.inkMuted)

            Text(headline)
                .font(.system(size: 26, weight: .bold))
                .tracking(26 * -0.025)
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 0) {
                ForEach(rows, id: \.label) { row in
                    Rectangle().fill(MivoColors.hairline).frame(height: 1)
                    HStack {
                        Text(row.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.inkBody)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundColor(MivoColors.ink)
                    }
                    .padding(.vertical, 12)
                }
                Rectangle().fill(MivoColors.hairline).frame(height: 1)
            }
            .padding(.top, 20)

            if let finding = report.findings.first {
                Text(finding)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }

            HStack {
                Text("Mivo")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.deep)
                Spacer()
                Text("usemivo.app")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .padding(.top, 22)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(MivoColors.background)
    }

    private var headline: String {
        guard report.keptCandidates > 0 else { return "\(report.sessionCount) sessions, each one on purpose." }
        return "Kept to what I came for in \(report.keptSessions) of \(report.keptCandidates) sessions."
    }

    private struct Row { let label: String; let value: String }

    private var rows: [Row] {
        var rows: [Row] = []
        if let share = report.onPurposeShare {
            rows.append(Row(label: "Time on what I said", value: "\(Int((share * 100).rounded()))%"))
        }
        rows.append(Row(label: "Minutes in social apps", value: "\(report.totalMinutes)"))
        if report.totalShortVideos > 0 {
            rows.append(Row(label: "Short videos", value: "\(report.totalShortVideos)"))
        }
        if report.escapes > 0 {
            rows.append(Row(label: "Went back to studying", value: "\(report.returnedToStudy) of \(report.escapes)"))
        }
        if let better = report.feelingShare(.better), report.answeredFeelings >= 3 {
            rows.append(Row(label: "Came out feeling better", value: "\(Int((better * 100).rounded()))%"))
        }
        return rows
    }
}

/// Preview of the card with the share sheet's button. The image is rendered
/// once, on appear, at the screen's scale.
struct GapReceiptShareView: View {
    let report: AppPurposeReport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GapReceiptCard(report: report)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(MivoColors.hairline, lineWidth: 1)
                        )

                    if let image {
                        ShareLink(
                            item: image,
                            preview: SharePreview("My \(report.periodName) in Mivo", image: image)
                        ) {
                            Label("Share my \(report.periodName)", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .background(MivoColors.background.ignoresSafeArea())
            .navigationTitle("Your \(report.periodName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: render)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: GapReceiptCard(report: report))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}

extension AppPurposeReport {
    /// What the range is called on the card: the Patterns tab shows 7 or 30 days.
    var periodName: String { days <= 7 ? "week" : "month" }
}
