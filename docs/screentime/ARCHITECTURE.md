# Screen Time API Architecture for Mivo

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS System                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Screen Time Monitoring System               │  │
│  │  (Tracks all device and app usage automatically)         │  │
│  └────────────────┬─────────────────────────────────────────┘  │
│                   │                                             │
│                   │ System Callbacks at Scheduled Intervals     │
│                   │                                             │
└───────────────────┼─────────────────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │   Device Activity Monitor Extension   │
    │   (MivoDeviceActivityMonitor.swift)   │
    │                                       │
    │  • intervalDidStart()                 │
    │  • intervalDidEnd()                   │
    │  • eventDidReachThreshold()           │
    └───────────────┬───────────────────────┘
                    │
                    │ Write usage data
                    ▼
         ┌──────────────────────┐
         │     App Group        │
         │  (Shared Container)  │
         │                      │
         │  • Usage reports     │
         │  • Extension logs    │
         │  • Timestamps        │
         └──────────┬───────────┘
                    │
                    │ Read data
                    ▼
    ┌───────────────────────────────────────┐
    │           Main App                    │
    │                                       │
    │  ┌─────────────────────────────────┐ │
    │  │  FamilyControlsManager          │ │
    │  │  • Request authorization        │ │
    │  │  • Schedule monitoring          │ │
    │  │  • Manage app group access      │ │
    │  └─────────────────────────────────┘ │
    │                                       │
    │  ┌─────────────────────────────────┐ │
    │  │  ScreenTimeDataCollector        │ │
    │  │  • Read from app group          │ │
    │  │  • Parse usage data             │ │
    │  │  • Format reports               │ │
    │  └─────────────────────────────────┘ │
    │                                       │
    │  ┌─────────────────────────────────┐ │
    │  │  UI Views                       │ │
    │  │  • SettingsView                 │ │
    │  │  • ScreenTimeUsageView          │ │
    │  │  • Display data to user         │ │
    │  └─────────────────────────────────┘ │
    └───────────────────────────────────────┘
```

## Data Flow Sequence

```
1. USER ACTION
   User taps "Request Screen Time access"
   │
   ▼
2. AUTHORIZATION
   FamilyControlsManager.requestAuthorization()
   │
   ├──> iOS shows system permission dialog
   │
   └──> User grants permission
        │
        ▼
3. SCHEDULE MONITORING
   User taps "Start daily monitoring"
   │
   ▼
   FamilyControlsManager.scheduleDailyMonitoring()
   │
   ├──> Creates DeviceActivitySchedule (00:00 - 23:59, repeating)
   │
   └──> Calls DeviceActivityCenter.startMonitoring()
        │
        ▼
4. SYSTEM MONITORING (Background)
   iOS monitors all device activity
   │
   ├──> Tracks app usage
   ├──> Tracks screen time
   └──> Tracks device pickups
        │
        ▼
5. INTERVAL CALLBACKS
   At scheduled times, iOS calls extension:
   │
   ├──> intervalDidStart() - Beginning of day (00:00)
   │    └──> Extension resets daily counters
   │
   └──> intervalDidEnd() - End of day (23:59)
        └──> Extension generates report
             │
             ▼
6. DATA WRITING
   Extension writes to App Group:
   │
   ├──> Serializes usage data to JSON
   ├──> Writes to UserDefaults(suiteName: "group.com.mivo.mivoapp")
   └──> Sets key "mivo.lastDeviceActivityReport"
        │
        ▼
7. DATA READING
   Main app reads from App Group:
   │
   ├──> AppViewModel.loadDeviceActivityReport()
   ├──> Reads from shared UserDefaults
   └──> Parses JSON and updates @Published properties
        │
        ▼
8. UI UPDATE
   SwiftUI views automatically update:
   │
   ├──> SettingsView shows report
   ├──> ScreenTimeUsageView shows charts
   └──> User sees their screen time data
```

## Component Responsibilities

### Main App Components

| Component | Responsibility | Key Methods |
|-----------|---------------|-------------|
| **FamilyControlsManager** | Authorization & scheduling | `requestAuthorization()`, `scheduleDailyMonitoring()`, `isMonitoring()` |
| **ScreenTimeDataCollector** | Data retrieval & parsing | `requestTodayUsageData()`, `loadCachedReport()` |
| **AppViewModel** | State management | `loadDeviceActivityReport()`, `startObservingDeviceActivityUpdates()` |
| **SettingsView** | User controls & status | Display monitoring status, start/stop controls |
| **ScreenTimeUsageView** | Data visualization | Charts, insights, app breakdown |

### Extension Components

| Component | Responsibility | Key Methods |
|-----------|---------------|-------------|
| **DeviceActivityMonitor** | System callbacks | `intervalDidStart()`, `intervalDidEnd()` |
| **Extension Logic** | Data collection | Aggregate usage, write to app group |

## Permission & Entitlements

```
Required Entitlements:
├── Main App
│   ├── com.apple.developer.family-controls
│   └── com.apple.security.application-groups
│       └── group.com.mivo.mivoapp
│
└── Extension
    ├── com.apple.developer.family-controls
    └── com.apple.security.application-groups
        └── group.com.mivo.mivoapp

