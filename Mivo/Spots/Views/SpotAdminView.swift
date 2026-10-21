import SwiftUI
import UIKit

/// Manufacturing for Mivo Spots, inside the existing super-admin center.
///
/// The workflow it supports: generate a batch of IDs → export `spot_id,url` → program
/// the URLs onto NFC tags before sale (with a bulk tool, or one at a time from here)
/// → look up or switch off a Spot later. Customers never see any of this; every
/// call is a super-admin-only RPC (`admin_*_physical_spot*`).
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

    private var canGenerate: Bool {
        !isWorking && !label.trimmingCharacters(in: .whitespaces).isEmpty && (1...5000).contains(count)
    }

    var body: some View {
        List {
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
        .task { await loadBatches() }
        .refreshable { await loadBatches() }
    }

    // MARK: Generate

    private var generateSection: some View {
        Section {
            Stepper(value: $count, in: 1...5000, step: count >= 100 ? 50 : 10) {
                LabeledContent("Spots", value: "\(count)")
            }
            TextField("Batch name, e.g. Launch run 1", text: $label)
                .textInputAutocapitalization(.sentences)
            Button {
                Task { await generate() }
            } label: {
                if isWorking { ProgressView() } else { Text("Generate \(count) Mivo Spots") }
            }
            .disabled(!canGenerate)
        } header: {
            Text("Generate a batch")
        } footer: {
            Text("Each Spot gets a random ID and the URL https://usemivo.app/s/<ID>, unclaimed. Nothing about what it does is stored on the tag.")
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
                        Text("\(batch.spotCount) Spots · \(batch.claimedCount) claimed · \(batch.disabledCount) off")
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

    private func generate() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await appVM.prepareAuthenticatedSession()
            generated = try await MivoBackendService.adminGeneratePhysicalSpots(
                count: count, label: label.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            HapticsService.success()
            await loadBatches()
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
                LabeledContent("Claimed", value: "\(batch.claimedCount)")
                LabeledContent("Switched off", value: "\(batch.disabledCount)")
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
                        Text("\(spot.status.capitalized)\(spot.ownerEmail.map { " · \($0)" } ?? "")")
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
