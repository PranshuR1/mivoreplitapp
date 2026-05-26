# Mivo Blocker Fix - Non-Xcode Runtime Support

## Problem Statement

The Mivo app's blocking mechanism only worked when Xcode was running and keeping the app alive. When the app was killed or Xcode stopped, protected apps would not relock at the end of a session because:

1. **In-app timer was the primary blocker**: A `DispatchQueue` timer in `FamilyControlsManager` was responsible for relocking apps, but this only works while the app is in memory.
2. **Device Activity extension was not verified**: No self-test mechanism existed to confirm the extension was actually being called by iOS.
3. **Session activation had no fail-safe**: Sessions could start even if Device Activity monitoring failed to schedule, creating a false sense of security.
4. **No user feedback on blocker health**: Users had no way to know if the blocking mechanism would work without Xcode.

## Solution Overview

The fix makes the **Device Activity Monitor Extension the sole authority** for timed session relocking, with fail-closed behavior when the blocker cannot be verified.

### Key Principles

1. **Fail Closed**: If Device Activity monitoring can't be confirmed, sessions don't start and apps stay blocked
2. **Extension Authority**: Only the Device Activity extension can relock apps after a session timer expires
3. **Self-Test Verification**: Users must verify the extension works before starting timed sessions
4. **Clear User Feedback**: UI shows blocker health status and prevents sessions when not verified

## Changes Made

### 1. FamilyControlsManager.swift

#### A. Made `setMivoSessionActive` return success/failure
```swift
// OLD: func setMivoSessionActive(_ active: Bool, ...)
// NEW: func setMivoSessionActive(_ active: Bool, ...) -> Bool
```

When activating a session:
- Schedules Device Activity monitoring
- Verifies the monitoring is actually active using `DeviceActivityCenter.activities.contains()`
- Returns `false` if monitoring couldn't be confirmed
- Only sets `sessionActive = true` if Device Activity is confirmed

#### B. Removed in-app DispatchQueue timer
```swift
// REMOVED: scheduleSessionRelock(after:) - only worked while app was alive
// REMOVED: sessionRelockWorkItem - in-memory timer that Xcode kept running
```

Added clear comments explaining this was the Xcode-only escape path.

#### C. Added self-test infrastructure
```swift
func runBlockerSelfTest() -> Bool
func markBlockerSelfTestCompleted()
func hasRecentBlockerSelfTestPass() -> Bool
func getBlockerSelfTestDiagnostics() -> String
```

- Schedules a 15-second Device Activity interval
- Extension marks completion via app group UserDefaults
- Check validity within 24 hours
- Provides diagnostic output for debugging

### 2. MivoDeviceActivityMonitor.swift

#### A. Handle session relock on interval end
```swift
override func intervalDidEnd(for activity: DeviceActivityName) {
    if activity.rawValue == "mivo.session.relock" {
        handleSessionRelock()
    }
}

private func handleSessionRelock() {
    // Set sessionActive = false
    // Set pendingInterventionSetup = true
    // Apps remain blocked until user reopens Mivo
}
```

This is the **only** code path that should relock apps when a session timer expires.

#### B. Handle self-test completion
```swift
if activity.rawValue == "mivo.blocker.selftest" {
    handleSelfTestCompletion()
}

private func handleSelfTestCompletion() {
    // Write to app group that test passed
    // Timestamp the callback
}
```

Proves the extension is actually being invoked by iOS.

### 3. AppViewModel.swift

#### A. Added session activation error state
```swift
@Published var sessionActivationError: String? = nil
```

Displays errors when sessions can't start due to blocker verification failure.

#### B. Check self-test before starting sessions
```swift
func markMivoSessionActiveFor(seconds: Int) {
    guard FamilyControlsManager.shared.hasRecentBlockerSelfTestPass() else {
        sessionActivationError = "Screen Time blocker not verified..."
        return
    }
    
    let success = FamilyControlsManager.shared.setMivoSessionActive(true, ...)
    if !success {
        sessionActivationError = "Failed to start session: Device Activity blocker could not be scheduled..."
    }
}
```

Sessions **refuse to start** unless:
1. Self-test passed within last 24 hours
2. Device Activity monitoring successfully scheduled

#### C. Session recovery also checks blocker health
```swift
func recoverExpiredRunningSessionIfNeeded() {
    if remainingSeconds > 0 {
        if FamilyControlsManager.shared.hasRecentBlockerSelfTestPass() {
            let success = FamilyControlsManager.shared.setMivoSessionActive(...)
            if !success {
                // Keep session data but don't unblock apps
            }
        } else {
            // Session data remains but apps stay blocked
        }
    }
}
```

### 4. SettingsView.swift

