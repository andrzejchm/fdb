## fdb skill: interact

UI interaction commands — screenshot, describe, tap, input, scroll, swipe, and navigation.

## Contents
- Best practices: making widgets targetable
- Selector priority
- Screenshot
- Widget tree
- Describe the current screen
- Widget selection
- Tap native UI (system dialogs)
- Tap a widget
- Long-press
- Double-tap
- Enter text
- Scroll
- Scroll to widget
- Swipe (PageView, Dismissible)
- Navigate back
- Agent workflow patterns

## Best practices: making widgets targetable

Add `ValueKey` (or any stable `Key`) to every widget you plan to target with fdb commands. Keys appear in `fdb describe` output and make `--key` targeting immune to text changes, widget tree restructuring, and localization.

```dart
// Buttons
ElevatedButton(
  key: const ValueKey('save_button'),
  onPressed: save,
  child: const Text('Save'),
)

// Text fields
TextField(
  key: const ValueKey('email_field'),
  controller: emailController,
)

// List items (use the data id, not the index — indices shift)
ListTile(
  key: ValueKey('contact_${contact.id}'),
  title: Text(contact.name),
)

// PageView pages
PageView(
  children: pages.map((p) => MyPage(key: ValueKey('page_${p.id}'), ...)).toList(),
)

// Dismissible items
Dismissible(
  key: ValueKey('todo_${todo.id}'),
  child: TodoTile(todo: todo),
)
```

Add keys to: buttons, text fields, list rows, tabs, cards, bottom-sheet handles, and any container that wraps interactive children you might need to breadcrumb in `fdb describe`.

## Selector priority

ALWAYS run `fdb describe` before any tap, input, or scroll. It shows every interactive widget, its `@N` ref, and its key in one call. Use that output — do NOT guess coordinates or target by `--text`/`--type` without checking first.

After `fdb describe`, choose a selector in this order:

1. `@N` ref — from `fdb describe`. Fastest path. A ref names one widget and keeps naming it while that widget stays on screen; it never jumps to another widget.
2. `--key` — stable across navigation changes; prefer for repeated or scripted taps. Keys are shown in `fdb describe` output.
3. `--text` — brittle if text is localised or changes. Use only when neither a ref nor a key is available.
4. `--type` — most brittle; breaks on widget type refactors. Last resort before coordinates.
5. `--at x,y` — coordinate tap. Use ONLY for elements with no other selector (native overlays, canvas). NEVER guess coordinates.

NEVER reach for `--text`, `--type`, or `--at` without first running `fdb describe` and exhausting `@N` ref and `--key` options.

## Screenshot

```bash
fdb screenshot [--output <path>] [--full]
```

Dispatches to the right capture tool per platform: `adb` (Android), `xcrun simctl` (iOS simulator), `screencapture` (macOS), `xdotool`+`import` (Linux X11), Chrome DevTools Protocol (web), or `fdb_helper` VM extension (physical iOS, Windows, Wayland). Default output: `<project>/.fdb/screenshot.png`. Output is downscaled so the longest side fits within 1200px — pass `--full` to skip downscaling. Read the file with the Read tool to view it.

Use `fdb describe` instead when you need to understand the UI for interaction — it's faster, text-based, and exposes widget refs. Use `fdb screenshot` to visually verify results after interactions.

## Widget tree

```bash
fdb tree --depth 5
fdb tree --depth 3 --user-only
```

Connects to VM service and prints the indented widget tree. `--user-only` filters to project widgets (excludes Flutter framework internals).

If this returns empty or unknown, fall back to raw websocat — see `fdb skill diagnostics`.

## Describe the current screen

Requires `fdb_helper` in the app.

```bash
fdb describe
```

Returns a compact, text-based snapshot: interactive elements with `@N` refs, ancestor breadcrumbs for context, and all visible text including TextField values. Prefer this over screenshot when you need to understand the UI and interact with it.

