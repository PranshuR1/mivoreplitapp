import Foundation
#if canImport(CoreNFC)
import CoreNFC
#endif

enum SpotNFCError: Error, Equatable {
    /// This device can't read NFC tags (an iPad, an iPhone before the 7, the Simulator).
    case unavailable
    case cancelled
    /// The sticker is read-only, locked, or not NDEF-capable.
    /// Staff programming only.
    case notWritable
    case tooSmall
    case multipleTags
    /// A tag was read, but it doesn't carry a Mivo Spot link.
    case notAMivoSpot
    case failed(String)

    var message: String {
        switch self {
        case .unavailable:
            return "This iPhone can't read NFC tags. You can still start the Spot with its Start button or a Shortcut."
        case .cancelled:
            return "Cancelled."
        case .notWritable:
            return "That sticker can't be written to. It may be locked or not NFC-ready — try a blank NTAG213 or NTAG215 sticker."
        case .tooSmall:
            return "That sticker is too small to hold the Spot link. Try an NTAG213 or larger."
        case .multipleTags:
            return "More than one tag is in range. Hold just one sticker near the top of your iPhone."
        case .notAMivoSpot:
            return "That tag doesn't have a Mivo Spot on it."
        case .failed(let detail):
            return detail.isEmpty ? "Something went wrong reading the tag. Try again." : detail
        }
    }
}

struct SpotTagWriteResult: Equatable {
    /// The sticker's hardware serial as hex, when iOS exposed it.
    var identifier: String?
}

/// Core NFC, used the way iOS allows it.
///
/// What an app can and cannot do with NFC on iPhone:
///
/// - **Read** a tag from inside Mivo: yes, in the foreground, from a system
///   "Ready to Scan" sheet the person starts (`scanSpot`). This is the in-app way
///   to set up or pair a Mivo Spot; everyday use is the tap-the-phone route below.
/// - **Write** a tag: yes, the same way. Customers never do this — official Mivo
///   Spots arrive already programmed. `writeOfficialSpot` exists for Mivo's own
///   staff (the super-admin Spots screen) to program a unit.
/// - **Continuously listen** for tags: no. There is no API for it.
/// - **Be launched** by a tag: yes, but only through *background tag reading*
///   (iPhone XS and later, screen on), which hands the app the tag's URL **only if
///   it is a universal link** the app is associated with. That is why a Spot's tag
///   carries `https://usemivo.app/s/<ID>` and not `mivo://…`. iOS always shows a
///   banner to tap first; an app cannot skip it.
@MainActor
final class SpotNFCService: ObservableObject {
    static let shared = SpotNFCService()

    @Published private(set) var isWorking = false

    #if canImport(CoreNFC)
    private var activeWriter: SpotTagWriter?
    private var activeReader: SpotTagReader?
    #endif

    private init() {}

    /// Whether this device can start an NFC session at all.
    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable && NFCTagReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    /// Programs an official Mivo Spot's URL (`https://usemivo.app/s/<ID>`) onto a
    /// tag held to the phone. Only the ID is written — never any setting. Staff
    /// only: the customer-facing app has no way to reach this.
    func writeOfficialSpot(_ physicalID: String) async throws -> SpotTagWriteResult {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { throw SpotNFCError.unavailable }
        guard let id = PhysicalSpotID.normalize(physicalID) else { throw SpotNFCError.notAMivoSpot }
        isWorking = true
        defer { isWorking = false; activeWriter = nil }
        let writer = SpotTagWriter(url: SpotLink.physicalURL(for: id))
        activeWriter = writer
        return try await writer.run()
        #else
        throw SpotNFCError.unavailable
        #endif
    }

    /// Reads a tag from inside Mivo and returns what its Spot link points at.
    func scanSpot() async throws -> SpotLink.Target {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { throw SpotNFCError.unavailable }
        isWorking = true
        defer { isWorking = false; activeReader = nil }
        let reader = SpotTagReader()
        activeReader = reader
        return try await reader.run()
        #else
        throw SpotNFCError.unavailable
        #endif
    }
}

#if canImport(CoreNFC)

