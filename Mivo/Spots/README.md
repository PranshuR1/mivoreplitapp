# Mivo Spots

A Spot is a place — a desk, a bedside, the car — with its own way of nudging you toward using your phone on purpose. Tapping a **Mivo Spot** (the physical product) starts it; tapping it again (or the timer, or **End Spot**) ends it. Spots add friction and awareness; they never lock you out.

## The physical product

Mivo sells NFC **Mivo Spots**. Each is programmed by Mivo before it ships with one URL, `https://usemivo.app/s/<ID>`, and nothing else — no apps, timer, name or user data. A customer never programs anything.

1. Mivo generates IDs (random, 8 chars, unambiguous alphabet) in the Admin Center → **Spots**, or from SQL: `select * from public._generate_physical_spots(100, 'Batch 1');`
2. Mivo exports `spot_id,url,status,batch` and programs the URLs onto tags (bulk tool, or one at a time from the same Admin screen). Tags may be write-locked.
3. The customer taps the Mivo Spot. Mivo reads the ID and asks the backend what it is to them:

| Backend says | The person sees |
| --- | --- |
| `unclaimed` | "Meet your new Mivo Spot" → connect to an existing setup (if they have Digital Spots) or name → apps → behavior → done. The claim happens when they confirm the last step, atomically; leaving earlier leaves it unclaimed. |
| `yours` (new phone, data cleared) | The same setup, on this phone. |
| set up on this phone | **Starts the Spot immediately** — no setup, no picker, no network. Tap again (after 4 s) ends it. |
| `taken` | "This Mivo Spot is already connected to another account." Nothing about the owner is ever returned. |
| `disabled` | "This Mivo Spot is switched off." |
| `invalid` | "We couldn't find this Mivo Spot." |

After the first setup the flow shows **Skip the banner** (`SpotInstantSteps`): the four Shortcuts steps (NFC trigger → *Tap a Mivo Spot* → Run Immediately) that make a tap start the Spot with no banner. iOS offers no other way; the same steps are on each Mivo Spot's page.

Logged out: the ID is kept (30 min) and the flow continues after sign-in. Changing a Spot's name, icon, apps, mode or duration never touches the Mivo Spot, so a Study Spot can become a Sleep Spot.

**Where things live.** The backend (Supabase `physical_spots`, only reachable through security-definer RPCs) knows `spot_id`, owner, status, claimed/created timestamps. The Spot's configuration stays on the phone as before (`MivoSpot`, per account) with a `PhysicalSpotLink` pointing at the ID. `SpotManager` re-checks the backend at most every 15 min: a Spot Mivo switched off stops working; one released elsewhere becomes a Digital Spot.

**Digital Spots.** A `MivoSpot` with no `physical` link is a "Digital Spot": it runs from its Start button or a Shortcut. Spots made by the first version (including ones with a self-written sticker, `/spot/<uuid>`) are Digital Spots that keep working, and can be connected to a Mivo Spot later without rebuilding them.

**Official vs. blank tags.** The app can't write tags for customers any more, and an ID only counts if it exists in the backend and is unclaimed. Verification is "the ID exists" for now; `SpotRegistry` is the seam where stronger tag authentication (signed URLs, NTAG 424 DNA) can be added without touching the rest.

## Layout

