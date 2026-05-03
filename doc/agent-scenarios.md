# Agent Scenarios — fdb Test App

Structured scenarios for an AI agent to run against the fdb test app and
**evaluate the output semantically**. These are not pass/fail shell scripts —
you read the actual output and judge whether it looks correct. This catches
regressions that token-matching alone misses (wrong screen scope, missing
elements, unexpected content leaking from other screens, etc.).

Run these scenarios after implementing or modifying any fdb feature, before
opening a PR. They complement `task smoke` (which runs the automated
token-matching tests) rather than replacing it.

## Prerequisites

App is running and `fdb_helper` is wired up:

```bash
cd example/test_app
dart run ../../bin/fdb.dart status   # must print RUNNING=true
```

If not running:

```bash
dart run ../../bin/fdb.dart launch --device <device_id>
```

All commands below are run from `example/test_app/` unless stated otherwise.

---

## S1 · describe — home screen

**Purpose:** baseline describe on the root route. Catches output format
regressions and verifies all expected elements are present.

```bash
# Ensure we are on the home screen (back to root if needed)
dart run ../../bin/fdb.dart back 2>/dev/null || true
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `SCREEN:` line says `fdb test app`
- `ROUTE:` line says `/`
- `INTERACTIVE:` section is present and contains at least these entries (not
  necessarily in this order):
  - `TextField` with `key=test_input`
  - `ElevatedButton "Submit"` with `key=submit_button`
  - `ElevatedButton "Go to Details"` with `key=go_to_details`
  - `ElevatedButton "Show Dialog"` with `key=show_dialog`
  - `FloatingActionButton` with `key=increment_button`
  - `GestureDetector` with `key=double_tap_target`
  - `GestureDetector` with `key=longpress_target`
- `VISIBLE TEXT:` section contains `"fdb test app"` and `"Counter: 0"`
- No element from a different screen appears (no `"Detail Page"`, no
  `"Benchmarks"` heading from a sub-screen)

---

## S2 · describe — child route isolation

**Purpose:** verifies that describe only surfaces the current (topmost) route
and does not leak elements from the underlying home screen. This was a
confirmed bug — regression guard.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_details
dart run ../../bin/fdb.dart tap --key go_to_details
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `SCREEN:` says `Detail Page` — not `fdb test app`
- `INTERACTIVE:` contains exactly the Back `IconButton` (and nothing else
  from home — no `submit_button`, no `double_tap_target`, no `show_delayed`)
- `VISIBLE TEXT:` contains `"Detail Page"` and `"Detail Page Content"`
- `VISIBLE TEXT:` does NOT contain home-screen text like `"Go to Details"`,
  `"Show Dialog"`, `"Benchmarks"`, or `"Submit"`

---

## S3 · describe — two levels deep

**Purpose:** describe works correctly when navigated two levels into the stack
(home → benchmarks → a benchmark sub-screen).

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_benchmarks
dart run ../../bin/fdb.dart tap --key go_to_benchmarks
sleep 1
dart run ../../bin/fdb.dart tap --key bench_baseline
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `SCREEN:` reflects the benchmark sub-screen title (e.g. `Baseline`)
- `ROUTE:` reflects `/benchmark/baseline`
- `INTERACTIVE:` contains only elements of that screen — no home-screen keys
  (`submit_button`, `go_to_details`, etc.) and no benchmark-menu keys
  (`bench_medium`, `bench_stress_list`, etc.)

---

## S4 · describe — nested GestureDetectors inside Stack/Positioned

**Purpose:** GestureDetectors nested inside Positioned widgets are found.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_nested_gesture_describe_test
dart run ../../bin/fdb.dart tap --key go_to_nested_gesture_describe_test
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `SCREEN:` says `Nested Gesture Describe Test`
- `INTERACTIVE:` contains `key=nested_gesture_reject` and
  `key=nested_gesture_approve`
- The outer toolbar `GestureDetector` (horizontalDrag) also appears
- `VISIBLE TEXT:` contains `"Main content"`

---

## S5 · describe — off-screen GridView/ListView children

**Purpose:** elements that exist in the widget tree but are below the viewport
are still listed with `built: false` placeholder coordinates.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_grid_describe_test
dart run ../../bin/fdb.dart tap --key go_to_grid_describe_test
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- Grid items `key=grid_item_40` through `key=grid_item_49` appear even though
  they are below the fold on any screen size
- List items `key=list_item_120` through `key=list_item_149` appear
- Each off-screen entry has `y` coordinate of `9999999` (or similar large
  placeholder) — do NOT use these coordinates to drive `fdb tap --at`

---

## S6 · tap — by key, text, type, ref

**Purpose:** all four tap selectors work and the correct element is tapped.

```bash
# Tap by key — increments counter
dart run ../../bin/fdb.dart tap --key increment_button
dart run ../../bin/fdb.dart describe
```

**After tap by key:** `VISIBLE TEXT:` in describe shows `"Counter: 1"`.

```bash
# Tap by text — submit button
dart run ../../bin/fdb.dart tap --text "Submit"
```

**After tap by text:** exits 0. The `TAPPED=` token MUST NOT be `Text` (the
ancestor walk in `findHittableElement` is required to resolve to an
interactive ancestor of the matched `Text` leaf). The exact ancestor type
is implementation-dependent across Flutter SDK versions: it may be
`GestureDetector`, `InkWell`, `ElevatedButton`, or another interactive
widget. The contract is the negative one: `TAPPED=Text` is a regression
of fdb-xdh.

```bash
# Tap by ref — get ref from describe, tap @1
dart run ../../bin/fdb.dart describe
# Note the ref number of the TextField (e.g. @1)
dart run ../../bin/fdb.dart tap @1
```

**After tap by ref:** exits 0, output contains `TAPPED=`.

---

## S7 · tap — disappearing widget

**Purpose:** tapping a widget that removes itself from the tree on tap succeeds
(the tap fires even if the element is gone by the time fdb checks the result).
This is also the regression guard for fdb-gfk: route-level `IgnorePointer`
wrappers must not leak into the `TAPPED=` token.

```bash
# Restart to ensure disappearing_button is present (it only exists once per session)
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key disappearing_button
dart run ../../bin/fdb.dart tap --key disappearing_button
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `tap` exits 0 with `TAPPED=ElevatedButton` (not `IgnorePointer` or any other wrapper)
- `describe` no longer shows `key=disappearing_button` in `INTERACTIVE:`