Example output:
```
SCREEN: Permissions
ROUTE: /settings/permissions

INTERACTIVE:
  @1 ElevatedButton "Save" key=save_btn
  ListTile "Camera · granted"
    @2 ElevatedButton "Request" key=perm_request_camera
  ListTile "Location · denied"
    @3 ElevatedButton "Request" key=perm_request_location
  Card(key=contact_card) > ListTile "John Doe"
    @4 IconButton key=call_john
    @5 IconButton key=delete_john
  @6 ListTile "Notifications · enabled" key=notif_tile

VISIBLE TEXT:
  "Manage your app permissions"
  "Permissions"
```

**Breadcrumbs:** When an interactive widget is nested inside a container with a key or text (like a `ListTile`, `Card`, `Tab`), its parent context is printed above it — this tells you *which* list item or card a button belongs to.

**ListTile handling:**
- `ListTile` with `onTap` → surfaced as its own interactive entry
- `ListTile` without `onTap` → not surfaced, but its interactive children are (with the tile as breadcrumb context)
- Display-only tiles (no `onTap`, no interactive children) → appear in VISIBLE TEXT only

**Text inputs that aren't `EditableText`** (flutter_quill, custom `TextInputClient` editors) are listed as interactive entries flagged `(editable)`, with their current text:
```
  @4 QuillRawEditor(editable) "current text"
```
JSON fields: `editable: true`, `inputClient: <StateType>`. Plain `TextField` lines are unchanged. Target them with `fdb tap @N` + `fdb input`, or `fdb input --type QuillRawEditor`.

**Disabled widgets** are flagged `(disabled)` (JSON: `enabled: false`): a button with no `onPressed`, a `Switch`/`Checkbox`/`Slider` with no `onChanged`, a `ListTile` or text field with `enabled: false`. Tapping one does nothing. Lines for enabled widgets are unchanged. A disabled custom button (its `GestureDetector` has no callbacks) is not listed at all; a selector tap on it still reports `is disabled`.
```
  @5 ElevatedButton(disabled) "Send" key=send_button
```
A send button often stays disabled until the app processes `fdb input`; tap it with `--key`/`--text` so fdb waits for it (see below).

**Foreground check.** If the app's lifecycle state isn't `resumed` (e.g. another app on the same simulator is in front), `describe` and `screenshot` print `WARNING: App is not in the foreground (lifecycle=paused). ...` (or `WARNING: App is inactive (lifecycle=inactive). ...`) on stderr. Stdout and exit code are unchanged — the output reflects the app's last frame, not what's on screen. Bring the app to the front before trusting it. Needs an fdb_helper with `ext.fdb.lifecycle`; describe JSON also carries `lifecycleState`.

**Helper version check.** `describe` prints `WARNING: The app runs fdb_helper X but the project resolves Y. Hot reload/restart does not reload it; stop and rebuild the app (fdb kill, then fdb launch).` on stderr when the running helper differs from the project's resolved `fdb_helper`, and `WARNING: fdb X with fdb_helper Y; update fdb_helper to ^X and rebuild.` when the helper is older than the CLI's major.minor. Stdout and exit code are unchanged. A helper older than 1.13 does not report its version; the warnings then say so instead of naming one. After changing `fdb_helper` in `pubspec.yaml`, run `fdb kill` and `fdb launch`. Hot reload/restart keeps the old helper.

**Refs are IDs, not positions.** `@N` names one widget instance in the running app, like agent-browser's `@eN` refs. Lines stay in top-to-bottom order, so the numbers are not 1..n and have gaps:

- A widget keeps its ref across describes while it stays mounted: rebuilds, state changes, scrolling within a list that keeps it built, a dialog on top.
- A widget that is removed or replaced (its route popped, the list rebuilt with new items, a different key or type) gets a new ref, and its old ref goes stale. Stale refs fail and never reach another widget:
  ```
  ERROR: @12 is stale: the widget was removed or rebuilt. Run fdb describe again.
  ```
- Refs are never reused while the app runs. Hot reload keeps them; hot restart starts again at `@1`.
- A list child that is not built yet (listed by describe but off screen, JSON `built: false`) also has a ref. `fdb scroll-to @N` brings it into view and it keeps the same ref once built. Tapping it before that fails with `ERROR: @N is not built on screen. Bring it into view with fdb scroll-to @N first`. Its ref goes stale when the list is rebuilt with new widgets.
- `tap`, `longpress`, `double-tap`, `input` and `scroll-to` accept `@N`. `swipe` and `wait` don't.

