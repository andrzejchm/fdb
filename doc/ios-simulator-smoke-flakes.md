# iOS Simulator Smoke Test Flakes — Diagnostics

Five `task test:*` targets fail on the iPhone 17 Pro iOS simulator. Confirmed pre-existing on `main` (i.e., they failed before PR #87 too — not regressions). Each has a hypothesis below; the actual fix needs investigation in a follow-up session.

Failing tests:
- `test:reload`
- `test:restart`
- `test:back` (depends on `restart`, so cascades)
- `test:doctor`
- `test:native-view-tap`

The `task smoke` orchestrator runs sequentially and stops at first failure (`test:reload` is position 6), so a clean smoke run requires fixing all five (or skipping them) so the suite can complete.

## Test environment

- Host: macOS, Apple Silicon
- Simulator UDID: `C1DE4562-CFBF-45D8-B79E-740A11E86171` (iPhone 17 Pro)
- Flutter SDK: FVM-managed, version 3.41.6
- Test app: `example/test_app/`

---

## 1. `test:reload` — hot reload completes but `Flutter.Frame` event never arrives

**Symptom:** `RELOAD_FAILED` with exit 1 after a 10-second timeout.

**Architecture:** `runReload` sends `SIGUSR1` to the flutter-tools PID, then subscribes to the VM service `Extension` stream waiting for an event with `extensionKind == 'Flutter.Frame'`. See `lib/core/commands/reload/reload.dart` and `lib/core/vm_lifecycle_events.dart` (`isFlutterFrameEvent`, `waitForVmEventAfterSignal`).

**What happens on the simulator** (verified by listening to the Extension stream and triggering SIGUSR1 manually):

```
flutter run log:        "Performing hot reload... Reloaded 0 libraries in 105ms"
VM Extension stream:    Flutter.FrameworkInitialization
                        Flutter.ServiceExtensionStateChanged
                        Flutter.ServiceExtensionStateChanged
                        (NO Flutter.Frame event)
```

The reload itself happens — flutter-tools confirms it. But the simulator does NOT emit a `Flutter.Frame` extension event afterward, likely because zero libraries were reloaded and zero widgets needed rebuilding. Our matcher then times out.

**Hypotheses:**
1. After a "Reloaded 0 libraries" reload, no rebuild → no new frame → no `Flutter.Frame` event.
2. The `Flutter.Frame` extension is only emitted in some Flutter SDK versions / build modes / DevTools-attached states.
3. Our subscription races with the signal — the event fires before `streamListen` is acknowledged (unlikely given the 3s setup window).

**Suggested investigation path:**
- Match a wider set of post-reload events: `Flutter.ServiceExtensionStateChanged`, OR check the `Isolate` stream for `IsolateReload`-type events, OR fall back to grep'ping the flutter-tools log for `Reloaded N libraries` after sending the signal.
- Verify by triggering an actual code change (touch a `.dart` file) before reload and seeing if `Flutter.Frame` appears with non-zero libraries.

**Code locations:**
- `lib/core/commands/reload/reload.dart` (calls `waitForVmEventAfterSignal` with `isFlutterFrameEvent`)
- `lib/core/vm_lifecycle_events.dart` line 10 (`isFlutterFrameEvent` matcher)
- `lib/core/vm_lifecycle_events.dart` lines 56–146 (`waitForVmEventAfterSignal`)

---

## 2. `test:restart` — hot restart completes but `Flutter.FirstFrame` event never arrives

**Symptom:** `RESTART_FAILED` with exit 1 after a 10-second timeout.

**Architecture:** `runRestart` sends `SIGUSR2`, then waits for an `Extension` stream event with `extensionKind == 'Flutter.FirstFrame'`. See `lib/core/commands/restart/restart.dart` and `isFlutterFirstFrameEvent` in `vm_lifecycle_events.dart`.

**What happens on the simulator** (verified by listening to BOTH `Isolate` and `Extension` streams during SIGUSR2):

```
Isolate stream:   IsolateExit
                  IsolateStart
                  ~80 × ServiceExtensionAdded
                  IsolateRunnable
                  ~few more ServiceExtensionAdded
Extension stream: Flutter.FrameworkInitialization
                  Flutter.ServiceExtensionStateChanged
                  Flutter.ServiceExtensionStateChanged
                  (NO Flutter.FirstFrame event)
```

The restart works — isolate cycles cleanly. But `Flutter.FirstFrame` is never emitted on this Flutter version / iOS sim combination.

**Suggested investigation path:**
- Match `IsolateRunnable` on the `Isolate` stream as a "restart completed" signal (much more reliable — fires every time).
- Or match `Flutter.FrameworkInitialization` on the Extension stream (also reliable on this simulator).
- Cross-reference the Flutter source to find when `Flutter.FirstFrame` is emitted (may require dev tools attached, or specific Flutter binding hooks).

**Code locations:**
- `lib/core/commands/restart/restart.dart`
- `lib/core/vm_lifecycle_events.dart` line 15 (`isFlutterFirstFrameEvent`)

---

## 3. `test:back` — depends on `test:restart`, cascades

**Symptom:** `task: Failed to run task "test:back": exit status 1` immediately, with output `==> Hot restarting to reset UI state` and nothing else.

**Architecture:** the `test:back` smoke target calls `fdb restart` first to reset UI state to a known starting screen, then performs `fdb back` and asserts on `POPPED`. Since `restart` fails with `RESTART_FAILED` (see #2), the test bails out before exercising `fdb back`.

`fdb back` itself is verified working in isolation (the unit-level smoke pattern matches show `POPPED` is emitted correctly when called against a freshly launched app).

**Fix:** fixing `test:restart` (#2) should fix this automatically. If the restart event matcher is broadened to include `IsolateRunnable`, `back` will follow.

**Code locations:**
- `Taskfile.yml:1354` (`test:back`) — invokes `{{.FDB}} restart` at the start.
- `lib/core/commands/back/back.dart` (the actual back logic — believed correct).

---

## 4. `test:doctor` — dispatcher session-dir resolution rejects dead-PID scenario

**Symptom:** Test scenario "dead PID (app_running=fail)" fails with `ERROR: No .fdb/ session found. Run from the project root or pass --session-dir <path>.` and exit 1.

**What the test does:** writes `999999` (a non-existent PID) into `.fdb/fdb.pid`, then calls `fdb doctor` expecting it to report `DOCTOR_CHECK=app_running STATUS=fail` and `DOCTOR_SUMMARY=fail CHECKS=5 FAILED=3` while still exiting 0.

**Why it fails:** `bin/fdb.dart` runs `resolveSessionDir()` BEFORE dispatching to the `doctor` command. `resolveSessionDir` requires the PID file's process to be alive (`kill -0 <pid>` succeeds) before treating a `.fdb/` directory as valid. With PID 999999, this check fails, so the resolver walks up looking for another live `.fdb/`, finds none, and the dispatcher errors out before ever calling `runDoctorCli`.

This is a real fdb bug — the `doctor` command's whole purpose is to diagnose unhealthy sessions, but the dispatcher rejects unhealthy sessions before doctor can examine them. Same applies to `status` (which has a special-case bypass in the dispatcher: `if (command != 'status' && resolved == null)`).

**Suggested fix:** add `doctor` to the same bypass list (alongside `launch`, `devices`, `skill`, `status`, `--help`) — the doctor must be able to run when the session is unhealthy. See `bin/fdb.dart` lines 117–138.

```dart
// Current:
if (command != 'launch' && command != 'devices' && command != 'skill' && !wantsHelp) {
  // ... resolveSessionDir ...
  if (command != 'status' && resolved == null) {
    stderr.writeln('ERROR: No .fdb/ session found. ...');
    exit(1);
  }
}
```

Should become something like:
```dart
final exemptFromSessionResolution = {'launch', 'devices', 'skill', 'doctor'};
if (!exemptFromSessionResolution.contains(command) && !wantsHelp) {
  // ... existing logic, status still gets the soft-fail ...
}
```

But also: `resolveSessionDir`'s walk-up logic might pick the WRONG `.fdb/` if there's a sibling project with a live app. For `doctor`, the user's CWD is the truth — don't walk up. Need to think through the right behaviour.

**Code locations:**
- `bin/fdb.dart` lines 117–138 (session-dir resolution + bypass list).
- `lib/constants.dart` lines 42–96 (`resolveSessionDir`).
- `Taskfile.yml:143–262` (the test scenarios).

---

## 5. `test:native-view-tap` — IndigoHID tap doesn't actually hit the iOS UIAlertController

**Symptom:** `FAIL: UIAlertController never showed CONFIRMED — native tap did not reach the alert`.

**What the test does on iOS sim**:
1. Tap "Show Native Alert" button → `TAPPED=ElevatedButton X=201.0 Y=142.0` ✅
2. Tap absolute coords `269,488` (where the alert's "Confirm" button SHOULD be on this iPhone size) → `TAPPED=coordinates X=269.0 Y=488.0` ✅
3. Loop 10× polling `fdb describe` for "Native alert: CONFIRMED" → never appears, alert says "not shown" still ❌

**Architecture:** `fdb native-tap --at x,y` on iOS simulator runs an inline Swift script that uses `SimulatorKit.SimDeviceLegacyHIDClient` to send IndigoHID touch events directly to the simulator runtime, bypassing the Simulator.app window. See `lib/core/commands/native_tap/native_tap.dart`.

**Hypotheses:**
1. **Coordinates wrong**: hard-coded `269,488` doesn't match the actual iPhone 17 Pro (393×852) UIAlertController button position. The alert is centered, with the "Confirm" button on the right half. The Swift script normalises to xRatio/yRatio (`x/393, y/852`), which gives `(0.685, 0.572)`. Need to verify the alert's actual center position on this exact simulator.
2. **IndigoHID API drift**: SimulatorKit's `SimDeviceLegacyHIDClient` is a private framework. iOS 18+ / Xcode 16+ may have changed the message format. The Swift script does `down.storeBytes(of:..., toByteOffset:0x3c, ...)` — those byte offsets are reverse-engineered from `idb` and may have shifted.
3. **Tap delivered but to wrong layer**: the IndigoHID touch reaches the simulator but lands on the Flutter view behind the alert, not the alert itself.

**Suggested investigation path:**
- Take a screenshot during the failed test to see exactly where the alert is rendered.
- Query the simulator's actual screen size dynamically rather than relying on `_iPhoneLogicalSize` lookup table.
- Try a known-good native button (a UIAlertController button is unusual — system UI runs in a separate process via SpringBoard).
- Compare with `idb`'s working tap implementation to verify the Indigo message byte layout hasn't drifted.

**Code locations:**
- `lib/core/commands/native_tap/native_tap.dart` lines 187–217 (`_tapIosSimulator`)
- `lib/core/commands/native_tap/native_tap.dart` lines 285–347 (`_indigoTapScript` — the Swift incantation)
- `Taskfile.yml:1501–1620` (`test:native-view-tap`, iOS branch on lines 1552–1590)

---

## Quick reproduction

```bash
# Launch the test app
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:launch

# Trigger each flake
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:reload         # FAILS: RELOAD_FAILED
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:restart        # FAILS: RESTART_FAILED
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:back           # FAILS: cascades from restart
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:doctor         # FAILS: dead-PID scenario
DEVICE=C1DE4562-CFBF-45D8-B79E-740A11E86171 task test:native-view-tap # FAILS: alert not dismissed

# Cleanup
cd example/test_app && dart run /Users/andrzejchm/Developer/andrzejchm/fdb/bin/fdb.dart kill
```

## Goal for the follow-up PR

`task smoke` runs to completion with all PASS lines on this iOS simulator. Each fix should be a separate commit. None of the fixes should regress Android-side behaviour — the original logic was presumably written and verified for Android first.