---

## S8 · input — type into a TextField

**Purpose:** text input lands in the right field and is readable back.

```bash
dart run ../../bin/fdb.dart input --key test_input "hello fdb"
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `input` command exits 0 with `INPUT=TextField VALUE=hello fdb`
- `describe` INTERACTIVE entry for `key=test_input` contains `"hello fdb"` in its text label
- `VISIBLE TEXT:` contains `"hello fdb"` (TextField content is visible on screen)

Clean up:

```bash
dart run ../../bin/fdb.dart input --key test_input ""
```

---

## S9 · scroll — down and up on the home screen

**Purpose:** scroll changes which elements are in the viewport; describe output
reflects the scroll position.

```bash
# Scroll all the way to the top first
dart run ../../bin/fdb.dart scroll up
dart run ../../bin/fdb.dart scroll up
dart run ../../bin/fdb.dart describe
```

**After scrolling to top:** `VISIBLE TEXT:` should contain `"fdb integration test
target"` and `"Counter: 0"` (elements near the top of the page).

```bash
dart run ../../bin/fdb.dart scroll down
dart run ../../bin/fdb.dart scroll down
dart run ../../bin/fdb.dart describe
```

**After scrolling down:** top-of-page text may drop out of `VISIBLE TEXT:`;
lower-page elements (e.g. `"Double Tap Target"` GestureDetectors, PageView
pages) should appear.

---

## S10 · scroll-to — lazy list item

**Purpose:** scroll-to reveals a lazy-built item and brings it into the viewport.