Run `fdb describe` again after navigation, and whenever a ref is stale. The describe JSON lists the refs from the previous describe that went stale in `removedRefs`.

A ref still names the same widget when that widget changes its label (a "Follow" button that now reads "Unfollow"). Add `--expect-text` (or `--expect-type`) to taps that would do damage (delete, submit, pay, create):

```bash
fdb tap @4 --expect-text "Save"     # fails, tapping nothing, if @4 no longer shows "Save"
```

## Widget selection

```bash
fdb select on     # enable tap-to-select overlay on device
fdb select off    # disable overlay
fdb selected      # get what widget was tapped
```

Use `select on` to interactively identify a widget's key or type by tapping it on the device screen.

## Tap native UI (system dialogs, permission sheets)

```bash
fdb native-tap --at 200,400    # tap at device coordinates (x,y)
fdb native-tap --x 200 --y 400 # same, two-flag form
```

Output: `NATIVE_TAPPED=<platform> X=<x> Y=<y>`

Platform dispatch:
- **Android**: `adb shell input tap X Y`, in physical pixels. Reaches all on-screen UI including system dialogs.
- **iOS simulator**: injects a real touch through the simulator's HID stack, the same way Simulator.app does. Coordinates are iOS points in the current screen orientation, so they match `fdb tap --at`, `fdb describe` and screenshots in portrait and in landscape. fdb reads the orientation from the simulator and rotates the touch itself. If it can't tell which way the simulator is rotated, it fails with an `ERROR` instead of tapping. Reaches anything on screen in any app, including SpringBoard: permission prompts ("Allow notifications", location), "Open in <App>?" URL confirmations, and the paste prompt. Needs Xcode only. The first tap on a machine compiles a small helper with `xcrun swiftc` (about 5-10 s) and caches it in `~/Library/Caches/fdb/` (set `FDB_CACHE_DIR` to change it).
- **iOS physical / macOS**: not supported. Use `fdb tap --at`.

native-tap only taps. It can't type; use `fdb input` for text entry. Tapping by label (`--text`) is not supported; pass coordinates.

On the iOS simulator, coordinates outside the screen fail with exit 1 and tap nothing:
```
ERROR: coordinates X,Y are outside the screen (WxH points, <orientation>)
```

WxH is the size in the current orientation, for example `874.0x402.0 points, landscapeLeft` on an iPhone 17 Pro in landscape.

If the simulator accepted the touch-down but not the touch-up, native-tap fails with an `ERROR:` and exit 1 instead of retrying, to avoid a double tap. It doesn't fall back to the in-process tap in that case.

If the helper can't be built or run, native-tap still taps, but in-process, and prints:
```
WARNING: iOS simulator HID tap unavailable (<reason>); fell back to in-process tap (UIApplication.sendEvent), which cannot reach SpringBoard system dialogs.
```
That tap reaches `UIAlertController` and other in-app native overlays only. Fix the reason to get the HID tap back. It is usually `xcode-select` pointing at the Command Line Tools instead of Xcode (`sudo xcode-select -s /Applications/Xcode.app`), or an unaccepted Xcode license.

**Getting coordinates from a screenshot.** `fdb screenshot` downscales the image so its longest side is at most 1200px, so screenshot pixels are not points. Convert:

```
points = screenshot px * (screen width in points / screenshot width in px)
```

For example, an iPhone 17 Pro is 402x874 points and its screenshot is 552x1200 px, so a button at 378,651 in the screenshot is at 275,474 points. The out-of-screen error above names the screen size in points if you don't know it.

Tap a SpringBoard dialog on the iOS simulator:
```bash
fdb screenshot                 # find the button; convert its position to points
fdb native-tap --at 275,474    # e.g. "Open" in the "Open in <App>?" alert on iPhone 17 Pro
fdb screenshot                 # verify the dialog is gone
```

For in-app alerts (`UIAlertController`), `fdb tap --at` works too:
```bash
fdb screenshot                 # locate button coordinates
fdb tap --at 285,508           # tap at those coordinates
fdb screenshot                 # verify dismissed
```

