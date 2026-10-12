# Screen Time API Setup Guide for Mivo

This guide will help you set up the Screen Time (Family Controls & Device Activity) APIs in your Mivo app.

## Prerequisites

- Xcode 14.0 or later
- iOS 16.0+ target device (Screen Time APIs don't work in Simulator for full functionality)
- Apple Developer account with App IDs configured

## Step 1: Create the Device Activity Monitor Extension

1. In Xcode, go to **File > New > Target**
2. Select **Device Activity Monitor Extension** (under iOS > Application Extension)
3. Name it: `MivoDeviceActivityExtension`
4. Ensure the bundle identifier follows this pattern: `com.yourcompany.mivo.MivoDeviceActivityExtension`
5. Click **Finish** (do NOT activate the scheme when prompted)

## Step 2: Configure App Groups

### In Apple Developer Portal:

1. Go to [developer.apple.com](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select **Identifiers** > **App Groups**
4. Click **+** to create a new App Group
5. Name it: `group.com.mivo.mivoapp` (must match the identifier in code)
6. Click **Register**

### Add App Group to App IDs:

1. Go to **Identifiers** > **App IDs**
2. Select your main app ID (e.g., `com.yourcompany.mivo`)
3. Enable **App Groups** capability
4. Click **Configure** and select `group.com.mivo.mivoapp`
5. Click **Save**
6. Repeat for the extension's App ID (`com.yourcompany.mivo.MivoDeviceActivityExtension`)

## Step 3: Configure Xcode Capabilities

### Main App Target:

1. Select your main app target in Xcode
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability** and add:
   - **Family Controls**
   - **App Groups**
4. In App Groups, add: `group.com.mivo.mivoapp`
5. Ensure **Automatically manage signing** is enabled (or manually select appropriate provisioning profile)

### Extension Target:

1. Select the `MivoDeviceActivityExtension` target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability** and add:
   - **Family Controls**
   - **App Groups**
4. In App Groups, add: `group.com.mivo.mivoapp`
5. Ensure signing is configured

## Step 4: Add the Extension Code

1. Replace the default extension code with the code from `MivoDeviceActivityMonitor.swift`
2. Ensure the file is added to the **extension target** (not the main app target)
3. Update the extension's Info.plist with the provided template

## Step 5: Add Support Files to Main App

Add these files to your **main app target**:
- `ScreenTimeDataCollector.swift`
- Updated `FamilyControlsManager.swift`
- Updated `SettingsView.swift`

## Step 6: Update Deployment Info

### Main App:

1. Select the main app target
2. Go to **General** tab
3. Set **Minimum Deployments** to iOS 16.0 or later (Screen Time APIs require iOS 16+)

### Extension:

1. Select the extension target
2. Set **Minimum Deployments** to iOS 16.0 or later

## Step 7: Build and Run

1. Clean build folder: **Product > Clean Build Folder** (Cmd+Shift+K)
2. Connect a **physical iOS device** (Screen Time APIs don't fully work in Simulator)
3. Select your device in the scheme selector
4. Build and run: **Product > Run** (Cmd+R)

## Step 8: Test the Implementation

1. Launch the app on your device
2. Navigate to **Settings**
3. Tap **"Request Screen Time access"**
4. Grant permission in the system dialog
5. Tap **"Start daily monitoring"**
6. Use your device normally for a while
7. Return to Settings to see the monitoring status and logs

## Troubleshooting

### "App Group not available" error:

**Cause**: The app group isn't properly configured in the provisioning profile.

**Solution**:
1. Delete the app from your device
2. In Xcode, go to **Preferences > Accounts**
3. Select your team and click **Download Manual Profiles**
4. Clean build folder and rebuild
5. Reinstall the app

### Permission dialog not showing:

**Cause**: The Family Controls entitlement isn't properly signed.

**Solution**:
1. Verify Family Controls capability is enabled in both targets
2. Check that you're running on a physical device (not Simulator)
3. Try toggling "Automatically manage signing" off and back on
4. Clean build and reinstall

### Extension not being called:

**Cause**: The extension may not be properly registered with the system.

**Solution**:
1. Verify the extension's bundle identifier is correct
2. Check that the extension target builds successfully
3. Ensure the extension's Info.plist has the correct NSExtensionPointIdentifier
4. Try restarting the device
5. Check extension logs in Settings > Extension logs (debug)

### No data in reports:

**Cause**: The monitoring schedule may not be active, or the extension hasn't written data yet.

**Solution**:
1. Verify monitoring status shows "Active" in Settings
2. Wait for the monitoring interval to complete (end of day)
3. Use the "Simulate device report (debug)" button to test the data flow
4. Check extension logs for errors

## Important Notes

1. **Physical Device Required**: Screen Time APIs have limited functionality in the iOS Simulator. Always test on a real device.

2. **System Delays**: The Screen Time data collection system may have delays. Don't expect instant data updates.

3. **Privacy**: Screen Time data is sensitive. The system enforces strict privacy controls.

4. **App Review**: When submitting to App Store, provide clear explanations of why you need Screen Time access.

5. **Testing**: Use the debug simulate function to test the data flow without waiting for real usage data.

## API Usage Flow

```
1. User grants Family Controls permission (Settings)
   ↓
2. App schedules daily monitoring (FamilyControlsManager)
   ↓
3. System calls extension at interval start/end
   ↓
4. Extension collects data and writes to App Group
   ↓
5. Main app reads data from App Group and displays
```

## Code Structure

```
Main App:
├── FamilyControlsManager.swift      (Authorization & scheduling)
├── ScreenTimeDataCollector.swift    (Data reading & parsing)
├── SettingsView.swift                (UI & user interaction)
└── AppViewModel.swift                (Data management)

Extension:
└── MivoDeviceActivityMonitor.swift  (System callbacks & data collection)

Shared:
└── App Group: group.com.mivo.mivoapp (Data exchange)
```

## Next Steps

Once the basic setup is working:

1. **Enhance Data Collection**: Implement more detailed usage tracking in the extension
2. **Add Visualizations**: Create charts and graphs to show usage patterns
3. **Set Up Notifications**: Alert users when they exceed usage goals
4. **Implement Restrictions**: Use ManagedSettings to block apps when needed
5. **Create Reports**: Generate detailed weekly/monthly usage reports

## Resources

- [Apple Documentation: Family Controls](https://developer.apple.com/documentation/familycontrols)
- [Apple Documentation: Device Activity](https://developer.apple.com/documentation/deviceactivity)
- [WWDC Videos on Screen Time API](https://developer.apple.com/videos/)

## Support

If you encounter issues:
1. Check the extension logs in Settings (debug mode)
2. Run the entitlement diagnostics in Settings
3. Verify all capabilities are properly configured
4. Ensure you're testing on a physical device with iOS 16+