```bash
dart run ../../bin/fdb.dart tap --key go_to_scroll_to_test
sleep 1
dart run ../../bin/fdb.dart tap --key go_to_lazy_list
sleep 1
# Item 80 is well below the initial viewport on any device
dart run ../../bin/fdb.dart scroll-to --key lazy_item_80
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `scroll-to` exits 0 with `SCROLLED_TO=ListTile`
- `describe` INTERACTIVE contains `key=lazy_item_80` with a normal (non-placeholder)
  y coordinate — it is now on screen

---

## S11 · back — navigator pop

**Purpose:** `fdb back` pops the current route and describe reflects the parent
screen.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_details
dart run ../../bin/fdb.dart tap --key go_to_details
sleep 1
dart run ../../bin/fdb.dart back
sleep 1
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `back` exits 0 with `POPPED`
- `describe` after back shows `SCREEN: fdb test app` and `ROUTE: /`
- Home screen elements are back in `INTERACTIVE:`

---

## S12 · double-tap — counter increments

**Purpose:** double-tap fires on a GestureDetector with `onDoubleTap`.

```bash
dart run ../../bin/fdb.dart scroll-to --key double_tap_target
dart run ../../bin/fdb.dart double-tap --key double_tap_target
sleep 0.5
dart run ../../bin/fdb.dart scroll-to --key double_tap_summary
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `double-tap` exits 0 with `DOUBLE_TAPPED=GestureDetector`
- `describe` VISIBLE TEXT contains `"Double tap summary: primary=1"` (count
  incremented from 0 to 1)

---

## S13 · longpress — fires the handler

**Purpose:** long-press gesture reaches a GestureDetector with `onLongPress`.

```bash
dart run ../../bin/fdb.dart scroll-to --key longpress_target
dart run ../../bin/fdb.dart longpress --key longpress_target
```

**What to verify:**

- Exits 0 with `LONG_PRESSED=GestureDetector`
- `fdb logs --last 5` shows `longpress_target triggered` log line

---

## S14 · wait — element appears after delay

**Purpose:** `fdb wait` blocks until an element appears, rather than sleeping.

```bash
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key show_delayed
dart run ../../bin/fdb.dart tap --key show_delayed
dart run ../../bin/fdb.dart wait --key delayed_button --present --timeout 5000
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `wait` exits 0 with `CONDITION_MET=present KEY=delayed_button` (button appears after ~2 s)
- `describe` shows `key=delayed_button` in `INTERACTIVE:`

---

## S15 · wait — absent guard

**Purpose:** `fdb wait --absent` resolves when an element disappears.

```bash
# Restart to ensure disappearing_button is present
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key disappearing_button
dart run ../../bin/fdb.dart tap --key disappearing_button &
dart run ../../bin/fdb.dart wait --key disappearing_button --absent --timeout 3000
```

**What to verify:**

- `wait --absent` exits 0 with `CONDITION_MET=absent KEY=disappearing_button`

---

## S16 · swipe — PageView page change

**Purpose:** swipe advances the PageView on the home screen.

```bash
dart run ../../bin/fdb.dart scroll-to --key page_view
dart run ../../bin/fdb.dart describe
# Note which page is visible (should be "Page 1")
dart run ../../bin/fdb.dart swipe left --key page_view
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `swipe` exits 0 with `SWIPED=left` (lowercase, consistent with `SCROLLED=down`)
- Second `describe` VISIBLE TEXT shows `"Page 2"` instead of `"Page 1"`

---

## S17 · status

**Purpose:** status correctly reports the app as running.

```bash
dart run ../../bin/fdb.dart status
```

**What to verify:** `RUNNING=true`, `PID=` and `VM_SERVICE_URI=` are present.

---

## S18 · reload and restart

**Purpose:** hot reload and restart complete without error.

```bash
dart run ../../bin/fdb.dart reload
```

**What to verify:** exits 0, output contains `RELOADED`.

```bash
dart run ../../bin/fdb.dart restart
```

**What to verify:** exits 0, output contains `RESTARTED`.

---

## S19 · logs — tag filtering

**Purpose:** `fdb logs` returns app-emitted log lines; `--tag` filters them.

```bash
# Tap increment to emit a log line
dart run ../../bin/fdb.dart tap --key increment_button
sleep 0.5
dart run ../../bin/fdb.dart logs --tag fdb_test --last 10
```

**What to verify:**

- Output contains `counter incremented to` log line
- No lines from other tags appear in the filtered output