When you know which permission the app will ask for, pre-granting with `fdb grant-permission` is still more reliable than tapping the prompt (see `fdb skill data`). The system photo picker needs an app test hook; see `fdb skill simulator`.

## Tap a widget

Requires `fdb_helper` in the app.

```bash
fdb tap @3                            # tap by describe ref  ← use after fdb describe
fdb tap @3 --expect-text "Save"       # ...and fail unless @3 still shows "Save"
fdb tap --key "increment_button"      # tap by widget key    ← stable across navigation
fdb tap --text "Submit"               # tap by visible text  (only if no key)
fdb tap --type "FloatingActionButton" # tap by widget type   (last resort before coordinates)
fdb tap --at 200,400                  # tap absolute coordinates — LAST RESORT ONLY
```

Output: `TAPPED=<type|coordinates> X=<x> Y=<y>`. For `@N` the widget's describe text is appended: `TAPPED=ElevatedButton X=196.0 Y=410.0 TEXT="Save"`.

A selector tap (and `longpress`, `double-tap`, `swipe --key/--text/--type`) only lands on a point inside the matched widget that actually reaches it. If something is on top, it retries until `--timeout` (default 5s), then fails with exit 1 and taps nothing:

```
ERROR: ElevatedButton is not hittable: it is covered by ModalBarrier at 200.0,410.0. Dismiss what covers it or use --index/another selector
ERROR: ElevatedButton is scrolled out of view. Bring it into view first with fdb scroll-to
```

A selector `tap`, `longpress` or `double-tap` on a disabled widget is never dispatched. fdb retries until the app enables it (up to `--timeout`), then fails with exit 1:

```
ERROR: ElevatedButton is disabled
```

For custom buttons, disabled means the button's own `GestureDetector`/`InkWell` has no callbacks. When fdb can't tell, it treats the widget as enabled. Coordinate taps (`--at`) don't check.

`@N` goes through the same checks: the ref's widget is tapped like a selector match, never at raw coordinates. A covered or disabled one waits up to `--timeout`; one on an off-screen `PageView` page or scrolled out of its list gets the `scrolled out of view` error above. A stale or not-built ref fails at once. A ref can't be combined with `--key`/`--text`/`--type`/`--at`. These errors exit 1 and tap nothing:

```
ERROR: @12 is stale: the widget was removed or rebuilt. Run fdb describe again.
ERROR: @40 is not built on screen. Bring it into view with fdb scroll-to @40 first
ERROR: @4 is now TextButton "Delete", not "Save". Nothing was tapped. Run fdb describe again.
ERROR: fdb_helper in the app is too old for @N refs. Update fdb_helper to the version of fdb and rebuild the app.
```

## Long-press a widget

Requires `fdb_helper` in the app.

```bash
fdb longpress @5                             # long-press a describe ref
fdb longpress --key "photo_card"             # long-press by key (default 500ms)
fdb longpress --text "Hold me"              # long-press by text
fdb longpress --type "GestureDetector"      # long-press by type
fdb longpress --key "item" --duration 1000  # long-press for 1 second
fdb longpress --at 200,400 --duration 1000  # long-press at coordinates
```

Output: `LONG_PRESSED=<type|coordinates> X=<x> Y=<y>`

## Double-tap a widget

Requires `fdb_helper` in the app.

```bash
fdb double-tap @5
fdb double-tap --key "map_widget"
fdb double-tap --text "Zoom here"
fdb double-tap --type "InteractiveViewer"
fdb double-tap --type "InteractiveViewer" --index 1  # 0-based when multiple match
fdb double-tap --at 200,400
```

Output: `DOUBLE_TAPPED=<type> X=<x> Y=<y>`

## Enter text

Requires `fdb_helper` in the app.

```bash
fdb input @3 "flutter"                     # type into the field behind a describe ref
fdb input --key "search_field" "flutter"   # type into field by key  ← prefer this
fdb input --text "Search" "query text"     # type into field by its label/hint text
fdb input "fallback text"                  # type into focused field
fdb input "QA test" --action send          # type, then send the IME "send" action
fdb input --action done                    # IME action only, no text
```

