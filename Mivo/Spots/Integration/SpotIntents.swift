import AppIntents
import Foundation

// App Intents are the best way to make a tag tap cost zero extra taps.
//
// A universal-link tag tap makes iOS show a "Open in Mivo" banner the person has
// to tap (background tag reading always asks). A Shortcuts *personal automation*
// triggered by "NFC" can instead run one of these intents immediately, with no
// banner, when "Ask Before Running" is off — iOS lets the person opt into that
// for NFC triggers. Both routes end in the same `SpotManager.handleScan`.

struct SpotEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mivo Spot")
    static var defaultQuery = SpotEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SpotEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SpotEntity] {
        await MainActor.run {
            SpotManager.shared.ensureLoaded()
            return SpotManager.shared.spots
                .filter { identifiers.contains($0.id) }
                .map { SpotEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [SpotEntity] {
        await MainActor.run {
            SpotManager.shared.ensureLoaded()
            return SpotManager.shared.spots
                .filter(\.isEnabled)
                .map { SpotEntity(id: $0.id, name: $0.name) }
        }
    }
}

/// Runs the same path as tapping the Spot's tag: starts it, or ends it if it is
/// already running.
struct ToggleSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "Tap a Mivo Spot"
    static var description = IntentDescription(
        "Starts a Mivo Spot, or ends it if it's already running — the same as tapping its tag."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Spot")
    var spot: SpotEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Tap \(\.$spot)")
    }

    init() {}

    init(spot: SpotEntity) {
        self.spot = spot
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let spotID = spot.id
        let message = await MainActor.run { SpotIntentRunner.toggle(spotID: spotID) }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct EndActiveSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "End my Mivo Spot"
    static var description = IntentDescription("Ends the Mivo Spot that's running now.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { SpotIntentRunner.endActive() }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MivoSpotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleSpotIntent(),
            phrases: [
                "Tap a Spot in \(.applicationName)",
                "Start a Spot in \(.applicationName)"
            ],
            shortTitle: "Tap a Spot",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: EndActiveSpotIntent(),
            phrases: ["End my Spot in \(.applicationName)"],
            shortTitle: "End Spot",
            systemImageName: "stop.circle"
        )
    }
}

/// The intent bodies, kept separate so they run on the main actor and read the
/// outcome from the manager like any other entry point.
@MainActor
enum SpotIntentRunner {
    static func toggle(spotID: String) -> String {
        let manager = SpotManager.shared
        manager.ensureLoaded()
        manager.reconcile()
        let outcome = manager.handleScan(spotID: spotID, trigger: .shortcut)
        defer { manager.notice = nil }
        switch outcome {
        case .started, .notFound, .disabled:
            guard let notice = manager.notice else { return "Done." }
            return [notice.title, notice.message].compactMap { $0 }.joined(separator: ". ")
        case .ended:
            return "Spot ended."
        case .ignoredDuplicate:
            return "That Spot just started."
        }
    }

    static func endActive() -> String {
        let manager = SpotManager.shared
        manager.ensureLoaded()
        manager.reconcile()
        guard let active = manager.activeSession else { return "No Spot is running." }
        manager.end(reason: .endedManually)
        return "\(active.spotName) ended."
    }
}
