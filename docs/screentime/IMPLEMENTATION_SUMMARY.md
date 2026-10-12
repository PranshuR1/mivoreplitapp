# Screen Time API Implementation - Quick Reference

## ✅ What's Been Done

### 1. **Core Manager Updates**
- **FamilyControlsManager.swift** - Enhanced with:
  - `scheduleDailyMonitoring()` - Now properly schedules DeviceActivity monitoring
  - `stopMonitoring()` - Stop active monitoring
  - `isMonitoring()` - Check monitoring status
  - Proper error handling and completion callbacks

### 2. **New Files Created**

#### MivoDeviceActivityMonitor.swift
- Device Activity Monitor extension implementation
- Handles interval start/end callbacks from the system
- Collects usage data and writes to App Group
- Logs all activities for debugging

#### ScreenTimeDataCollector.swift  
- Helper class for reading screen time data
- Parses and structures usage reports
- Provides ScreenTimeReport model with:
  - Total usage time
  - Per-app breakdown
  - Top apps ranking
  - Formatted duration helpers

#### ScreenTimeUsageView.swift
- Beautiful SwiftUI view to display screen time data
- Shows total usage, app breakdown, and insights
- Compares actual usage vs user estimates
- Pull-to-refresh support

#### Setup Documentation
- **SCREENTIME_SETUP_GUIDE.md** - Complete setup instructions
- **MivoDeviceActivityExtension-Info.plist** - Extension configuration template

### 3. **Enhanced UI**
- **SettingsView.swift** updated with:
  - Real-time monitoring status display
  - Start/Stop monitoring controls
  - Extension logs viewer (debug mode)
  - Better error messages and user guidance
  - Total usage display from reports

## 🚀 How to Complete Setup

### Required Steps in Xcode:

1. **Create Device Activity Extension Target**
   ```
   File > New > Target > Device Activity Monitor Extension
   Name: MivoDeviceActivityExtension
   ```

2. **Configure App Groups**
   - Create `group.com.mivo.mivoapp` in Apple Developer Portal
   - Add to both main app and extension App IDs
   - Enable in Xcode capabilities for both targets

3. **Enable Family Controls**
   - Add capability to both main app and extension targets
   - Ensure proper code signing

4. **Add Files to Correct Targets**
   - Main app: ScreenTimeDataCollector.swift, ScreenTimeUsageView.swift, updated managers
   - Extension: MivoDeviceActivityMonitor.swift
   - Extension Info.plist: MivoDeviceActivityExtension-Info.plist

5. **Test on Physical Device**
   - Screen Time APIs require a real iOS device (iOS 16+)
   - Clean build and reinstall

## 📱 User Flow

```
1. Settings → Request Screen Time access
   ↓ (System permission dialog)
2. Grant permission
   ↓
3. Start daily monitoring
   ↓
4. System calls extension at intervals
   ↓
5. View usage in Settings or new ScreenTimeUsageView
```

## 🔧 Testing

### Debug Features:
- **Simulate device report** - Test data flow without real usage
- **Extension logs** - See what the extension is doing
- **Diagnostics** - Check entitlements and provisioning
- **Monitoring status** - Real-time active/inactive indicator

### Quick Test Checklist:
- [ ] Permission dialog appears when requested
- [ ] Permission granted successfully
- [ ] Monitoring starts without errors
- [ ] Status shows "Active - tracking device usage"
- [ ] Extension logs show interval callbacks
- [ ] Simulated report appears in Settings
- [ ] ScreenTimeUsageView displays data

## 🐛 Common Issues & Solutions

### "App Group not available"
→ Reinstall app after configuring App Group in capabilities

### Permission dialog doesn't appear
→ Must test on physical device, not Simulator

### Extension not called
→ Check extension target builds, Info.plist is correct, and device has been restarted

### No data in reports
→ Wait for interval to complete, or use "Simulate device report" for testing

## 📊 What the APIs Do

### Family Controls
- Authorization for Screen Time access
- Required permission for all Screen Time features

### Device Activity
- **DeviceActivityCenter** - Schedule monitoring intervals
- **DeviceActivityMonitor** - Extension receives callbacks
- **DeviceActivityReport** - Visual reports (optional)

### Data Flow
```
iOS System → Extension → App Group → Main App
           (writes)   (UserDefaults) (reads)
```

## 🎯 Next Steps

1. **Follow SCREENTIME_SETUP_GUIDE.md** for detailed setup
2. **Create the extension target** in Xcode
3. **Configure capabilities** in both targets
4. **Test on physical device** with iOS 16+
5. **Integrate ScreenTimeUsageView** into your main navigation

## 💡 Usage Examples

### Schedule monitoring:
```swift
FamilyControlsManager.shared.scheduleDailyMonitoring { result in
    switch result {
    case .success:
        print("Monitoring started!")
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

### Read usage data:
```swift
ScreenTimeDataCollector.shared.requestTodayUsageData { result in
    switch result {
    case .success(let report):
        print("Total: \(report.formattedDuration())")
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

### Check authorization:
```swift
if FamilyControlsManager.shared.cachedAuthorizationStatus() == true {
    // User has granted permission
}
```

## 📚 Resources

- Full setup guide: `SCREENTIME_SETUP_GUIDE.md`
- Apple Docs: [FamilyControls](https://developer.apple.com/documentation/familycontrols)
- Apple Docs: [DeviceActivity](https://developer.apple.com/documentation/deviceactivity)

---

**Important**: All Screen Time features require iOS 16+ and a physical device. The Simulator has very limited support for these APIs.
