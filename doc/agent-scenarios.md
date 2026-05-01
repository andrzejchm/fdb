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

**After tap by text:** exits 0, output contains `TAPPED=ElevatedButton`.

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

```bash
dart run ../../bin/fdb.dart tap --key disappearing_button
```

**What to verify:**

- Exits 0
- Output contains `TAPPED=ElevatedButton`
- After the tap, running `fdb describe` no longer shows `key=disappearing_button`

---

## S8 · input — type into a TextField

**Purpose:** text input lands in the right field and is readable back.

```bash
dart run ../../bin/fdb.dart input --key test_input "hello fdb"
dart run ../../bin/fdb.dart describe
```

**What to verify:**

- `input` command exits 0 with `INPUT=TextField VALUE=hello fdb`
- `describe` INTERACTIVE entry for `key=test_input` shows `"hello fdb"` in its
  text field
- `VISIBLE TEXT:` contains `"hello fdb"`

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
dart run ../../bin/fdb.dart tap --key show_delayed
dart run ../../bin/fdb.dart wait --key delayed_button --timeout 5000
```

**What to verify:**

- `wait` exits 0 (the button appears after ~2 s, well within 5 s timeout)
- Output contains `WAIT_FOUND`
- Running `fdb describe` after this shows `key=delayed_button` in `INTERACTIVE:`

---

## S15 · wait — absent guard

**Purpose:** `fdb wait --absent` resolves when an element disappears.

```bash
# disappearing_button removes itself when tapped
dart run ../../bin/fdb.dart scroll-to --key disappearing_button
dart run ../../bin/fdb.dart tap --key disappearing_button &
dart run ../../bin/fdb.dart wait --key disappearing_button --absent --timeout 3000
```

**What to verify:**

- `wait --absent` exits 0 with `WAIT_ABSENT`

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

- `swipe` exits 0 with `SWIPED=left`
- Second `describe` VISIBLE TEXT shows `"Page 2"` instead of `"Page 1"`

---

## S17 · status and kill

**Purpose:** status reports the app as running; kill stops it cleanly.

```bash
dart run ../../bin/fdb.dart status
```

**What to verify:** `RUNNING=true`, `PID=` and `VM_SERVICE_URI=` are present.

```bash
dart run ../../bin/fdb.dart kill
dart run ../../bin/fdb.dart status
```

**After kill:** `RUNNING=false`.

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

## Adding new scenarios

When you add a new fdb command or significantly change an existing one:

1. Add a scenario section here following the pattern above.
2. Give it the next `S<n>` number.
3. Cover: setup steps, exact commands, and a **What to verify** list written
   in terms of semantic content — not just token presence.
4. Keep scenarios independent: each one navigates back to the home screen
   before finishing, so subsequent scenarios start from a known state.