---

## S20 · tree — widget tree snapshot

**Purpose:** `fdb tree` returns a non-empty indented widget tree.

```bash
dart run ../../bin/fdb.dart tree --depth 4 --user-only
```

**What to verify:**

- Output is not empty
- Recognisable Flutter widget types appear (`MaterialApp`, `Scaffold`,
  `AppBar`, `ElevatedButton`, etc.)
- Depth is respected — no subtrees deeper than 4 levels appear

---

## S21 · shared-prefs — read, write, clear

**Purpose:** shared-prefs round-trip works.

```bash
dart run ../../bin/fdb.dart shared-prefs set test_key "hello"
dart run ../../bin/fdb.dart shared-prefs get test_key
dart run ../../bin/fdb.dart shared-prefs remove test_key
dart run ../../bin/fdb.dart shared-prefs get test_key
```

**What to verify:**

- `set` exits 0 with `PREF_SET=test_key`
- `get` exits 0 with `PREF_VALUE=hello`
- `remove` exits 0 with `PREF_REMOVED=test_key`
- Second `get` exits 0 with `PREF_NOT_FOUND`

---

## S22 · mem and gc

**Purpose:** heap inspection and forced GC work without errors.

```bash
dart run ../../bin/fdb.dart mem
dart run ../../bin/fdb.dart gc
```

**What to verify:**

- `mem` prints a table with `heapUsage` column and a `TOTAL` row; values are
  human-readable (e.g. `81.0 MB`)
- `gc` exits 0 with `GC_COMPLETE HEAP_BEFORE=... HEAP_AFTER=... HEAP_DELTA=...`
- `HEAP_DELTA` is negative (GC reclaimed memory)

---

## S23 · kill

**Purpose:** kill stops the app cleanly. Run this last — it terminates the
session used by all preceding scenarios.

```bash
dart run ../../bin/fdb.dart kill
dart run ../../bin/fdb.dart status
```

**What to verify:**

- `kill` exits 0
- `status` prints `RUNNING=false`

---

## S24 · grant-permission — pre-grant camera on iOS simulator

**Purpose:** verify that granting camera before launch results in the app
seeing `granted` status without any system dialog appearing.

**Platform:** iOS simulator only. Skip on Android, macOS, physical iOS.

```bash
# Reset all permissions and kill the app
xcrun simctl privacy <UDID> reset all <bundle-id>
dart run ../../bin/fdb.dart kill 2>/dev/null || true

# Pre-grant camera
dart run ../../bin/fdb.dart grant-permission camera --bundle <bundle-id>

# Launch and navigate to permission screen
dart run ../../bin/fdb.dart launch --device <device-id>
dart run ../../bin/fdb.dart scroll-to --key go_to_permission_test
dart run ../../bin/fdb.dart tap --key go_to_permission_test
sleep 1
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `PERMISSION_GRANTED=camera` was printed by the grant command
- No system permission dialog appeared (no dialog visible in describe output)
- `ROUTE:` says `/permission-test`
- Camera row shows `status: granted`
- Other permissions (microphone, location, photos, contacts) show `status: denied`

---

## S25 · grant-permission — revoke camera on iOS simulator

**Purpose:** verify that revoking a previously granted permission results in
the app seeing `permanentlyDenied` status.

**Platform:** iOS simulator only. Requires S24 to have run first (camera is granted).

```bash
# Revoke camera (app will be terminated by simctl)
dart run ../../bin/fdb.dart grant-permission camera --revoke --bundle <bundle-id>

# Relaunch and navigate to permission screen
dart run ../../bin/fdb.dart launch --device <device-id>
dart run ../../bin/fdb.dart scroll-to --key go_to_permission_test
dart run ../../bin/fdb.dart tap --key go_to_permission_test
sleep 1
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `PERMISSION_REVOKED=camera` was printed by the revoke command
- Camera row shows `status: permanentlyDenied`

---

## S26 · grant-permission — grant all on Android

**Purpose:** verify that granting camera, microphone, location, photos, and
contacts on Android results in all showing `granted` live without app restart.

**Platform:** Android only. Skip on iOS, macOS.