#### A. Added "Blocker Self-Test" row in Screen Time section
```swift
private var blockerSelfTestRow: some View {
    HStack {
        let hasRecent = FamilyControlsManager.shared.hasRecentBlockerSelfTestPass()
        settingsIcon("shield.checkered", color: hasRecent ? green : orange)
        rowText(
            title: "Blocker self-test",
            subtitle: hasRecent ? "Verified" : "Not verified recently"
        )
        Button("Test") { runBlockerSelfTest() }
        Button(info) { showBlockerDiagnosticsSheet = true }
    }
}
```

Shows:
- Green check if verified within 24 hours
- Orange warning if not verified
- Test button to run verification
- Info button for diagnostics

#### B. Self-test execution flow
```swift
private func runBlockerSelfTest() {
    let success = FamilyControlsManager.shared.runBlockerSelfTest()
    
    if success {
        // Wait 20 seconds, then check if callback received
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            if hasRecentPass {
                // SUCCESS: Extension called back
            } else {
                // FAILURE: No callback, blocker not working
            }
        }
    }
}
```

#### C. Diagnostics sheet
Shows detailed info:
- When test was started
- When callback was received (or "Never")
- Whether test passed
- Whether recent pass is still valid
- Instructions for running test properly

### 5. MivoWidgets.swift

Fixed syntax error in placeholder function (removed corrupted text).

## User Flow

### First-Time Setup
1. User grants Screen Time authorization in Settings
2. User taps "Blocker Self-Test" → "Test" button
3. User **leaves Mivo app** (goes to home screen)
4. User **stops Xcode** if running
5. User waits 15+ seconds
6. User reopens Mivo
7. Settings shows "✅ Verified - blocker is working"

### Starting a Session
1. User tries to start a timed session
2. App checks if self-test passed recently (< 24 hours)
3. If not verified: Shows error "Screen Time blocker not verified. Run the self-test in Settings first."
4. If verified: Attempts to schedule Device Activity monitoring
5. If scheduling fails: Shows error "Failed to start session: Device Activity blocker could not be scheduled. Protected apps will remain locked."
6. If successful: Session starts, apps temporarily unblocked

### Session End (App Not Running)
1. Session timer expires
2. iOS invokes Device Activity Monitor extension
3. Extension's `intervalDidEnd` callback fires
4. Extension sets `sessionActive = false` and `pendingInterventionSetup = true`
5. Apps return to blocked state
6. When user reopens Mivo, they must choose new intention to start another session

## Expected Behavior

### With Xcode Stopped

#### ✅ Correct Behavior
- Self-test passes (extension callback received)
- Sessions start only after verification
- Apps relock at timer end even if app is killed
- User must reopen Mivo to start next session

#### ❌ Failure Mode (Blocker Not Working)
- Self-test does NOT callback
- Sessions refuse to start
- Error message: "Screen Time blocker not verified"
- Protected apps **remain blocked** (fail closed)
- User cannot accidentally bypass blocking

### Provisioning/Entitlement Issues

If the Device Activity extension is not properly registered:
- Self-test will schedule but not callback
- After 20 seconds, test shows failure
- Sessions blocked until issue is resolved
- Diagnostics help identify the problem

## Testing Checklist

### Required Device Setup
- [ ] Physical iOS device (not Simulator)
- [ ] iOS 16.0 or later
- [ ] App signed with proper provisioning profile
- [ ] Family Controls entitlement present
- [ ] App Group configured and shared with extension
- [ ] Device Activity Monitor Extension target built and included

### Self-Test Verification
- [ ] Tap "Test" in Settings
- [ ] Leave Mivo app
- [ ] Stop Xcode completely
- [ ] Wait 20 seconds
- [ ] Reopen Mivo
- [ ] Check Settings shows "✅ Verified"
- [ ] Check diagnostics show completed timestamp

### Session Blocking Without Xcode
- [ ] Run self-test successfully
- [ ] Start 1-minute timed session
- [ ] Open a protected app (should open during session)
- [ ] Kill Mivo app from app switcher
- [ ] Stop Xcode
- [ ] Wait for timer to expire (1+ minute)
- [ ] Try to open protected app again
- [ ] **Expected: App is blocked by shield**
- [ ] Reopen Mivo
- [ ] **Expected: Prompted to start new session**

### Failure Mode Testing
- [ ] Without running self-test, try to start session
- [ ] **Expected: Error message, session doesn't start**
- [ ] **Expected: Protected apps remain blocked**
- [ ] Run self-test, verify it passes
- [ ] Now session can start

### Extension Logs
- [ ] In Settings → Advanced → Extension Logs (debug builds)
- [ ] After self-test, should see:
  - "⏰ Monitoring interval STARTED for activity: mivo.blocker.selftest"
  - "⏰ Monitoring interval ENDED for activity: mivo.blocker.selftest"
  - "✅ SELF-TEST COMPLETED"
