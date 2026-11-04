# Attention journey

The iPhone app now connects a chosen problem to one starting action, a commitment, a weekly experiment, and a review. Existing Screen Time, Still, Lock-in, Swap, and Companion services remain responsible for their respective behavior.

## Data and evidence

- `AttentionJourney` is stored with `StorageService`, scoped to the signed-in account. It is local to this device and included in both export paths.
- Completing an ordinary commitment is explicitly self-reported. A linked Lock-in can only resolve through Lock-in's existing rules; its evidence is labeled Milo-reviewed or keyholder-approved.
- Repeated Lock-in history imports are idempotent. Expired and cancelled locks do not count as completed commitments.
- A recovery choice is a request for an easier next step, not a completed task. It leaves the existing schedule and shields in place.
- Experiment suggestions distinguish recorded session/check-in patterns from a starting suggestion based on the person's choice. Before-and-after results require at least three sessions in both periods and do not establish causation.
- Mivo Clear is no longer reachable from the iPhone app (removed 2026-11-03). The messages problem and recovery choice open the app window flow, where messages in Mivo are free.

## Device acceptance checks

1. On a new account, choose each starting problem in turn. Verify that Home offers the appropriate commitment, the app window flow, or 15-minute Still setup. Changing the focus must not overwrite existing protections.
2. Finish the three-question onboarding flow, with and without Screen Time permission. The optional swap can be skipped. The app picker must save actual selections. Finishing setup must not immediately present a paywall.
3. Create a commitment, make it smaller, mark it done, and restart the app. Its title, timestamp, and self-report label should survive. Verify the matching date range in receipts and the weekly report.
4. Protect a commitment with Lock-in. Verify the task is prefilled. An active protected task cannot be marked done, resized, or set aside from the commitment screen. Check Milo, keyholder, timeout, and early-cancel outcomes using in-memory fixtures or an explicitly initiated device test.
5. Pick each recovery action. Premium actions should offer their contextual upgrade when needed. A cancelled recovery setup must not appear as a completed commitment or erase a schedule.
6. From the messages problem and recovery choice, pick an app and Messages. It should open straight into that app's messages in Mivo, with no paywall.
7. Approve an experiment, stop it early, finish a full week, and keep/adjust/stop the completed rule. Managing an existing rule must remain accessible after Plus expires. Other shields must remain active when an experiment ends.
8. Sign out, switch accounts, export, and reset/delete the account. Commitments from one account must not appear in another.

## Automated checks and previews

`ruby scripts/add_attention_journey_files.rb` idempotently registers the new sources and tests without regenerating the project.

Run the shared `Mivo` scheme's `MivoClearGuardTests` on an iOS simulator. `AttentionJourneyTests` covers commitment transitions, Lock-in import deduplication, evidence labels, date-range boundaries, daylight-saving recovery deduplication, account storage isolation, direct media links, and insufficient experiment evidence.

For a quick check without an iOS simulator, run `python3 scripts/test_attention_journey_core.py`. It runs the same 12 XCTest cases against the actual Foundation-only source declarations in a temporary Swift package.

Validated on November 1, 2026: the native simulator build succeeded, and 113 selected iOS tests passed (AttentionJourney, LockInManager, LockInRules, LockInModel, MivoPlus, MivoComeback, and MivoClearRuntimeGuard). The website production build, TypeScript check, and lint for the changed files also passed. Repository-wide website lint still includes existing issues in unrelated hooks and generated files inside nested worktrees.

Visually reviewed the actual starting-point, onboarding, commitment, recovery, completion-history, Clear, and Home screens in the isolated iPhone 16 simulator. Reviewed both the initial Clear state and its explicit unavailable state.

Debug builds support `-MivoPreviewAttention home|plan|commitment|wins|recovery`. Use a separate QA simulator: the preview seeds a fictional local profile. Screen Time enforcement, NFC, camera recording, purchases, and live social-site compatibility still require device/service verification.