Required Capabilities (Xcode):
├── Family Controls (both targets)
└── App Groups (both targets)

iOS Version Requirement:
└── iOS 16.0 or later
```

## App Group Structure

```
App Group: group.com.mivo.mivoapp
│
├── UserDefaults Keys:
│   ├── "mivo.lastDeviceActivityReport" (String - JSON)
│   ├── "mivo.lastReportTimestamp" (Double - Unix timestamp)
│   ├── "mivo.extensionLogs" ([String] - Debug logs)
│   ├── "mivo.dailyScreenTimeSeconds" (Int - Running total)
│   ├── "mivo.familyControlsAuthorized" (Bool - Cached status)
│   └── "mivo.selectedApps" ([String] - Bundle IDs)
│
└── Example Report JSON:
    {
      "generatedAt": "2026-04-27T14:30:00Z",
      "totalSeconds": 7200,
      "perAppSeconds": {
        "com.apple.Safari": 1800,
        "com.tiktok.ios": 2400,
        "com.instagram.ios": 1500,
        "com.apple.messages": 900,
        "other": 600
      }
    }
```

## State Machine

```
User Permission State:
┌─────────────┐
│  Unknown    │ (Initial state)
└──────┬──────┘
       │
       │ User taps "Request access"
       ▼
┌─────────────┐
│  Requesting │ (System dialog showing)
└──────┬──────┘
       │
       ├──> Granted ──> ┌──────────┐
       │                │Authorized│
       │                └──────────┘
       │
       └──> Denied ──>  ┌──────────┐
                        │  Denied  │
                        └──────────┘

Monitoring State:
┌─────────────┐
│   Inactive  │ (Default)
└──────┬──────┘
       │
       │ User taps "Start monitoring"
       ▼
┌─────────────┐
│   Active    │ (System monitoring)
└──────┬──────┘
       │
       │ User taps "Stop" or error
       ▼
┌─────────────┐
│   Stopped   │
└─────────────┘
```

## Communication Channels

```
Extension → Main App:
└── App Group (UserDefaults)
    ├── Write data
    └── Set timestamps

Main App → Extension:
└── DeviceActivityCenter
    └── Schedule/stop monitoring

iOS System → Extension:
└── Scheduled callbacks
    └── Interval events

iOS System → Main App:
└── Permission dialogs
    └── Authorization results
```

## File Dependencies

```
Main App Build:
├── AppViewModel.swift
│   └── imports: Foundation, SwiftUI
├── FamilyControlsManager.swift
│   └── imports: Foundation, SwiftUI, FamilyControls, DeviceActivity
├── ScreenTimeDataCollector.swift
│   └── imports: Foundation, DeviceActivity, FamilyControls
├── ScreenTimeUsageView.swift
│   └── imports: SwiftUI, DeviceActivity, FamilyControls
│   └── depends on: AppViewModel, ScreenTimeDataCollector
└── SettingsView.swift
    └── depends on: AppViewModel, FamilyControlsManager

Extension Build:
└── MivoDeviceActivityMonitor.swift
    └── imports: Foundation, DeviceActivity, FamilyControls, ManagedSettings
    └── extends: DeviceActivityMonitor
```

## Testing Strategy

```
Level 1: Unit Testing
├── Test FamilyControlsManager authorization flow
├── Test ScreenTimeDataCollector parsing
└── Test ScreenTimeReport model

Level 2: Integration Testing
├── Test app group read/write
├── Test monitoring schedule creation
└── Test data flow end-to-end

Level 3: Manual Testing
├── Test permission dialog flow
├── Test monitoring start/stop
├── Test simulated data injection
└── Test real usage data collection

Level 4: Device Testing
├── Test on multiple iOS versions (16.0+)
├── Test on different device types
└── Test with various app usage patterns
```

## Performance Considerations

```
Extension Lifecycle:
├── System launches extension as needed
├── Extension has limited runtime
├── Must complete work quickly
└── Terminated after callback completes

Main App Performance:
├── Read from app group is fast (UserDefaults)
├── JSON parsing happens off main thread when possible
├── UI updates on main thread via @Published
└── Pull-to-refresh triggers async data fetch

Battery Impact:
├── System handles all monitoring (not app responsibility)
├── Extension runs briefly at scheduled times
├── No continuous background activity from app
└── Minimal battery impact
```

---

This architecture ensures:
- ✅ Clear separation of concerns
- ✅ Efficient data sharing via App Group
- ✅ Minimal main app battery usage
- ✅ Privacy-conscious design
- ✅ System-managed reliability
