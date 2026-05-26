# Quick Test Guide: Verify Blocking Without Xcode

## Prerequisites
✅ Physical iPhone (iOS 16+)
✅ App installed and Screen Time authorized
✅ Protected apps selected in Settings

## Step 1: Run Self-Test (First Time)

1. Open Mivo app
2. Go to **Settings** tab
3. Scroll to **Screen Time** section
4. Find **"Blocker self-test"** row
5. Tap **"Test"** button
6. **Immediately leave Mivo** (press home button)
7. **Stop Xcode** if it's running
8. Wait 20 seconds
9. Reopen Mivo app
10. Go back to Settings
11. Check self-test row shows: **"✅ Verified - blocker is working"**

### If Self-Test Fails
- Tap the **ℹ️** button next to Test
- Read diagnostics
- Common fixes:
  - Restart iPhone
  - Reinstall app
  - Check extension target is built

## Step 2: Test Session Blocking

1. In Mivo, start a **1-minute timed session**
   - Choose any intention
   - Set duration to 1 minute
2. Session should start successfully (no errors)
3. Open a **protected app** (should work during session)
4. **Kill Mivo** from app switcher (swipe up and remove)
5. **Stop Xcode** completely
6. Wait 1+ minute for timer to expire
7. Try opening the protected app again
8. **Expected: App is blocked by shield screen** 🔒
9. Reopen Mivo
10. **Expected: Must start new session to unblock**

## Success Criteria

✅ Self-test shows "Verified" status
✅ Session starts without errors
✅ Apps relock after timer expires (even with app killed)
✅ Shield screen appears when trying to access protected app
✅ Must reopen Mivo to start new session

## Failure Indicators

❌ Self-test never completes (stuck on "Running...")
❌ Error: "Screen Time blocker not verified"
❌ Error: "Failed to start session: Device Activity blocker could not be scheduled"
❌ Apps don't relock after timer expires
❌ Can access protected apps after session should have ended

## Debug Info

### Check Extension Logs (Debug Builds Only)
1. Settings → Advanced → Extension Logs
2. Look for:
   - "⏰ Monitoring interval STARTED"
   - "⏰ Monitoring interval ENDED"
   - "🔒 SESSION RELOCK"
   - "✅ SELF-TEST COMPLETED"

### Check Diagnostics
1. Settings → Screen Time → Blocker self-test → ℹ️
2. Shows:
   - Test started time
   - Test completed time
   - Pass/fail status
   - Recent verification status

## Common Issues

### "Test" button grays out but never completes
**Fix**: Stop Xcode, leave app, wait 20s, reopen

### Session won't start - "blocker not verified"
**Fix**: Run self-test first, ensure it passes

### Apps don't relock
**Fix**: 
1. Check extension logs for SESSION RELOCK message
2. Verify extension target is built and signed
3. Restart device after fresh install

## When to Rerun Self-Test

- After 24 hours (test expires)
- After app reinstall
- After iOS update
- After changing protected apps
- If session blocking stops working

## Contact Developer If:

- Self-test never passes (after device restart + reinstall)
- Self-test passes but blocking still doesn't work
- Extension logs show errors
- Sessions fail with "could not be scheduled" error

## Quick Checklist

- [ ] Self-test passes with green "Verified" status
- [ ] Can start 1-minute session without errors
- [ ] Protected app opens during session
- [ ] Kill Mivo app and stop Xcode
- [ ] Wait 1+ minute
- [ ] Protected app is blocked after timer expires
- [ ] Reopen Mivo, must start new session

**If all checkboxes pass: Blocking works correctly without Xcode! 🎉**