```bash
# Navigate to permission screen first
dart run ../../bin/fdb.dart scroll-to --key go_to_permission_test
dart run ../../bin/fdb.dart tap --key go_to_permission_test
sleep 1

# Confirm all start as denied
dart run ../../bin/fdb.dart describe

# Grant all 5
dart run ../../bin/fdb.dart grant-permission camera
dart run ../../bin/fdb.dart grant-permission microphone
dart run ../../bin/fdb.dart grant-permission location
dart run ../../bin/fdb.dart grant-permission photos
dart run ../../bin/fdb.dart grant-permission contacts

# Refresh and check
dart run ../../bin/fdb.dart tap --key refresh_permissions
sleep 1
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- All 5 grant commands print `PERMISSION_GRANTED=<token>`
- No termination warnings on Android (app stays alive)
- After refresh, all 5 rows show `status: granted`
- No system permission dialogs appeared

---

## S27 · grant-permission — photos warning on iOS simulator

**Purpose:** verify that granting photos on iOS simulator emits the unreliable
photos warning, and that the permission may not take effect.

**Platform:** iOS simulator only.

```bash
dart run ../../bin/fdb.dart grant-permission photos --bundle <bundle-id>
```

**What to verify:**

- `PERMISSION_GRANTED=photos` is printed
- `WARNING: Photos permission via simctl is unreliable on iOS simulator` is printed
- The warning mentions this is a known Apple limitation

---

## S28 · grant-permission — unsupported platform errors

**Purpose:** verify clear error messages on unsupported platforms.

**Platform:** run on macOS and physical iOS.

```bash
# On macOS:
dart run ../../bin/fdb.dart grant-permission camera

# On physical iOS:
dart run ../../bin/fdb.dart grant-permission camera
```

**What to verify:**

- macOS grant: prints `WARNING:` about Apple requiring user approval, suggests `--reset`
- macOS reset: `dart run ../../bin/fdb.dart grant-permission camera --reset --bundle <bundle-id>` prints `PERMISSION_RESET=camera`
- Physical iOS: prints `ERROR:` about not being supported, suggests using iOS simulator

---

## S29 · grant-permission — unknown token and missing args

**Purpose:** verify input validation produces clear errors.

```bash
dart run ../../bin/fdb.dart grant-permission totally_fake_permission
dart run ../../bin/fdb.dart grant-permission
dart run ../../bin/fdb.dart grant-permission camera --revoke --reset
```

**What to verify:**

- Unknown token: `ERROR: Unsupported permission` with list of supported tokens
- No args: `ERROR: Provide a permission token`
- Conflicting flags: `ERROR:` about mutual exclusivity

---

## S30 · describe — ListTile with interactive trailing widget

**Purpose:** when a `ListTile` has no `onTap` but contains an `ElevatedButton`
in its `trailing` slot, only the button should appear in `INTERACTIVE:`. The
tile body is not itself tappable and must not produce a spurious entry.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_listtile_describe_test
dart run ../../bin/fdb.dart tap --key go_to_listtile_describe_test
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `SCREEN:` says `ListTile Describe Test`
- `INTERACTIVE:` contains `key=perm_request_camera` (`ElevatedButton "Request"`)
  with real on-screen coordinates (not `y=9999999`)
- `INTERACTIVE:` does NOT contain a bare `ListTile` entry for the camera row
  (the tile has no `onTap` - it is not independently tappable)
- `INTERACTIVE:` does contain `key=tappable_tile` (the tile in case 2 that has
  `onTap`)
- `INTERACTIVE:` does NOT contain `key=display_tile` (case 3 - no `onTap`, no
  interactive children)

---

## S31 · describe — plain tappable ListTile

**Purpose:** a `ListTile` with `onTap` and no interactive children surfaces as
a single interactive entry. Regression guard for the structural rewrite.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_listtile_describe_test
dart run ../../bin/fdb.dart tap --key go_to_listtile_describe_test
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `INTERACTIVE:` contains `key=tappable_tile` with text containing
  `"Tappable tile"` (or similar)
- The entry has real on-screen coordinates (not `y=9999999`)
- No duplicate entries for `tappable_tile`

---

## S32 · describe — display-only ListTile is not surfaced

**Purpose:** a `ListTile` with no `onTap` and no interactive children must not
appear in `INTERACTIVE:` at all - it is a display element.

```bash
dart run ../../bin/fdb.dart scroll-to --key go_to_listtile_describe_test
dart run ../../bin/fdb.dart tap --key go_to_listtile_describe_test
sleep 1
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `INTERACTIVE:` does NOT contain `key=display_tile`
- `VISIBLE TEXT:` contains `"Display only"` (the text is visible but the tile
  is not interactive)