`@N` must come first and be followed by the text or `--action`; a lone `@3` is typed as text into the focused field.

Output:
```
INPUT=<type> VALUE=<text>              # when text was given
IME_ACTION=<action> TARGET=<type>      # when --action was given
```
`<type>` is the matched widget with a selector (e.g. `TextField`, `QuillEditor`), or the input widget itself when using focus (e.g. `EditableText`, `QuillRawEditor`).

Tap the field first if it isn't already focused:
```bash
fdb tap --key "search_field"
fdb input --key "search_field" "flutter"
```

**Which widgets work:** any text input, not just `TextField`/`EditableText`. fdb_helper resolves the target (focused element by default, or the `--text`/`--key`/`--type`/`--index` match), then looks for a text input client on that element, then below it (`EditableText` first, then any `State` implementing `TextInputClient`), then above it. That covers flutter_quill (`QuillEditor` → `QuillRawEditorState`) and custom editors implementing `TextInputClient`/`DeltaTextInputClient`. `--text` on a Quill placeholder and `--type QuillEditor`/`--type QuillRawEditor` both resolve to the editor. With a selector, fdb never searches other branches of an ancestor: a match that holds several fields fails with the count, and a standalone `Text` next to a field (not its `labelText`/`hintText`) fails instead of typing into whichever field comes first. Target the field with `--key`, or `--type` plus `--index`.

**Mode is replace.** The field's content is replaced with `<text>`. Text goes through the client interface (`updateEditingValue`, or `updateEditingValueWithDeltas` for `DeltaTextInputClient`), so the widget's own controller and listeners run. No soft or hardware keyboard is needed. Rich-text editors keep their trailing document newline.

**`--action <name>`** calls `TextInputClient.performAction` on the same client, after the text if both are given. Valid: `send`, `done`, `newline`, `go`, `search`, `next`, `previous`, `join`, `route`, `continue`, `emergencyCall`, `none`, `unspecified`. What happens next is up to the widget:
- `EditableText`/`TextField` → `onSubmitted` / `onEditingComplete`.
- flutter_quill → forwards to `QuillEditorConfig.onPerformAction`; does nothing if the app didn't set it. In that case tap the app's send button instead (`fdb describe`, then `fdb tap @N`).
- `--action newline` does not insert a line break. Put `\n` in the text for that.

Errors name the widget and the reason:
```
ERROR: Focused element is not an editable text field: ElevatedButton is not a text input: no EditableText and no State implementing TextInputClient was found on it, below it, or above it
ERROR: enterText failed: QuillRawEditor (QuillRawEditorState) has no active text input connection ... Tap the field to focus it, then retry
ERROR: Invalid value for --action: <x>. Valid: send, done, ...
```
If the app's fdb_helper predates `--action`, the command fails saying the action was not performed — update fdb_helper and rebuild the app.

Rich-text editor (flutter_quill) example:
```bash
fdb describe                               # @4 QuillRawEditor(editable) ""
fdb tap @4                                 # focus the editor
fdb input "Hello from fdb"                 # replaces document content
fdb input --action send                    # only does something if onPerformAction is set
fdb describe                               # verify; otherwise tap the app's send button
```

## Scroll

Requires `fdb_helper` in the app.

```bash
fdb scroll down              # scroll down
fdb scroll up                # scroll up
fdb scroll left              # scroll left
fdb scroll right             # scroll right
fdb scroll down --at 200,400 # scroll at specific screen coordinates
```

Output: `SCROLLED=<DIR> DISTANCE=<n>`

## Scroll to widget

Requires `fdb_helper` in the app.

Scrolls the nearest `Scrollable` until the target widget becomes visible. Works for lazy lists (`ListView.builder`) where off-screen widgets don't exist in the element tree yet — `fdb describe` won't show them until after `scroll-to`.

```bash
fdb scroll-to @42                          # scroll a describe ref into view (also a not-built list child)
fdb scroll-to --key "list_item_42"         # scroll until widget with key is visible  ← prefer
fdb scroll-to --text "Item 42"             # scroll until widget with text is visible
fdb scroll-to --type "MyListItemWidget"    # scroll until widget of type is visible
fdb scroll-to --type "ListTile" --index 5  # scroll to the 6th ListTile (0-based)
```