| Folder | Role |
| --- | --- |
| `Models/SpotShared.swift` | **Foundation-only, compiled into the app and the three Screen Time extensions.** `SpotKeys`, `SpotMode`, `SpotLiveState` (the live block the extensions read), `SpotUsageLadder` (usage-event naming). |
| `Models/MivoSpot.swift` | `MivoSpot`, `SpotAppSelection`, `SpotTagBinding`, icons, templates, formatting. |
| `Models/SpotSession.swift` | `SpotSession`, `SpotCompletionReason`, `SpotTrigger`, usage and intention records. |
| `Models/SpotLink.swift` | The identification layer: `https://usemivo.app/s/<ID>` (official) and the first version's `/spot/<uuid>` (still honoured), plus `mivo://` equivalents. |
| `Models/PhysicalSpot.swift` | `PhysicalSpotLink`, `PhysicalSpotID`, what the backend can say about an ID, claim errors and their copy. |
| `Models/SpotInsights.swift` | Pure analytics: totals, average, most-used Spot, and the one comparison. |
| `Services/SpotManager` | The only place Spot state is decided. List, the one running session, history, start/end rules, timers. |
| `Services/SpotScreenTime` | The boundary to `ManagedSettings` / `DeviceActivity` (behind `SpotScreenTimeControlling`, so the rules are testable). |
| `Services/SpotNFCService` | Core NFC read (customers) and write (Mivo staff only, from the Admin screen). |
| `Services/SpotRegistry` | `SpotRegistry`: resolve / claim / release / list against the Mivo backend, plus an in-memory double for tests. |
| `Services/SpotPersistence` | `StorageService`, per account. |
| `Integration/SpotIntents` | App Intents: tap/end a Spot from Shortcuts or Siri. |
| `Integration/SpotsPresenter` | The single seam into `MainTabView` (`.spotsPresentation()`). |
| `Views/` | List, setup/claim flow, "Connect a Mivo Spot" sheet, detail, active, summary, shield prompts, tap confirmation, `SpotAdminView` (super-admin manufacturing). `SpotPreviewHost` (DEBUG) renders each screen from a launch argument. |

## Where it hooks into existing Mivo code

| Existing code | Spots call |
| --- | --- |
| `AppViewModel.handleDeepLink` | `SpotManager.shared.handle(url:)` first (called from `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`) |
| `MivoBackendService` | Spot RPCs (`resolve_physical_spot`, `claim_physical_spot`, …) and the `admin_*_physical_spot*` RPCs |
| `AdminCenterView` | **Spots** tab → `AdminSpotsView` |
| `AppViewModel.logout` / `deleteAccount` / `resetAllData` | `signOut()` / `eraseAllData()` |
| `MainTabView` | `.spotsPresentation()` (account binding, tap confirmation, shield prompts, summary, 30 s reconcile) |
| `MivoApp` notification delegate | `mivoRoute == "spot"` → `mivoSpotRequested` |
| `HomeView`, `InterventionsView` (Protect) | `SpotsEntryRow`, `SpotActiveBanner` |
| `MivoShieldConfigurationExtension` | Spot copy for the Spot's own apps |
| `MivoShieldActionExtension` | Spot taps → pending route + "Open Mivo" notification |
| `MivoDeviceActivityMonitorExtension` | `mivo.spot.end`, `mivo.spot.relock`, usage thresholds |
| `FamilyControlsManager` | Authorization status, Live Activity (Focus mode, behind the `liveActivities` flag) |
| `StorageService` | Three `StorageKey`s, scoped per account |

Spots uses its own named `ManagedSettingsStore` (`mivo.spot`), exactly as Still Lock and cross-device focus do, so ending a Spot can never clear another feature's shield.

## The four modes

| Mode | Shield | What the person sees |
| --- | --- | --- |
| Mivo Pause | Spot's apps | Shield → *Open Mivo* → the existing breathing stage (`PauseBreathingStage`, same length as the shield pause) → open for 5/10/15 min, then it pauses again. |
| Focus Session | Spot's apps, for the whole timer | Shield says how long is left and points to Mivo, where the Spot can be ended. |
| Intention Check | Spot's apps until answered | "What did you come here to do?" — once. Answering lifts the shield for the rest of the Spot. |
| Awareness Only | none | Nothing blocked; usage is recorded and summarised. |

## What iOS does and doesn't allow

These are limits of iOS, not of Mivo. Nothing here is faked.

**NFC**
- An app **cannot listen** for tags continuously. There is no API.
- An app **can write** a tag (foreground, system "Ready to Scan" sheet) and **read** one from inside the app. Both use `NFCTagReaderSession` / `NFCNDEFReaderSession`.
- A tag can **launch** Mivo only through *background tag reading* (iPhone XS or later, screen on). iOS hands the app the tag's URL **only if it is a universal link** the app is associated with. A `mivo://` URL on a tag is not routed to the app. So a Mivo Spot carries `https://usemivo.app/s/<ID>` (`applinks:usemivo.app` is in the entitlements; the association file claims `/s/*`).
- iOS **always shows a banner** to tap when a tag is read in the background. An app cannot skip it. The only zero-tap route is a **Shortcuts automation** (NFC trigger → *Run Immediately*) running the `Tap a Spot` App Intent. Both routes end in `SpotManager.handleScan`.
- iPhone 7, 8 and X can't read in the background: use Control Center's tag reader or **Scan a Spot** in the app.
- The Simulator has no NFC. `SpotNFCService.isAvailable` is false there and the UI says so.