---

## S33 · simulator — appearance, status-bar, location, text-size, push, defaults

**Purpose:** verifies all `fdb simulator` subcommands work end-to-end on a
booted iOS simulator. Does not require a running app session for most
subcommands, but push delivery verification uses the Notification Test screen.

> **iOS simulator only** — skip on Android, macOS, physical iOS.

```bash
# Confirm a simulator is booted
xcrun simctl list devices booted

# --- appearance ---
dart run ../../bin/fdb.dart simulator appearance get
dart run ../../bin/fdb.dart simulator appearance dark
dart run ../../bin/fdb.dart simulator appearance get
dart run ../../bin/fdb.dart simulator appearance light

# --- text-size ---
dart run ../../bin/fdb.dart simulator text-size get
dart run ../../bin/fdb.dart simulator text-size accessibility-extra-extra-large
dart run ../../bin/fdb.dart simulator text-size get
dart run ../../bin/fdb.dart simulator text-size large

# --- status-bar ---
dart run ../../bin/fdb.dart simulator status-bar override --time "9:41" --battery-state charged --battery-level 100 --wifi-bars 3 --cellular-bars 4 --operator "fdb"
dart run ../../bin/fdb.dart simulator status-bar clear

# --- location ---
dart run ../../bin/fdb.dart simulator location set 48.8584,2.2945
dart run ../../bin/fdb.dart simulator location route "City Run"
dart run ../../bin/fdb.dart simulator location clear

# --- defaults (use the real app bundle ID) ---
dart run ../../bin/fdb.dart simulator defaults write --bundle-id dev.andrzejchm.fdb.testApp fdb_scenario_key "hello_fdb"
dart run ../../bin/fdb.dart simulator defaults read --bundle-id dev.andrzejchm.fdb.testApp fdb_scenario_key
dart run ../../bin/fdb.dart simulator defaults delete --bundle-id dev.andrzejchm.fdb.testApp fdb_scenario_key

# --- push (app must be running, navigate to Notification Test screen first) ---
dart run ../../bin/fdb.dart tap --key go_to_notification_test_top
cat > /tmp/s33_push.apns <<'EOF'
{
  "aps": { "alert": { "title": "S33 push", "body": "fdb simulator push scenario" }, "sound": "default" },
  "deeplink": "fdbtest://scenarios/s33",
  "case": "s33"
}
EOF
dart run ../../bin/fdb.dart simulator push --bundle-id dev.andrzejchm.fdb.testApp /tmp/s33_push.apns
sleep 2
dart run ../../bin/fdb.dart describe
dart run ../../bin/fdb.dart back
```

**What to verify:**

- `appearance get` returns `APPEARANCE=light` or `APPEARANCE=dark` (not empty)
- `appearance dark` returns `APPEARANCE=dark`; second `get` confirms `APPEARANCE=dark`
- `appearance light` returns `APPEARANCE=light`; simulator visibly switches back to light
- `text-size get` returns `TEXT_SIZE=<any valid size>`
- `text-size accessibility-extra-extra-large` returns `TEXT_SIZE=accessibility-extra-extra-large`
- second `text-size get` confirms the change
- `text-size large` resets back to `TEXT_SIZE=large`
- `status-bar override` returns `STATUS_BAR_OVERRIDDEN`; status bar shows 9:41 and "fdb" carrier
- `status-bar clear` returns `STATUS_BAR_CLEARED`; status bar snaps back to real values
- `location set` returns `LOCATION_SET LAT=48.8584 LON=2.2945`; Maps shows Eiffel Tower area
- `location route` returns `LOCATION_ROUTE=City Run`; Maps blue dot starts moving
- `location clear` returns `LOCATION_CLEARED`; moving dot stops (may stay at last position)
- `defaults write` returns `DEFAULTS_WRITTEN KEY=fdb_scenario_key VALUE=hello_fdb`
- `defaults read` prints `hello_fdb`
- `defaults delete` returns `DEFAULTS_DELETED KEY=fdb_scenario_key`
- Push: `PUSH_SENT BUNDLE_ID=dev.andrzejchm.fdb.testApp`
- After push + describe on Notification Test screen: `VISIBLE TEXT:` contains `"Last foreground push"`, `"Title: S33 push"`, `"Body: fdb simulator push scenario"`, `"Deeplink: fdbtest://scenarios/s33"`

