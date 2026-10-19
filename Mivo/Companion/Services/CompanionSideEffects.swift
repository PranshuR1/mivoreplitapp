import Foundation
import SwiftUI
import UIKit
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Everything the state manager does *outside* its own state: App Group
/// publishing, the shield portrait, widget reloads and notifications. Behind a
/// protocol so the manager's logic is testable without touching any of it.
@MainActor
protocol CompanionSideEffects {
    func publish(snapshot: CompanionSharedSnapshot?, preferences: CompanionPreferences)
    func syncNotifications(preferences: CompanionPreferences, appNotificationsEnabled: Bool)
    func scheduleFocusNudge(text: String, at fireDate: Date)
    func cancelFocusNudge()
}

@MainActor
final class LiveCompanionSideEffects: CompanionSideEffects {
    static let bedtimeNotificationID = "mivo.companion.bedtime"
    static let focusNudgeNotificationID = "mivo.companion.focusNudge"

    private let store = CompanionSharedStore()
    private var lastPublishedSignature: String?

    // MARK: Snapshot + widget

    func publish(snapshot: CompanionSharedSnapshot?, preferences: CompanionPreferences) {
        guard let snapshot, preferences.isActive else {
            store.clear()
            CompanionPortraitRenderer.remove()
            reloadWidgetIfNeeded(signature: "inactive")
            updateLiveActivity(name: nil, state: nil)
            return
        }
        store.write(snapshot)
        updateLiveActivity(name: snapshot.name, state: snapshot.state)
        CompanionPortraitRenderer.refreshIfNeeded()

        // Reloading widget timelines is an IPC round trip. Only do it when
        // something the widget actually shows has changed.
        let signature = [
            snapshot.state, snapshot.name, snapshot.message ?? "", "\(snapshot.pausesToday)",
            "\(snapshot.focusActive)", snapshot.dayKey,
        ].joined(separator: "|")
        reloadWidgetIfNeeded(signature: signature)
    }

    private var lastLiveActivitySignature: String?

    /// A running session / focus Live Activity shows the character; keep it in
    /// step. Only touches ActivityKit when the character actually changed.
    private func updateLiveActivity(name: String?, state: String?) {
        let signature = "\(name ?? "-")|\(state ?? "-")"
        guard signature != lastLiveActivitySignature else { return }
        lastLiveActivitySignature = signature
        FamilyControlsManager.shared.updateLiveActivityCompanion(name: name, state: state)
    }

    private func reloadWidgetIfNeeded(signature: String) {
        guard signature != lastPublishedSignature else { return }
        lastPublishedSignature = signature
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: CompanionSharedKeys.widgetKind)
        #endif
    }

    // MARK: Notifications
    //
    // Companion notifications are opt-in and ride on the notification
    // permission Mivo already asks for elsewhere. This never requests
    // authorization; if it hasn't been granted, nothing is scheduled.

    func syncNotifications(preferences: CompanionPreferences, appNotificationsEnabled: Bool) {
        let center = UNUserNotificationCenter.current()
        guard preferences.isActive, preferences.notificationsEnabled, appNotificationsEnabled,
              preferences.bedtime.isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.bedtimeNotificationID])
            if !(preferences.isActive && preferences.notificationsEnabled && appNotificationsEnabled) {
                center.removePendingNotificationRequests(withIdentifiers: [Self.focusNudgeNotificationID])
            }
            return
        }
        // If bedtime itself falls inside quiet hours the companion is asleep:
        // nothing to announce.
        if preferences.quietHours.isEnabled,
           preferences.bedtime.bedtime.isWithin(start: preferences.quietHours.start, end: preferences.quietHours.end) {
            center.removePendingNotificationRequests(withIdentifiers: [Self.bedtimeNotificationID])
            return
        }
        let bedtime = preferences.bedtime.bedtime
        let text = CompanionMessageProvider.message(
            for: .bedtime,
            personality: preferences.personality,
            context: CompanionMessageContext(companionName: preferences.name)
        ) ?? "\(preferences.name)'s settling down for the night."

        Task {
            guard await Self.isAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Mivo"
            content.body = text
            content.threadIdentifier = "mivo.companion"
            content.interruptionLevel = .passive
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: bedtime.hour, minute: bedtime.minute),
                repeats: true
            )
            center.removePendingNotificationRequests(withIdentifiers: [Self.bedtimeNotificationID])
            try? await center.add(UNNotificationRequest(identifier: Self.bedtimeNotificationID, content: content, trigger: trigger))
        }
    }

    func scheduleFocusNudge(text: String, at fireDate: Date) {
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 5 else { return }
        Task {
            guard await Self.isAuthorized() else { return }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = "Mivo"
            content.body = text
            content.threadIdentifier = "mivo.companion"
            content.interruptionLevel = .passive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.removePendingNotificationRequests(withIdentifiers: [Self.focusNudgeNotificationID])
            try? await center.add(UNNotificationRequest(identifier: Self.focusNudgeNotificationID, content: content, trigger: trigger))
        }
    }

    func cancelFocusNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.focusNudgeNotificationID])
    }

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}

/// Renders the character once into the App Group so the shield-configuration
/// extension (which can only display a bitmap) can show it. Re-rendered only
/// when the artwork version changes.
@MainActor
enum CompanionPortraitRenderer {
    /// Bump when the artwork changes so the shield picks up the new portrait.
    static let version = 1

    static func refreshIfNeeded() {
        let defaults = UserDefaults(suiteName: CompanionSharedKeys.appGroup)
        guard let url = CompanionPortraitFile.url() else { return }
        if defaults?.integer(forKey: CompanionSharedKeys.portraitVersion) == version,
           FileManager.default.fileExists(atPath: url.path) { return }

        let badge = ZStack {
            Circle().fill(Color(red: 0.98, green: 0.97, blue: 0.93))
            Circle().strokeBorder(Color(red: 0.77, green: 0.72, blue: 0.62), lineWidth: 5)
            MeerkatCanvas(pose: MeerkatMotion.staticPose(for: .intervening))
                .padding(.top, 14).padding(.bottom, 10).padding(.horizontal, 12)
        }
        .frame(width: 96, height: 96)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return }
        do {
            try data.write(to: url, options: .atomic)
            defaults?.set(version, forKey: CompanionSharedKeys.portraitVersion)
        } catch {
            // No shared container: the shield keeps its default icon.
        }
    }

    static func remove() {
        if let url = CompanionPortraitFile.url() { try? FileManager.default.removeItem(at: url) }
        UserDefaults(suiteName: CompanionSharedKeys.appGroup)?.removeObject(forKey: CompanionSharedKeys.portraitVersion)
    }
}