private func mapNFCError(_ error: Error) -> SpotNFCError {
    guard let nfcError = error as? NFCReaderError else { return .failed(error.localizedDescription) }
    switch nfcError.code {
    case .readerSessionInvalidationErrorUserCanceled:
        return .cancelled
    case .readerSessionInvalidationErrorSessionTimeout:
        return .failed("No sticker was found. Hold it near the top of your iPhone and try again.")
    case .readerTransceiveErrorTagConnectionLost:
        return .failed("The sticker moved away too soon. Hold it still and try again.")
    case .readerErrorUnsupportedFeature, .readerErrorSecurityViolation:
        return .unavailable
    default:
        return .failed("")
    }
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

/// One write attempt: poll for an ISO 14443 tag (NTAG and friends), read its
/// serial, check it is writable, write one URI record.
private final class SpotTagWriter: NSObject, NFCTagReaderSessionDelegate {
    private let url: URL
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<SpotTagWriteResult, Error>?
    private let lock = NSLock()
    private var finished = false

    init(url: URL) { self.url = url }

    func run() async throws -> SpotTagWriteResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard let session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil) else {
                finish(.failure(SpotNFCError.unavailable))
                return
            }
            session.alertMessage = "Hold the top of your iPhone near the sticker."
            self.session = session
            session.begin()
        }
    }

    private func finish(_ result: Result<SpotTagWriteResult, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        finish(.failure(mapNFCError(error)))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = SpotNFCError.multipleTags.message
            session.restartPolling()
            return
        }

        let ndefTag: NFCNDEFTag
        let identifier: String?
        switch tag {
        case .miFare(let miFare):
            ndefTag = miFare
            identifier = hexString(miFare.identifier)
        case .iso7816(let iso):
            ndefTag = iso
            identifier = hexString(iso.identifier)
        default:
            session.invalidate(errorMessage: SpotNFCError.notWritable.message)
            finish(.failure(SpotNFCError.notWritable))
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: "Couldn't connect to the sticker. Try again.")
                self.finish(.failure(mapNFCError(error)))
                return
            }
            ndefTag.queryNDEFStatus { status, capacity, error in
                if let error {
                    session.invalidate(errorMessage: "Couldn't read the sticker. Try again.")
                    self.finish(.failure(mapNFCError(error)))
                    return
                }
                guard status == .readWrite else {
                    session.invalidate(errorMessage: SpotNFCError.notWritable.message)
                    self.finish(.failure(SpotNFCError.notWritable))
                    return
                }
                guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: self.url) else {
                    session.invalidate(errorMessage: "Couldn't build the Spot link.")
                    self.finish(.failure(SpotNFCError.failed("Couldn't build the Spot link.")))
                    return
                }
                let message = NFCNDEFMessage(records: [payload])
                guard message.length <= capacity else {
                    session.invalidate(errorMessage: SpotNFCError.tooSmall.message)
                    self.finish(.failure(SpotNFCError.tooSmall))
                    return
                }
                ndefTag.writeNDEF(message) { error in
                    if let error {
                        session.invalidate(errorMessage: "Couldn't write to the sticker. Try again.")
                        self.finish(.failure(mapNFCError(error)))
                    } else {
                        session.alertMessage = "Mivo Spot programmed."
                        self.finish(.success(SpotTagWriteResult(identifier: identifier)))
                        session.invalidate()
                    }
                }
            }
        }
    }
}

/// One read attempt: the first NDEF message carrying a Mivo Spot link wins.
/// Anything else on the tag is ignored.
private final class SpotTagReader: NSObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<SpotLink.Target, Error>?
    private let lock = NSLock()
    private var finished = false

    func run() async throws -> SpotLink.Target {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = "Hold the top of your iPhone near your Mivo Spot."
            self.session = session
            session.begin()
        }
    }

    private func finish(_ result: Result<SpotLink.Target, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Reading one tag ends the session on purpose; the result was already delivered.
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            finish(.failure(SpotNFCError.notAMivoSpot))
            return
        }
        finish(.failure(mapNFCError(error)))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                if let url = record.wellKnownTypeURIPayload(), let target = SpotLink.target(from: url) {
                    finish(.success(target))
                    return
                }
            }
        }
        finish(.failure(SpotNFCError.notAMivoSpot))
    }
}

#endif