**Screen Time**
- Apple gives apps **opaque tokens**, not bundle IDs; they are device-specific, and a name is not guaranteed (`localizedDisplayName` may be nil). The app list is drawn with Apple's `Label(token)`.
- `FamilyActivityPicker` does not work in the Simulator.
- There is **no API to read an app's usage live**. The only supported route is `DeviceActivityEvent` thresholds: the monitor extension is woken when cumulative use of the Spot's apps crosses a step (1, 2, 3, 5, 7, 10 … 180 min for the Spot; 1, 3, 5 … 120 min per app) and Mivo keeps the highest step reached. **Reported times are therefore floors, in steps — "close, not exact"** — and say so on screen.
- Per-app times are measured for at most **4 apps** per Spot (`SpotUsageLadder.maxTrackedApps`); further apps count toward the Spot total only. Total events per Spot ≤ 56.
- If Screen Time access is off, a Spot still runs and keeps time, but cannot shield or measure; the summary says "not measured" rather than showing 0.
- A shield extension **cannot open Mivo**. Like the existing flows it records the request and posts an "Open Mivo" notification; the tap on the shield's button is one step, and the notification is a second. This is how every Mivo shield flow already works.
- A Spot's end is guaranteed three ways: an in-process timer, a `DeviceActivity` alarm that wakes the monitor extension at the end time (works with Mivo closed), and a reconcile on foreground.

**Deliberate limits**
- One Spot runs at a time; starting another ends the first.
- A Spot with no timer ends itself after 12 hours (`SpotKeys.openEndedCapHours`), so a forgotten Spot can't keep apps shielded.
- A tap delivered twice within 4 s is ignored, so one tap can't start then end a Spot.
- The tag stores only the Spot ID. A Mivo Spot can't be duplicated by the customer: an ID has to exist in the backend and be unclaimed. Disconnecting a Mivo Spot (or deleting its Spot) releases the ID so it can be set up again or passed on.
- Everyday taps work offline once a Mivo Spot is set up on the phone; first scans, claims and disconnects need the internet.
- Comparisons ("21 min less than your usual …") need **3 earlier measured sessions of ≥ 10 min in the same Spot** and compare rates, not totals.

## Setup you have to do once

1. **Apple Developer: enable *NFC Tag Reading*** on the app's App ID and regenerate the provisioning profile. `Mivo.entitlements` declares `com.apple.developer.nfc.readersession.formats` (`NDEF`, `TAG`); signing a device build fails until the profile includes it.
2. **Deploy the association file.** `deployment/usemivo.app/.well-known/apple-app-site-association` claims `/s/*` and `/spot/*`; serve `deployment/usemivo.app/s/index.html` for `/s/*` (and `spot/index.html` for `/spot/*`) as the fallback for phones without Mivo. Without this, a tap opens Safari instead of Mivo.
3. **Apply the migration** `supabase/migrations/20261019130000_physical_spots.sql` (also appended to `supabase_schema.sql`). It was syntax-checked but not run against a database here.
4. Test on a real iPhone: NFC, Screen Time events and shields cannot run in the Simulator.

## Project membership

`ruby scripts/add_spots_files.rb` adds every file under `Mivo/Spots/` to the Mivo target, `SpotShared.swift` to the three extensions, and `MivoSpotsTests.swift` to `MivoClearGuardTests`. It is idempotent; re-run it after adding files.

## Previewing screens

DEBUG builds: launch with `-MivoPreviewSpots`, `-MivoPreviewSpotsEmpty`, `-MivoPreviewSpotDetail`, `-MivoPreviewSpotSetup`, `-MivoPreviewSpotConnect`, `-MivoPreviewSpotClaim`, `-MivoPreviewSpotActive`, `-MivoPreviewSpotSummary`, `-MivoPreviewSpotPause`, `-MivoPreviewSpotIntention` or `-MivoPreviewSpotNotice`.

## Adding another physical product

A new carrier (a different tag, a desk object, an accessory) only has to present `SpotLink.physicalURL(for:)` for an ID in the registry. Discovery, claiming, activation, history and summaries don't change.
