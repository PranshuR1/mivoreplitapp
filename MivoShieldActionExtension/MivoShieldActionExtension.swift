import FamilyControls
import Foundation
import ManagedSettings

final class MivoShieldActionExtension: ShieldActionDelegate {
    private let appGroup = "group.com.mivo.mivoapp"
    private let selectionKey = "mivo.familyActivitySelection"
    private let protectionEnabledKey = "mivo.impulseProtectionEnabled"
    private let signedInKey = "mivo.impulseProtectionSignedIn"
    private let sessionActiveKey = "mivo.sessionActive"
    private let sessionEndsAtKey = "mivo.sessionEndsAt"
    private let pendingInterventionSetupKey = "mivo.pendingInterventionSetup"
    private let countdownUntilKey = "mivo.shieldCountdownUntil"
    private let countdownRemainingKey = "mivo.shieldCountdownRemaining"
    private let countdownDuration: TimeInterval = 5
    private let interventionRelockDelay: TimeInterval = 2
    private let sessionRelockDelay: TimeInterval = 90
    private let store = ManagedSettingsStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            if isInterventionSetupPending() {
                completionHandler(.close)
                return
            }
            beginCountdown {
                if self.isSessionActive() {
                    self.unlock(application: application, relockDelay: self.sessionRelockDelay, requestSetupOnRelock: false)
                } else {
                    self.unlock(application: application, relockDelay: self.interventionRelockDelay, requestSetupOnRelock: true)
                }
            }
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            if isInterventionSetupPending() {
                completionHandler(.close)
                return
            }
            beginCountdown {
                if self.isSessionActive() {
                    self.unlock(category: category, relockDelay: self.sessionRelockDelay, requestSetupOnRelock: false)
                } else {
                    self.unlock(category: category, relockDelay: self.interventionRelockDelay, requestSetupOnRelock: true)
                }
            }
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            if isInterventionSetupPending() {
                completionHandler(.close)
                return
            }
            beginCountdown {
                if self.isSessionActive() {
                    self.unlock(webDomain: webDomain, relockDelay: self.sessionRelockDelay, requestSetupOnRelock: false)
                } else {
                    self.unlock(webDomain: webDomain, relockDelay: self.interventionRelockDelay, requestSetupOnRelock: true)
                }
            }
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    private func beginCountdown(_ open: @escaping () -> Void) {
        let endTime = Date().addingTimeInterval(countdownDuration).timeIntervalSince1970
        updateCountdownDisplay(remaining: Int(countdownDuration), endTime: endTime)

        for second in 1..<Int(countdownDuration) {
            let remaining = Int(countdownDuration) - second
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(second)) {
                self.updateCountdownDisplay(remaining: remaining, endTime: endTime)
                self.apply(selection: self.loadSelection())
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + countdownDuration, execute: open)
    }

    private func updateCountdownDisplay(remaining: Int, endTime: TimeInterval) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(endTime, forKey: countdownUntilKey)
        defaults?.set(remaining, forKey: countdownRemainingKey)
        defaults?.synchronize()
    }

    private func unlock(application: ApplicationToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        var selection = loadSelection()
        selection.applicationTokens.remove(application)
        apply(selection: selection)
        scheduleRelock(after: relockDelay)
    }

    private func unlock(category: ActivityCategoryToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        var selection = loadSelection()
        selection.categoryTokens.remove(category)
        apply(selection: selection)
        scheduleRelock(after: relockDelay)
    }

    private func unlock(webDomain: WebDomainToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        var selection = loadSelection()
        selection.webDomainTokens.remove(webDomain)
        apply(selection: selection)
        scheduleRelock(after: relockDelay)
    }

    private func loadSelection() -> FamilyActivitySelection {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }

        return selection
    }

    private func apply(selection: FamilyActivitySelection) {
        let defaults = UserDefaults(suiteName: appGroup)
        guard defaults?.bool(forKey: protectionEnabledKey) == true,
              defaults?.bool(forKey: signedInKey) == true else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            return
        }

        guard !isSessionActive() else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            return
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func scheduleRelock(after delay: TimeInterval) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.removeObject(forKey: countdownUntilKey)
        defaults?.removeObject(forKey: countdownRemainingKey)
        defaults?.synchronize()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.apply(selection: self.loadSelection())
        }
    }

    private func requestInterventionSetup() {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(true, forKey: pendingInterventionSetupKey)
        defaults?.removeObject(forKey: countdownUntilKey)
        defaults?.removeObject(forKey: countdownRemainingKey)
        defaults?.synchronize()
    }

    private func isInterventionSetupPending() -> Bool {
        UserDefaults(suiteName: appGroup)?.bool(forKey: pendingInterventionSetupKey) == true
    }

    private func isSessionActive() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.bool(forKey: sessionActiveKey) else {
            return false
        }

        let endsAt = defaults.double(forKey: sessionEndsAtKey)
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            defaults.set(false, forKey: sessionActiveKey)
            defaults.removeObject(forKey: sessionEndsAtKey)
            defaults.synchronize()
            return false
        }

        return true
    }
}
