# Screen Time API Setup Checklist

Use this checklist to ensure you've completed all necessary steps to get Screen Time APIs working in Mivo.

## ☑️ Apple Developer Portal

- [ ] Create App Group: `group.com.mivo.mivoapp`
- [ ] Add App Group to main app's App ID (e.g., `com.yourcompany.mivo`)
- [ ] Add App Group to extension's App ID (e.g., `com.yourcompany.mivo.MivoDeviceActivityExtension`)
- [ ] Regenerate provisioning profiles if needed
- [ ] Download updated profiles in Xcode (Preferences > Accounts > Download Manual Profiles)

## ☑️ Xcode - Create Extension Target

- [ ] File > New > Target
- [ ] Select "Device Activity Monitor Extension"
- [ ] Name: `MivoDeviceActivityExtension`
- [ ] Bundle ID: `com.yourcompany.mivo.MivoDeviceActivityExtension`
- [ ] Don't activate scheme when prompted

## ☑️ Xcode - Main App Target

- [ ] Select main app target
- [ ] Go to Signing & Capabilities
- [ ] Add capability: **Family Controls**
- [ ] Add capability: **App Groups**
- [ ] Check `group.com.mivo.mivoapp` in App Groups
- [ ] Verify signing is successful (green checkmark)
- [ ] Set Minimum Deployment to iOS 16.0 (General tab)
- [ ] Add entitlements file: `Mivo.entitlements`

## ☑️ Xcode - Extension Target

- [ ] Select extension target
- [ ] Go to Signing & Capabilities
- [ ] Add capability: **Family Controls**
- [ ] Add capability: **App Groups**
- [ ] Check `group.com.mivo.mivoapp` in App Groups
- [ ] Verify signing is successful
- [ ] Set Minimum Deployment to iOS 16.0 (General tab)
- [ ] Add entitlements file: `MivoDeviceActivityExtension.entitlements`
- [ ] Set Info.plist to `MivoDeviceActivityExtension-Info.plist`

## ☑️ File Organization

### Main App Target Should Include:
- [ ] `FamilyControlsManager.swift` (updated version)
- [ ] `ScreenTimeDataCollector.swift` (new file)
- [ ] `ScreenTimeUsageView.swift` (new file)
- [ ] `SettingsView.swift` (updated version)
- [ ] `AppViewModel.swift` (existing, updated)
- [ ] `Mivo.entitlements`

### Extension Target Should Include:
- [ ] `MivoDeviceActivityMonitor.swift` (new file)
- [ ] `MivoDeviceActivityExtension-Info.plist`
- [ ] `MivoDeviceActivityExtension.entitlements`

### Documentation (not in any target):
- [ ] `SCREENTIME_SETUP_GUIDE.md`
- [ ] `IMPLEMENTATION_SUMMARY.md`
- [ ] `SCREENTIME_CHECKLIST.md` (this file)

## ☑️ Build Configuration

- [ ] Clean build folder (Cmd+Shift+K)
- [ ] Main app target builds successfully
- [ ] Extension target builds successfully
- [ ] No signing errors in either target
- [ ] No entitlement errors in build log

## ☑️ Device Setup

- [ ] Using a **physical iOS device** (not Simulator)
- [ ] Device running iOS 16.0 or later
- [ ] Device is developer-enabled
- [ ] Trust developer certificate on device if needed

## ☑️ Testing - Initial Setup

- [ ] Delete old version of app from device (if exists)
- [ ] Build and run from Xcode
- [ ] App launches successfully
- [ ] Navigate to Settings screen
- [ ] No crash or errors visible

## ☑️ Testing - Authorization

- [ ] Tap "Request Screen Time access"
- [ ] System permission dialog appears
- [ ] Grant permission
- [ ] Status shows "Authorized" in green
- [ ] No error alerts appear

## ☑️ Testing - Monitoring

- [ ] Tap "Start daily monitoring"
- [ ] No error appears
- [ ] Success message shows
- [ ] Monitoring status shows "Active - tracking device usage"
- [ ] Start/Stop buttons appear correctly

## ☑️ Testing - Data Flow (Simulated)

- [ ] Scroll to "Simulate device report (debug)" in Settings
- [ ] Tap the simulate button
- [ ] Action log shows simulation completed
- [ ] "Last device activity report" section updates with JSON
- [ ] "Total today" shows simulated minutes
- [ ] No errors in console

## ☑️ Testing - Extension Logs (Debug)

- [ ] Extension logs section appears in Settings (debug builds)
- [ ] Logs show extension activity
- [ ] Clear button works
- [ ] Timestamps are recent

## ☑️ Testing - Diagnostics

- [ ] Tap "Run entitlement diagnostics"
- [ ] Diagnostics sheet appears
- [ ] Shows "App Group suite available: YES"
- [ ] Shows "Family Controls entitlement: PRESENT"
- [ ] Shows correct App Group identifier
- [ ] Copy to clipboard works

## ☑️ Testing - Real Usage (Wait Time Required)

- [ ] Use device normally for several hours
- [ ] Return to app
- [ ] Check Settings for updated report
- [ ] Verify "Total today" reflects actual usage
- [ ] Check extension logs for interval callbacks

## ☑️ Optional Enhancements

- [ ] Add ScreenTimeUsageView to main navigation
- [ ] Create navigation link in main tab view
- [ ] Add widget support for glanceable screen time
- [ ] Implement push notifications for usage alerts
- [ ] Add weekly/monthly reports
- [ ] Create usage goals and tracking

## ☑️ Pre-Release Checklist

- [ ] Remove or wrap debug features in `#if DEBUG`
- [ ] Test on multiple devices
- [ ] Test with fresh install
- [ ] Test permission denial flow
- [ ] Test with monitoring disabled
- [ ] Verify privacy policy mentions Screen Time data
- [ ] Prepare App Review notes explaining Screen Time usage

## 🚨 Common Issues Reference

| Issue | Symptom | Solution |
|-------|---------|----------|
| App Group not working | "NOT available" in diagnostics | Reinstall app after configuring capabilities |
| Permission dialog missing | Dialog never appears | Must use physical device; check entitlements |
| Extension not called | No logs, no data | Restart device; verify extension builds |
| Signing error | Red X in capabilities | Download profiles; toggle auto-signing |
| No data after hours | Report still empty | Check monitoring status; view extension logs |

## 📞 Getting Help

If you encounter issues:

1. **Check extension logs** in Settings (debug mode)
2. **Run diagnostics** to verify entitlements
3. **Review console logs** in Xcode while app is running
4. **Restart device** - extension registration sometimes requires it
5. **Clean rebuild** - delete app, clean build folder, reinstall

## ✅ Success Criteria

You'll know everything is working when:

- ✅ Permission granted without errors
- ✅ Monitoring status shows "Active"
- ✅ Simulated reports appear correctly
- ✅ Extension logs show interval callbacks
- ✅ Real usage data appears after waiting period
- ✅ ScreenTimeUsageView displays formatted data
- ✅ No crashes or permission errors

---

**Date Completed**: _______________

**Tested By**: _______________

**Notes**: _______________________________________________
