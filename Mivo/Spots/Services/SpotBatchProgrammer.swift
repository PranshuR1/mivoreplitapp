import Foundation

/// Programming a batch of Mivo Spot stickers one after another (staff only).
///
/// Each round: ask the backend for the next code that is not on a sticker yet,
/// write it to the sticker held to the phone, read it back, and record that it is
/// done — then straight on to the next. The person only holds stickers to the phone.
///
/// The hard rule is that a code is never handed out twice. So:
/// - A sticker that already carries a Mivo Spot code is refused and **no code is
///   used up**; the next sticker gets that code.
/// - If a code was written but recording it failed (no internet), the run stops and
///   that code is remembered. Starting again records it first, before any new code,
///   so it can't end up on a second sticker.

struct SpotProgrammingNext: Equatable {
    /// nil when every code in the batch is on a sticker.
    var spotID: String?
    var programmed: Int
    var total: Int
}

protocol SpotProgrammingBackend: AnyObject {
    func next(batchID: String) async throws -> SpotProgrammingNext
    func markProgrammed(_ spotID: String) async throws
}

@MainActor
protocol SpotStickerWriting: AnyObject {
    /// Writes the code to a sticker and verifies it. Never overwrites a sticker that
    /// already carries a Mivo Spot code (throws `SpotNFCError.alreadyProgrammed`).
    func program(_ spotID: String, prompt: String) async throws
}

@MainActor
final class SpotBatchProgrammer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var programmed = 0
    @Published private(set) var total = 0
    /// The code that just went onto a sticker, so it can be labelled.
    @Published private(set) var lastProgrammed: String?
    @Published private(set) var message: String?
    @Published private(set) var isFinished = false
    /// Written to a sticker but not yet recorded. Recorded first on the next run.
    @Published private(set) var unrecorded: String?

    private let batchID: String
    private let backend: SpotProgrammingBackend
    private let writer: SpotStickerWriting
    private let pause: () async -> Void
    private var task: Task<Void, Never>?

    static let recordAttempts = 3

    init(
        batchID: String,
        backend: SpotProgrammingBackend,
        writer: SpotStickerWriting,
        pause: @escaping () async -> Void = { try? await Task.sleep(nanoseconds: 1_200_000_000) }
    ) {
        self.batchID = batchID
        self.backend = backend
        self.writer = writer
        self.pause = pause
    }

    func start() {
        guard !isRunning else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
    }

    /// Runs until the batch is done, the person stops, or something needs attention.
    /// Exposed for tests; the UI calls `start()`.
    func run() async {
        isRunning = true
        message = nil
        defer { isRunning = false }

        do {
            if let pending = unrecorded {
                try await record(pending)
            }
            while !Task.isCancelled {
                let next = try await backend.next(batchID: batchID)
                programmed = next.programmed
                total = next.total
                guard let id = next.spotID else {
                    isFinished = true
                    message = total == 0 ? "This batch has no codes." : "All \(total) stickers are programmed."
                    return
                }

                do {
                    try await writer.program(id, prompt: "Sticker \(programmed + 1) of \(total)")
                } catch SpotNFCError.alreadyProgrammed(let existing) {
                    // Not a blank sticker. Nothing was written, so no code is used up.
                    message = "That sticker is already programmed as \(existing). Use a blank one."
                    await pause()
                    continue
                }

                unrecorded = id
                lastProgrammed = id
                try await record(id)
                await pause()
            }
            message = "Stopped."
        } catch SpotNFCError.cancelled {
            message = "Stopped."
        } catch let error as SpotNFCError {
            message = error.message
        } catch {
            message = unrecorded == nil
                ? error.localizedDescription
                : "Code \(unrecorded ?? "") is on a sticker but couldn't be saved. Check your connection and start again — don't use that sticker for another code."
        }
    }

    /// Records a code as done, retrying briefly: losing this would let the code be
    /// handed out again.
    private func record(_ id: String) async throws {
        var lastError: Error?
        for attempt in 0..<Self.recordAttempts {
            do {
                try await backend.markProgrammed(id)
                unrecorded = nil
                programmed += 1
                return
            } catch {
                lastError = error
                if attempt < Self.recordAttempts - 1 { await pause() }
            }
        }
        throw lastError ?? SpotNFCError.failed("")
    }
}

// MARK: - Real implementations

final class BackendSpotProgramming: SpotProgrammingBackend {
    private let prepare: () async throws -> Void

    /// `prepare` refreshes the sign-in before each call (`appVM.prepareAuthenticatedSession`).
    init(prepare: @escaping () async throws -> Void) { self.prepare = prepare }

    func next(batchID: String) async throws -> SpotProgrammingNext {
        try await prepare()
        let next = try await MivoBackendService.adminNextUnprogrammedPhysicalSpot(batchID: batchID)
        return SpotProgrammingNext(spotID: next.spotId, programmed: next.programmed, total: next.total)
    }

    func markProgrammed(_ spotID: String) async throws {
        try await prepare()
        try await MivoBackendService.adminMarkPhysicalSpotProgrammed(id: spotID)
    }
}

@MainActor
final class NFCSpotStickerWriter: SpotStickerWriting {
    func program(_ spotID: String, prompt: String) async throws {
        _ = try await SpotNFCService.shared.writeOfficialSpot(spotID, overwrite: false, prompt: prompt)
    }
}