Output: `SCROLLED_TO=<type> X=<x> Y=<y>`

**Tip:** Give every list item a `ValueKey` keyed on its data ID (not its index) so `scroll-to --key` works even after the list reorders.

## Swipe (PageView, Dismissible)

Requires `fdb_helper` in the app.

Use `swipe` when you need to trigger `PageView` page changes, `Dismissible` dismissals, or any gesture that requires crossing a snap/dismiss threshold. Unlike `scroll`, `swipe` targets a specific widget and uses 60% of its dimension as the default distance — enough to cross most snap thresholds.

```bash
fdb swipe left --key "photo_card"    # swipe widget left by key  ← prefer
fdb swipe right --text "Next"        # swipe widget right by text
fdb swipe up --type "Dismissible"    # swipe widget up by type
fdb swipe left                       # swipe from screen center (fallback)
fdb swipe left --at 200,400         # swipe from specific coordinates
fdb swipe left --distance 400       # custom pixel distance
```

Output: `SWIPED=<DIR> DISTANCE=<n>`

## Swipe path (freeform drawing, handwriting, signatures)

Requires `fdb_helper` in the app.

Use `swipe-path` when a gesture needs to follow a shape `swipe` can't express — a curve, a zigzag, a loop, a letter — as one continuous stroke. This is the tool for drawing canvases, signature pads, and `$1`/`$P`-style handwriting/gesture recognizers. `swipe-path` only accepts raw screen coordinates (no `--key`/`--text`/`--type` selector); run `fdb describe` first if you need to anchor the path relative to a widget's position.

```bash
fdb swipe-path --points "10,10;15,40;40,55;70,40;75,10"   # freeform path, min 2 points
fdb swipe-path --points "10,10;300,300" --precision 4      # finer interpolation (smaller = smoother)
```

Output: `SWIPED_PATH POINTS=<n>`

## Navigate back

Requires `fdb_helper` in the app.

```bash
fdb back
```

Presses the system back button, exactly like the Android back button: the app's own back handling (router, nested `AutoRouter`, `PopScope`, dialogs) decides what closes. Returns `POPPED` when the app handled it. At the root screen it exits 1 with `ERROR: Nothing in the app handled back ...`. On Android the press then goes to the OS like a real one and the app leaves the foreground (bring it back by relaunching it); on iOS and desktop the app is left alone. If back does not close a screen, a real user's back press would not either: use its on-screen back button (`fdb tap`).

## Agent workflow patterns

```bash
# Standard launch + inspect
DEVICE=$(fdb devices 2>/dev/null | grep '^DEVICE_ID=' | head -1 | sed 's/DEVICE_ID=\([^ ]*\).*/\1/')
fdb launch --device "$DEVICE" --project /path/to/flutter/app
fdb doctor                                 # verify environment before interacting
fdb describe                               # compact screen snapshot — preferred over screenshot for navigation
fdb screenshot                             # visual verification

# Describe-driven interaction (required — always start here)
fdb describe                               # ALWAYS run first — gives @N refs, keys, visible text
fdb tap @2                                 # tap by @N ref from describe output
fdb tap --key perm_request_camera          # or tap by key (stable across navigation)
fdb describe                               # re-run after navigation or a stale-ref error
# NEVER tap by --text, --type, or --at without first running fdb describe
# NEVER guess coordinates

# Full interaction loop
fdb tap --key "submit_button"
fdb longpress --key "photo_card"
fdb screenshot                             # verify after each significant action
fdb input --key "search_field" "flutter"
fdb tap --text "Search"
fdb wait --key "loading_spinner" --absent  # wait for UI state — NOT shell sleep
fdb scroll down
fdb scroll-to --key "list_item_42"
fdb swipe left --key "photo_card"
fdb back
fdb logs --tag "fdb_test" --last 20

# Form fill
fdb tap --key "username_field"
fdb input --key "username_field" "testuser"
fdb tap --key "password_field"
fdb input --key "password_field" "secret"
fdb tap --text "Login"
fdb screenshot
```