- [ ] After session expires, should see:
  - "⏰ Monitoring interval ENDED for activity: mivo.session.relock"
  - "🔒 SESSION RELOCK - Timer ended, relocking protected apps"

## Troubleshooting

### Self-Test Never Passes
**Symptoms**: Test runs but never shows verified status

**Causes**:
1. Extension target not built/included in app bundle
2. Extension Info.plist not configured correctly
3. NSExtensionPrincipalClass not pointing to correct class
4. App Group not shared between app and extension
5. Device needs restart after fresh install

**Solutions**:
- Check extension target builds successfully
- Verify `NSExtension` dictionary in extension's Info.plist
- Confirm principal class: `MivoDeviceActivityMonitorExtension.MivoDeviceActivityMonitor`
- Delete app, clean build folder, reinstall
- Restart device after first install

### Sessions Start But Don't Relock
**Symptoms**: Self-test passes but timer expiry doesn't block apps

**Causes**:
1. Session relock activity name mismatch
2. Extension's `intervalDidEnd` not handling relock case
3. Managed Settings Store not applying shields

**Solutions**:
- Verify activity name "mivo.session.relock" matches in both files
- Check extension logs for "SESSION RELOCK" message
- Ensure `ManagedSettingsStore(named: "mivo.intervention")` is used

### Extension Not Receiving Callbacks
**Symptoms**: Neither self-test nor session relock works

**Causes**:
1. Device Activity framework permission not granted
2. Extension target signing mismatch with app
3. iOS system not loading extension (needs device restart)

**Solutions**:
- Request Family Controls authorization
- Ensure both targets signed with same team/profile
- Restart device after modifying extension
- Check Console app on Mac for system extension errors

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                         Mivo App                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ FamilyControlsManager                                  │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ setMivoSessionActive(true)                         │ │ │
│  │ │ ├─ scheduleSystemSessionRelock()                   │ │ │
│  │ │ │  ├─ DeviceActivityCenter.startMonitoring()       │ │ │
│  │ │ │  └─ Verify .activities.contains(activity)        │ │ │
│  │ │ └─ Returns false if monitoring not confirmed       │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │                                                          │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ runBlockerSelfTest()                               │ │ │
│  │ │ └─ Schedule 15-second DeviceActivity               │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Shared via App Group UserDefaults
                            ├─ mivo.sessionActive
                            ├─ mivo.sessionEndsAt
                            ├─ mivo.blockerSelfTestEnd
                            └─ mivo.blockerSelfTestPassed
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│           Device Activity Monitor Extension                  │
│              (Runs in separate process)                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ MivoDeviceActivityMonitor                              │ │
│  │                                                          │ │
│  │ intervalDidEnd(for activity)                           │ │
│  │ ├─ if activity == "mivo.session.relock"               │ │
│  │ │  └─ handleSessionRelock()                           │ │
│  │ │     ├─ Set sessionActive = false                    │ │
│  │ │     ├─ Set pendingInterventionSetup = true          │ │
│  │ │     └─ Apps return to blocked state                 │ │
│  │ │                                                       │ │
│  │ └─ if activity == "mivo.blocker.selftest"             │ │
│  │    └─ handleSelfTestCompletion()                      │ │
│  │       └─ Mark test passed in app group                │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ System callback even when app killed
                            │ No dependency on main app process
                            ▼
                    ✅ Apps relock reliably
```

## Key Architectural Decisions

1. **No in-app timers for blocking**: All blocking enforcement goes through iOS system callbacks
2. **Fail closed on verification failure**: Better to block unnecessarily than fail to block
3. **24-hour self-test validity**: Balance between security and user convenience
4. **Clear error messages**: Users understand why sessions won't start
5. **Diagnostics visibility**: Debug builds expose extension logs and test results

## Future Considerations

1. **Self-test reminder**: Prompt users to rerun test if stale (> 7 days)
2. **Automatic test on authorization**: Run self-test immediately after granting Screen Time permission
3. **Background test scheduling**: Periodically verify blocker health without user action
4. **Telemetry**: Log self-test pass/fail rates to identify provisioning issues
5. **Extension heartbeat**: More frequent keepalive to detect extension crashes

## Conclusion

This fix ensures Mivo's blocking mechanism works correctly in production without Xcode. The fail-closed approach means users are protected even if the blocker isn't functioning, and the self-test provides clear feedback about system health.

**Critical Success Factors**:
- Self-test must pass before sessions allowed
- Device Activity extension must callback on interval end
- Provisioning/entitlements properly configured
- User understands to stop Xcode when testing

**Failure is now safe**: If anything doesn't work, apps stay blocked and users are informed.
