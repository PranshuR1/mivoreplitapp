# Mivo — iOS Native App

> See the Pattern. Break the Loop.

A native iOS app built in Swift/SwiftUI, converted from the original Expo/React Native implementation. All data is stored locally on-device using UserDefaults.

---

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 15.0+ |
| iOS Deployment Target | 17.0+ |
| Swift | 5.9+ |
| macOS | 13.0+ (Ventura) |

---

## Getting Started

1. **Open in Xcode**
   ```
   open mivoreplitapp.xcodeproj
   ```

2. **Select a simulator or device** from the scheme picker (top-left toolbar)

3. **Set your Team** (for device builds only):
   - Go to `Mivo` target → Signing & Capabilities → Team

4. **Run** with `Cmd + R`

---

## Project Structure

```
Mivo/
├── mivoreplitapp.xcodeproj/   Xcode project file
└── Mivo/
    ├── MivoApp.swift           App entry point + RootView router
    ├── Info.plist              App configuration
    ├── Assets.xcassets/        App icon, accent colour, logo image
    ├── Constants/
    │   └── Colors.swift        Brand colours (#E7D6C4 bg, #C97942 accent, #4A2E1F brand)
    ├── Models/
    │   └── Models.swift        Session, UserProfile, FocusRecommendation, etc.
    ├── ViewModels/
    │   └── AppViewModel.swift  Central app state (auth, sessions, onboarding)
    ├── Services/
    │   ├── StorageService.swift UserDefaults CRUD helpers
    │   └── AIService.swift     AI integration + offline rule-based engine
    ├── Components/
    │   └── MivoComponents.swift Shared UI: MivoButton, MivoCard, MivoLogo, etc.
    └── Views/
        ├── Auth/               LoginView, RegisterView
        ├── Onboarding/         Welcome → Why → Calibration → Apps (3-step flow)
        ├── Tabs/               HomeView, PatternsView, InterventionsView, SettingsView
        ├── Session/            ActiveSessionView, ReflectionView
        ├── Focus/              FocusView (AI coach + mode selector), FocusTimerView
        ├── MainTabView.swift   Tab bar container
        ├── InterventionView.swift  5-second mindful pause
        └── WeeklyReportView.swift  7-day summary with insights
```

---

## Features

### All Screens
- **Login / Register** — Local auth, email + password, stored in UserDefaults
- **Onboarding** — 3-step flow: Why you scroll → Estimate daily time → Pick your apps
- **Home** — Today's scroll time, session count, week-over-week pattern, reflection journal
- **Patterns** — Interactive month calendar, day-by-day session detail, insights
- **Interventions** — Session starter: pick intention + duration → delay pause → active timer
- **Settings** — Profile, stats, export data, weekly report, sign out, reset data
- **Active Session** — Countdown timer with colour interpolation, over-limit detection, one-time extension
- **Reflection** — Post-session check-in with optional note, saves to session history
- **Focus Mode** — 5 focus modes (Classic, Adaptive, Open, Micro, Academic) with full configuration
- **AI Focus Coach** — Online API + offline rule-based recommendation engine (works with no network)
- **Intervention Pause** — 5-second mindful delay with rotating prompts
- **Weekly Report** — 7-day summary: total time, sessions, avg length, over-limit %, insights

### AI Focus Recommendations (Offline-Capable)
Mivo includes a fully offline AI engine in `AIService.swift`. It uses a rule-based system that mirrors the server logic:

| Focus Level | Time Available | Recommended Mode |
|-------------|---------------|-----------------|
| ≤ 2 | Any | Micro (7 min) |
| ≥ 4 | ≥ 50 min | Classic (50–60/5–10) |
| 3 | ≥ 30 min | Adaptive (10 min start) |
| ≥ 3 | Intended ≥ 25 | Academic (25/5 sprints) |
| Default | Any | Classic (25/5) |

To enable the **online API**, add your server's base URL to `Info.plist` under the key `AI_API_BASE_URL`. If the key is empty or the network call fails, the app silently falls back to the offline engine.

---

## Adding the Logo

Place your `mivo_logo.png` file at:
```
Mivo/Assets.xcassets/MivoLogo.imageset/mivo_logo.png
```

If no image is found, the app shows a fallback feather SF Symbol. The logo automatically clips to a rounded rectangle at any size.

---

## Branding

| Role | Hex | Usage |
|------|-----|-------|
| Background | `#E7D6C4` | App background |
| Accent | `#C97942` | Buttons, selections, highlights |
| Brand | `#4A2E1F` | Logo text, header |
| Card | `#F3F3F3` | Card backgrounds |
| Text Secondary | `#9C8573` | Subtitles, labels |
| Timer Green | `#6B8C6B` | Early session |
| Timer Orange | `#C97942` | Mid session |
| Timer Red | `#B05540` | Overtime |

---

## Authentication

Auth is fully local — no backend required:
- Passwords are hashed with a simple djb2-style hash (same algorithm as the Expo app's AsyncStorage implementation)
- Credentials and session tokens are stored in `UserDefaults`
- No data ever leaves the device unless you configure `AI_API_BASE_URL`

---

## Slogan

> **See the Pattern. Break the Loop.**
> *Pause. Choose. Scroll on your terms.*
