# Mivo Companion

A small meerkat (default name **Milo**) that gives Mivo's existing pauses a quiet presence. It adds
no Screen Time monitor, schedule or enforcement of its own — it only reads what Mivo already knows
and reports what Mivo's existing flows already did. With Companion off, every entry point is a no-op.

## Defaults and pacing

Companion is on by default but stays inactive until the person finishes the privacy introduction;
until then Home shows a "Meet Milo" tile that opens it. Pacing is set in
`CompanionInterventionFrequency` (balanced: 8-minute gap, 12 lines a day, 10-minute rest after a
pause) and `CompanionThresholds`. A pause screen ignores the gap (45-second floor, daily cap still
applies). When nothing stands out, Home and the widget show a passive `.ambient` hello that changes
with the hour; it is never counted as speech and never appears on a pause screen.

## Layout

| Folder | Role |
| --- | --- |
| `Models/` | Value types: `CompanionState` (11 states), `CompanionAnimation`, `CompanionPersonality`, `CompanionPreferences`, `CompanionRuntime`, `CompanionProgress`, `CompanionSignals`, `CompanionSharedSnapshot`. |
| `Services/CompanionBehaviorEngine` | Pure function: `CompanionSignals` + `CompanionPreferences` → `CompanionBehaviorResult` (state, animation, message topic, severity, recommendation, cooldown). No UI, no storage, no clock. |
| `Services/CompanionStateManager` | The only place companion state is decided and stored. Views read `presentation`. |
| `Services/CompanionMessageProvider` | All copy. Personality changes copy only. |
| `Services/CompanionSideEffects` | App Group snapshot, widget reloads, shield portrait, opt-in notifications — behind a protocol so the manager is testable. |
| `Integration/` | The two seams to existing Mivo code (below). |
| `Views/` | Companion screen, settings, onboarding, pause accessory, the meerkat figure. |

## Where it hooks into Mivo

| Existing code | Companion call |
| --- | --- |
| `AppViewModel.recordInterventionAttempt` / `resolveInterventionAttempt` | `CompanionInterventionAdapter.pauseBegan()` / `pauseResolved(continued:)` |
| `InterventionFlowView.pauseStep`, `MidScrollCheckInView` | `CompanionPauseAccessory` (character + at most one line; no new actions) |
| `MivoStillViews` | `focusBegan(endsAt:)` / `focusEnded(completed:)` |
| `MainTabView` (foreground, background, once a minute) | `CompanionDeviceActivityAdapter.sync(with:)` |
| `AppViewModel.handleDeepLink` (`mivo://companion`) | `CompanionStateManager.requestOpen()` |
| `AppViewModel.logout` | `prepare(forEmail: nil)` clears the widget snapshot |
| Settings → Progress & tools, Home | `CompanionEntryView`, `CompanionHomeRow` |
| `MivoShieldConfigurationExtension` (default shield only) | Reads the portrait PNG the app renders into the App Group |
| `MivoWidgets/CompanionWidget.swift` | Reads `CompanionSharedSnapshot` from the App Group |

## What iOS lets Mivo know (and what it doesn't)

Used: Screen Time authorization, whether apps are selected, today's total from Mivo's existing
DeviceActivity report, the adaptive daily target, recorded daily observations (for "longer than
usual", after five days of history), Mivo's pause log, Still/Lock Mode state, late-night protection,
time of day, bedtime and quiet hours.

**Not available, and never claimed:** how many times an app was opened, how long the current
continuous session has been, which app is on screen, or anything about content. These fields do not
exist in `CompanionSignals`; add one only when Mivo can fill it truthfully. The Companion screen shows
which of the available signals are missing (`CompanionDataLimit`).

No floating overlay, private API or new entitlement is used. The App Group
(`group.com.mivo.mivoapp`) was already configured for the app, widget and shield extension.

## Live Activities / Dynamic Island

iOS has no way to draw a character over other apps, so the companion is visible outside Mivo only
through Apple's sanctioned surfaces. Companion reuses Mivo's existing session Live Activity
(`MivoSessionLiveAttributes`, behind the existing `liveActivities` rollout flag) instead of adding a
second one:

- It starts only for a real timed event: a Mivo scroll session, or a Mivo Still run
  (`kind == "focus"`, which hides the Finish / Add time actions that only make sense for a scroll session).
- When Companion is on, `ContentState.companionName` / `companionState` make the Lock Screen,
  compact and minimal Dynamic Island show the meerkat's face (`MeerkatHeadBadge`) in the state's
  resting pose. Live Activities can't run custom animation.
- `LiveCompanionSideEffects` pushes state changes into a running activity, and drops the character
  if Companion is switched off.
- There is deliberately no always-on activity just to keep the character visible.

## Adding a character

1. Add a case to `CompanionType` and set `isAvailable` (it is hidden from Settings until then).
2. Add its artwork in `CompanionArtworkRegistry` (`Views/CompanionArtwork.swift`).
3. Give it a `defaultName`. Nothing in the engine, persistence or widget needs to change.

## Replacing the vector artwork

Drop images named `companion_meerkat_<state>` (for example `companion_meerkat_sleeping`) into
`Assets.xcassets`. They are picked up per state automatically; states without an image keep the
vector figure. Bump `CompanionPortraitRenderer.version` if the shield portrait should change.

## Project membership

`ruby scripts/add_companion_files.rb` adds every file under `Mivo/Companion/` to the Mivo target, the
five Foundation/SwiftUI-only files to the widget target, and the tests to `MivoClearGuardTests`. It is
idempotent; re-run it after adding files.
