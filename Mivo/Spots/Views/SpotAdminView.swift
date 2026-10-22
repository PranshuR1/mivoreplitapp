import SwiftUI
import UIKit

/// Manufacturing for Mivo Spots, inside the existing super-admin center.
///
/// The workflow it supports: generate a batch of IDs → program the URLs onto NFC
/// tags before sale (straight from here, one sticker after another; or export
/// `spot_id,url` for a bulk tool) → look up or switch off a Spot later. Customers
/// never see any of this; every call is a super-admin-only RPC (`admin_*_physical_spot*`).
struct AdminSpotsView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var count = 100
    @State private var label = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var generated: AdminGeneratedPhysicalSpots?
    @State private var batches: [AdminPhysicalSpotBatch] = []
    @State private var lookupID = ""
    @State private var found: AdminPhysicalSpot?
    @State private var disableReason = ""
    @State private var programTarget: AdminPhysicalSpotBatch?

    static let countPresets = [25, 50, 100, 250, 500]

    private var canGenerate: Bool {
        !isWorking && (1...5000).contains(count)
    }

    /// What the batch is called when the name field is left empty.
    private var suggestedLabel: String {
        Self.defaultBatchLabel(existing: batches.map(\.label))
    }

    /// The newest batch that still has codes without a sticker.
    private var unfinishedBatch: AdminPhysicalSpotBatch? {
        batches.first { $0.remainingToProgram > 0 }
    }

    var body: some View {
        List {
            if let unfinishedBatch { continueSection(unfinishedBatch) }
            generateSection
            if let generated { resultSection(generated) }
            batchSection
            lookupSection
            if let found { foundSection(found) }
            if let message {
                Section { Text(message).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Mivo Spots")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $programTarget) { batch in
            AdminSpotProgramView(batch: batch, appVM: appVM, autoStart: true)
        }
        .task { await loadBatches() }
        .refreshable { await loadBatches() }
    }

    // MARK: Continue

    private func continueSection(_ batch: AdminPhysicalSpotBatch) -> some View {
        Section {
            NavigationLink {
                AdminSpotProgramView(batch: batch, appVM: appVM, autoStart: true)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue programming").font(.body.weight(.semibold))
                    Text("\(batch.label) · \(batch.remainingToProgram) stickers to go")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Generate

    private var generateSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(Self.countPresets, id: \.self) { preset in
                    Button("\(preset)") { count = preset }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(count == preset ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Stepper(value: $count, in: 1...5000, step: count >= 100 ? 50 : 10) {
                LabeledContent("Spots", value: "\(count)")
            }
            TextField("Batch name (optional) — \(suggestedLabel)", text: $label)
                .textInputAutocapitalization(.sentences)
            Button {
                Task { await generate(startProgramming: true) }
            } label: {
                if isWorking { ProgressView() } else { Label("Generate \(count) & start programming", systemImage: "wave.3.right") }
            }
            .disabled(!canGenerate)
            Button {
                Task { await generate(startProgramming: false) }
            } label: {
                Text("Generate only, export CSV")
            }
            .disabled(!canGenerate)
        } header: {
            Text("Make more Spots")
        } footer: {
            Text("Each Spot gets a random ID and the URL https://usemivo.app/s/<ID>, unclaimed. Nothing about what it does is stored on the tag. Then hold blank stickers to the phone one after another; no codes to type.")
        }
    }

    private func resultSection(_ result: AdminGeneratedPhysicalSpots) -> some View {
        let csv = Self.csv(result.spots.map { ($0.spotId, $0.url, "unclaimed") }, batch: result.label)
        return Section {
            LabeledContent("Batch", value: result.label)
            LabeledContent("Generated", value: "\(result.spots.count)")
            ForEach(result.spots.prefix(5), id: \.spotId) { item in
                Text("\(item.spotId)  →  \(item.url)")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            if result.spots.count > 5 {
                Text("+ \(result.spots.count - 5) more in the export").font(.footnote).foregroundColor(.secondary)
            }
            ShareLink(item: csv, subject: Text("Mivo Spots — \(result.label)")) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = csv
                HapticsService.selection()
            } label: {
                Label("Copy CSV", systemImage: "doc.on.doc")
            }
        } header: {
            Text("New batch")
        } footer: {
            Text("Keep this export. Spot IDs can be listed again below, but this is the file for programming tags.")
        }
    }

    // MARK: Batches

    private var batchSection: some View {
        Section("Batches") {
            if batches.isEmpty {
                Text("No batches yet.").foregroundColor(.secondary)
            }
            ForEach(batches) { batch in
                NavigationLink {
                    AdminSpotBatchView(batch: batch)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batch.label).font(.body.weight(.semibold))
                        Text("\(batch.spotCount) Spots · \(batch.programmedCount ?? 0) on stickers · \(batch.claimedCount) claimed · \(batch.disabledCount) off")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Look up one Spot

    private var lookupSection: some View {
        Section {
            TextField("Spot ID, e.g. A7K92X", text: $lookupID)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Check status") { Task { await lookup() } }
                .disabled(isWorking || PhysicalSpotID.normalize(lookupID) == nil)
        } header: {
            Text("Check a Spot")
        }
    }

    private func foundSection(_ spot: AdminPhysicalSpot) -> some View {
        Section {
            LabeledContent("ID", value: spot.spotId)
            LabeledContent("Status", value: spot.status.capitalized)
            LabeledContent("Batch", value: spot.batchLabel ?? "—")
            LabeledContent("Claimed by", value: spot.ownerEmail ?? "Nobody")
            if let reason = spot.disabledReason, spot.status == "disabled" {
                LabeledContent("Reason", value: reason)
            }
            if spot.status == "disabled" {
                Button("Switch back on") { Task { await setDisabled(spot, disabled: false) } }
                    .disabled(isWorking)
            } else {
                TextField("Reason (optional)", text: $disableReason)
                Button("Switch off", role: .destructive) { Task { await setDisabled(spot, disabled: true) } }
                    .disabled(isWorking)
            }
            if SpotNFCService.isAvailable {
                Button("Program onto an NFC tag") { Task { await writeTag(spot) } }
                    .disabled(isWorking)
            }
        } header: {
            Text("Spot")
        } footer: {
            Text("Switching a Spot off keeps its owner. It stops working in the app until switched back on.")
        }
    }

    // MARK: Actions

    private func generate(startProgramming: Bool) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await appVM.prepareAuthenticatedSession()
            let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await MivoBackendService.adminGeneratePhysicalSpots(
                count: count, label: typed.isEmpty ? suggestedLabel : typed
            )
            generated = result
            label = ""
            HapticsService.success()
            await loadBatches()
            if startProgramming { programTarget = result.batch }
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadBatches() async {
        do {
            try await appVM.prepareAuthenticatedSession()
            batches = try await MivoBackendService.adminPhysicalSpotBatches()
        } catch {
            message = error.localizedDescription
        }
    }

    private func lookup() async {
        guard let id = PhysicalSpotID.normalize(lookupID) else { return }
        isWorking = true
        message = nil
        found = nil
        defer { isWorking = false }
        do {
            try await appVM.prepareAuthenticatedSession()
            found = try await MivoBackendService.adminPhysicalSpotStatus(id: id)
        } catch {
            message = error.localizedDescription.contains("spot_not_found")
                ? "No Spot with that ID."
                : error.localizedDescription
        }
    }

    private func setDisabled(_ spot: AdminPhysicalSpot, disabled: Bool) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await appVM.prepareAuthenticatedSession()
            let reason = disableReason.trimmingCharacters(in: .whitespacesAndNewlines)
            try await MivoBackendService.adminSetPhysicalSpotDisabled(
                id: spot.spotId, disabled: disabled, reason: reason.isEmpty ? nil : reason
            )
            disableReason = ""
            found = try await MivoBackendService.adminPhysicalSpotStatus(id: spot.spotId)
            await loadBatches()
        } catch {
            message = error.localizedDescription
        }
    }

    private func writeTag(_ spot: AdminPhysicalSpot) async {
        message = nil
        do {
            _ = try await SpotNFCService.shared.writeOfficialSpot(spot.spotId)
            message = "Programmed \(spot.url)."
            HapticsService.success()
        } catch let error as SpotNFCError {
            if error != .cancelled { message = error.message }
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Naming

    /// "Batch 21 Oct", then "Batch 21 Oct (2)" … so a second batch on the same day
    /// never needs a name typed in.
    static func defaultBatchLabel(on date: Date = Date(), timeZone: TimeZone = .current, existing: [String]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM"
        let base = "Batch \(formatter.string(from: date))"
        let taken = Set(existing)
        if !taken.contains(base) { return base }
        var number = 2
        while taken.contains("\(base) (\(number))") { number += 1 }
        return "\(base) (\(number))"
    }

    // MARK: CSV

    /// `spot_id,url,status,batch` — the file used to program tags.
    static func csv(_ rows: [(id: String, url: String, status: String)], batch: String) -> String {
        let escapedBatch = "\"" + batch.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let lines = rows.map { "\($0.id),\($0.url),\($0.status),\(escapedBatch)" }
        return (["spot_id,url,status,batch"] + lines).joined(separator: "\n") + "\n"
    }
}

/// Every Spot in one batch, with the same export.
struct AdminSpotBatchView: View {
    let batch: AdminPhysicalSpotBatch
    @EnvironmentObject private var appVM: AppViewModel

    @State private var spots: [AdminPhysicalSpot] = []
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Spots", value: "\(batch.spotCount)")
                LabeledContent("On stickers", value: "\(spots.isEmpty ? batch.programmedCount ?? 0 : spots.filter { $0.programmedAt != nil }.count)")
                LabeledContent("Claimed", value: "\(batch.claimedCount)")
                LabeledContent("Switched off", value: "\(batch.disabledCount)")
                if SpotNFCService.isAvailable {
                    NavigationLink {
                        AdminSpotProgramView(batch: batch, appVM: appVM, autoStart: true)
                    } label: {
                        Label("Program stickers", systemImage: "wave.3.right")
                    }
                }
                if !spots.isEmpty {
                    ShareLink(item: exportText, subject: Text("Mivo Spots — \(batch.label)")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundColor(.secondary) }
            }
            Section("Spots") {
                if isLoading { ProgressView() }
                ForEach(spots) { spot in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.spotId).font(.system(.body, design: .monospaced).weight(.semibold))
                        Text("\(spot.status.capitalized)\(spot.programmedAt == nil ? " · not on a sticker" : " · on a sticker")\(spot.ownerEmail.map { " · \($0)" } ?? "")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(batch.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var exportText: String {
        AdminSpotsView.csv(spots.map { ($0.spotId, $0.url, $0.status) }, batch: batch.label)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await appVM.prepareAuthenticatedSession()
            var all: [AdminPhysicalSpot] = []
            while true {
                let page = try await MivoBackendService.adminListPhysicalSpots(
                    batchID: batch.id, status: nil, limit: 1000, offset: all.count
                )
                all += page.spots
                spots = all
                if page.spots.isEmpty || all.count >= page.total { break }
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Program a whole batch of stickers by holding them to the phone one after another.
/// The next unwritten code is picked automatically; the person never types a code.
struct AdminSpotProgramView: View {
    let batch: AdminPhysicalSpotBatch
    /// Opens the scan sheet as soon as the screen appears, so the first sticker needs no extra tap.
    let autoStart: Bool
    @StateObject private var programmer: SpotBatchProgrammer

    init(batch: AdminPhysicalSpotBatch, appVM: AppViewModel, autoStart: Bool = false) {
        self.batch = batch
        self.autoStart = autoStart
        _programmer = StateObject(wrappedValue: SpotBatchProgrammer(
            batchID: batch.id,
            backend: BackendSpotProgramming(prepare: { try await appVM.prepareAuthenticatedSession() }),
            writer: NFCSpotStickerWriter()
        ))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(programmer.programmed) of \(max(programmer.total, batch.spotCount))")
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text("stickers programmed").font(.footnote).foregroundColor(.secondary)
                    if let last = programmer.lastProgrammed {
                        Text(last)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .padding(.top, 8)
                            .textSelection(.enabled)
                        Text("Last sticker — write this code on its backing card.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if programmer.isFinished {
                    Label("Batch complete", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Button(programmer.isRunning ? "Waiting for a sticker…" : (programmer.unrecorded == nil ? "Start programming" : "Save last code and continue")) {
                        programmer.start()
                    }
                    .disabled(programmer.isRunning)
                }
                if let message = programmer.message {
                    Text(message).font(.footnote).foregroundColor(.secondary)
                }
            } footer: {
                Text("Hold each blank sticker to the top of your iPhone. When it says programmed, the next sticker starts automatically. A sticker that already has a Mivo Spot code is refused and no code is used up. To stop, dismiss the scan sheet.")
            }
        }
        .navigationTitle("Program stickers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoStart else { return }
            // Let the push finish before iOS covers it with the scan sheet.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { programmer.start() }
        }
        .onDisappear { programmer.stop() }
    }
}