---

## S34 · tap — IgnorePointer wrapper does not leak (fdb-gfk regression)

**Purpose:** an `ElevatedButton` wrapped in `IgnorePointer(ignoring: false)`
must resolve to `TAPPED=ElevatedButton`. The pre-fix behavior was
`TAPPED=IgnorePointer` because the ancestor walk accepted `IgnorePointer` as
a fallback hittable. After the fix, `IgnorePointer` and `AbsorbPointer` are
filtered out as pass-through wrappers.

This scenario covers two paths through `findHittableElement`:

- **Path A (fast-path):** `tap --key` on the button. The matched element is
  itself interactive and hittable, so the walk is short-circuited.
- **Path B (ancestor walk):** `tap --text` on the button label. The matched
  `Text` leaf is non-interactive, so the walk runs and MUST skip the
  surrounding `IgnorePointer` to land on an interactive ancestor.

The test app exposes `key=ignore_pointer_wrapped_button` on a button wrapped
in an explicit `IgnorePointer(ignoring: false, ...)`.

```bash
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key ignore_pointer_wrapped_button
# Path A
dart run ../../bin/fdb.dart tap --key ignore_pointer_wrapped_button
# Path B
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key ignore_pointer_wrapped_button
dart run ../../bin/fdb.dart tap --text "IgnorePointer Wrapped"
```

**What to verify:**

- Path A: exits 0, `TAPPED=ElevatedButton`. Anything else (including
  `TAPPED=IgnorePointer`) is a regression.
- Path B: exits 0, `TAPPED=` is some interactive widget. The two specific
  failure modes that the fix MUST prevent are `TAPPED=IgnorePointer` (the
  fdb-gfk leak) and `TAPPED=Text` (the fdb-xdh leak). Any other widget type
  (`GestureDetector`, `InkWell`, `ElevatedButton`, etc.) is acceptable.

---

## S35 · tap — CupertinoButton coverage

**Purpose:** the closed list of interactive widgets must include
`CupertinoButton` so iOS-style apps get accurate `TAPPED=` tokens. Tapping a
`CupertinoButton` by `--key` or by `--text` on its label must resolve to
`TAPPED=CupertinoButton`.

The test app exposes `key=cupertino_button_test` on a `CupertinoButton` with
text label `"Cupertino Button"`.

```bash
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key cupertino_button_test
dart run ../../bin/fdb.dart tap --key cupertino_button_test
dart run ../../bin/fdb.dart restart
sleep 1
dart run ../../bin/fdb.dart scroll-to --key cupertino_button_test
dart run ../../bin/fdb.dart tap --text "Cupertino Button"
```

**What to verify:**

- Tap by `--key`: exits 0, `TAPPED=CupertinoButton`.
- Tap by `--text`: exits 0, `TAPPED=CupertinoButton` (the ancestor walk
  finds the named widget directly because `CupertinoButton` is in the
  closed list and there are no other interactive widgets between the
  `Text` leaf and `CupertinoButton`). `TAPPED=Text` is a regression.

---

## Adding new scenarios

When you add a new fdb command or significantly change an existing one:

1. Add a scenario section here following the pattern above.
2. Give it the next `S<n>` number.
3. Cover: setup steps, exact commands, and a **What to verify** list written
   in terms of semantic content — not just token presence.
4. Keep scenarios independent: each one navigates back to the home screen
   before finishing, so subsequent scenarios start from a known state.
