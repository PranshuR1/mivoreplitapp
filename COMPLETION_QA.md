# Mivo completion checks — November 4, 2026

## Implemented and verified

- **iOS:** fixed AI citation parsing so negative, zero, missing and out-of-range citations cannot
  index outside the notes or bypass grounding. Replies cannot invent numbers absent from the
  cited note. Questions are bounded, dismissed requests are cancelled, and outages explicitly
  return a bundled note or support contact. Updated the knowledge bundle for commitments,
  linked study and the current iPhone flows. Removed remaining compiler warnings in the
  validated targets. The latest signed 3.1 app was installed and launched on the connected
  iPhone 14; its process remained running after launch.
- **Mac:** fixed room-operation races across sign-out and switching away and back to the same
  account. Old responses/errors cannot overwrite a new room or clear a newer operation's busy
  state. Stale polls cannot overwrite a room change. Account transitions clear the last-sync
  timestamp and room state. Added isolated lifecycle tests and corrected the privacy documentation
  to describe linked-study traffic.
- **Website:** completed the room UI changes with synchronized mutation guards, stale-poll
  protection, explicit offline state and per-room visitor remounting. Fixed reduced-motion and
  portal hydration hooks. Test and lint commands exclude nested agent worktrees.
- **Shared services:** the linked-study database checks pass for permissions, account isolation,
  reconnects, offline credit, completion, cancellation, reward replay and the trial. The real AI
  Edge Function handler passes isolated authentication, payload-limit, token-cap, citation-prefix,
  timeout and upstream-error checks.

## Results

| Check | Result |
|---|---|
| iOS, isolated iPhone 16 / iOS 18.4 simulator | **385 tests passed**, zero failures |
| Latest signed iPhone build | **Build succeeded**, signature verified, installed and launched |
| Latest Mac build and unit tests | **92 tests passed** (76 XCTest + 16 Swift Testing) |
| Website unit tests | **43 passed** |
| Full website ESLint and TypeScript | **Passed** |
| Website production build | **Passed**; code changes remain in the local working tree |
| Linked-study database and AI handler checks | **Passed** with isolated fixtures |
| Live study sync, linked study and room endpoints | **Present**; authenticated endpoints reject anonymous access |

The first iOS run used a simulator shared with another active chat and its host was killed.
The dedicated `Mivo Completion QA` simulator then passed the full suite. Web room checks used
local sample responses, creating no production users or study sessions: join, leave, offline
recovery, and a delayed closed-room response after a successful join. The latter did not undo
the newer action. A 390px mobile frame had no horizontal overflow and its join controls fit.
The Kimi WebBridge browser session was closed after QA.

The current Mac/iPhone guided study setup changes from the `Improve study room UI` chat are
included in these final tests. That chat also reported both guided setups visually checked.
Actual Screen Time enforcement and camera capture still need an explicitly initiated physical
device session; no long-lived lock or capture session was started on the person's phone here.

## AI deployment and remaining input

The exact tested `supabase/functions/mivo-ai/index.ts` source was deployed through the existing
authorized Supabase dashboard. Legacy gateway JWT verification was disabled because this
function validates users itself, matching its documented deployment configuration. The saved
source was reopened in a fresh browser tab and verified byte for byte against the local file
(SHA-256 `e99307a7092db4c06c2e39562e8b01c129c0a19e793f6be146a5f12a09a5f285`).

The project currently has **no custom secrets**, so model generation is not activated.
`MIVO_AI_URL` and `MIVO_AI_HF_TOKEN` must be configured, then a signed-in end-to-end model test
must pass. The live proxy currently returns `500 service_not_configured`; the service probe
correctly reports that check as a failure. The connected Hugging Face account had no models
or Spaces. A pinned, private CPU
hosting recipe is prepared in `deployment/mivo-ai-server`; it has not been deployed or run.
Its hosting plan requires a user decision or an existing compatible model-server URL.

Spots were removed from the iPhone app, while the website still offers them for purchase.
The decision to pause new sales or keep them available is pending. Existing orders, checkout,
refund policies and support were preserved while that decision is outstanding.

No paid hosting plan was purchased. No production website deployment, Git push or release DMG
was made. Mac originals are backed up at
`/var/folders/vc/96fdczc92859r5rbtdkd35b00000gn/T/mivo-mac-completion-backup-ijcxh4vh`.

At final review, all 422 source/configuration fingerprints still matched the validated files.
The phone's main Mivo process and its device-activity extension were still running.

## Reproduce

- iOS: shared `Mivo` scheme, `MivoClearGuardTests`, isolated simulator
  `226DA105-DFCA-4BFA-BEF4-B6AC25817F71`.
- Mac: `xcodebuild -project MivoMac/MivoMac.xcodeproj -scheme MivoMac -configuration Debug -destination 'platform=macOS' test -only-testing:MivoMacTests CODE_SIGNING_ALLOWED=NO`.
- Website: `npm test`, `npm run lint`, `npm run typecheck`, `npm run build`.
- Database: install PGlite outside the repo, then run `scripts/test_linked_study_db.mjs` with
  `PGLITE_MODULE` pointing to its `dist/index.js`.
- AI handler: run `scripts/test_mivo_ai_edge.mjs` with `TYPESCRIPT_MODULE` pointing to an installed
  TypeScript `lib/typescript.js`.
- Live read-only service probe: `python3 scripts/check_completion_services.py`.
