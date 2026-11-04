# Mivo Lock-in

Name one thing. Mivo shields the person's chosen apps until they have done it and shown Milo. A friend
(the **keyholder**) can have the last word. It adds no new Screen Time authorization: it shields with a
`ManagedSettingsStore` of its own (`mivo.lockIn`), the same way Still Lock does.

## How a lock ends

| Way | What happens |
| --- | --- |
| Milo is convinced (no active keyholder) | `release(.miloConvinced)` — shield lifted at once. |
| Milo is convinced (active keyholder) | Milo only recommends. The person taps "Ask Dana to unlock"; the keyholder is emailed a link and approves or declines on `usemivo.app/keyholder`. Approval → `release(.keyholderApproved)`. |
| The check-in time passes | `release(.timeRanOut)`, recorded as **not done**. Every lock has one, never more than `LockInKeys.hardCapHours` (12) away, so a lock can't strand anyone. |
| Undo | Only in the first `LockInRules.cancelGrace` (2 min) and only before anything was said to Milo or sent to a keyholder. |

There is deliberately no other way out: a keyholder can't be removed mid-lock, and the chat and the number of
keyholder requests are capped per lock.

## Layout

| Folder | Role |
| --- | --- |
| `Models/LockInShared.swift` | Foundation-only keys and `LockInLiveState`; compiled into the app **and** the shield, shield-action and device-activity extensions. |
| `Models/LockInModels.swift` | `LockIn`, messages, requests, `LockInRules` (every number), `MiloVerdict`. |
| `Services/LockInManager.swift` | The one place a lock starts, is talked about, and ends. Views read it; nothing else shields for Lock-in. |
| `Services/LockInScreenTime.swift` | Shield store, live-state mirror for the extensions, end alarm (DeviceActivity), end notification. Behind a protocol so the manager is testable. |
| `Services/LockInBackend.swift` | Protocol + Supabase client + in-memory double: invite/status/revoke keyholder, request unlock, `reviewProof` (Milo). |
| `Views/` | Entry (`LockInEntryView`), setup flow, active lock, Milo chat, keyholder + "hard to undo" guide, presenter, Home tile, debug preview host. |

Backend: `supabase/migrations/20261025120000_lock_in_keyholder.sql`, `supabase/functions/lockin-keyholder`,
`supabase/functions/lockin-milo`; the keyholder's page is `app/keyholder` in the website repo.

## Where it hooks into Mivo

| Existing code | Lock-in call |
| --- | --- |
| `MainTabView` | `.lockInPresentation()` — Lock-in sheet, wrap-up, foreground reconcile, keyholder polling. |
| `HomeView` Explore grid, Settings → Companion section | `LockInHomeRow`, a "Lock in" row. |
| `MivoApp` `onOpenURL` | `LockInManager.shared.handle(url:)` for `mivo://lockin`. |
| `MivoApp` notification delegate | `mivoRoute == "lockin"` → `LockInKeys.routeChangedNotification`. |
| `AppViewModel.logout` / delete / reset | `signOut()` / `eraseAllData()` — a lock never outlives its account. |
| `MivoShieldConfigurationExtension` / `MivoShieldActionExtension` | "Locked in" shield; "Open Mivo" posts the usual local notification. |
| `MivoDeviceActivityMonitorExtension` | `LockInKeys.endActivityName` alarm lifts the shield at the check-in time. |

## What this can and can't do

- **Milo's judgment is a commitment device, not a security boundary.** It runs server-side (`lockin-milo`,
  Claude Opus 5.5, key as a function secret) and treats the person's words and photos as evidence, never
  instructions — but it can't see the real world. With a keyholder, a human has the last word.
- **Photos** are resized on the phone, shown to the model once, and neither stored nor logged. Only the
  count is kept in the chat. A keyholder is told one sentence of Milo's, never a photo.
- **Mivo can't tell whether the iOS Screen Time lock is on.** "Make it hard to undo" (a Screen Time code a
  friend sets, so Screen Time can't be switched off and Mivo can't be deleted) needs **iOS 26.4+** and is a
  guide plus a self-reported checkbox. Below 26.4 a lock still works, but Settings can switch it off.
- Camera capture isn't offered: the camera permission string is scoped to Mivo Clear. Photos come from the
  library (a screenshot or a photo taken in the Camera app).

## Reviewing without signing in

`-MivoPreviewLockIn <home|setup|active|chat|waiting|wrapup|guide|keyholder>` (debug builds) runs the screens on
scripted state: nothing is shielded and no email is sent. In `chat`, Milo asks for more on the first message and is
convinced on the second. Covered by `MivoClearGuardTests/LockInTests.swift`.
