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

1. `@N` ref — use immediately from the current `fdb describe` output. Fastest path; refs reset on navigation.
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

Returns a compact, text-based snapshot: interactive elements with stable `@N` refs, ancestor breadcrumbs for context, and all visible text including TextField values. Prefer this over screenshot when you need to understand the UI and interact with it.

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

**Refs reset on navigation.** Always re-run `fdb describe` after navigating to get fresh refs.

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
- **Android** — `adb shell input tap X Y`. Reaches all on-screen UI including system dialogs.
- **iOS simulator** — falls back to `fdb tap --at` (in-process). Reaches `UIAlertController` and in-app native overlays. **Cannot reach SpringBoard dialogs** (URL scheme confirmations, OS permission prompts).
- **iOS physical / macOS** — not supported. Use `fdb tap --at`.

For iOS in-app alerts (`UIAlertController`):
```bash
fdb screenshot                 # locate button coordinates
fdb tap --at 285,508           # tap at those coordinates
fdb screenshot                 # verify dismissed
```

For OS-level permission prompts on iOS simulator, use `fdb grant-permission` instead — see `fdb skill data`.

## Tap a widget

Requires `fdb_helper` in the app.

```bash
fdb tap @3                            # tap by describe ref  ← use after fdb describe
fdb tap --key "increment_button"      # tap by widget key    ← stable across navigation
fdb tap --text "Submit"               # tap by visible text  (only if no key)
fdb tap --type "FloatingActionButton" # tap by widget type   (last resort before coordinates)
fdb tap --at 200,400                  # tap absolute coordinates — LAST RESORT ONLY
```

Output: `TAPPED=<type|coordinates> X=<x> Y=<y>`

## Long-press a widget

Requires `fdb_helper` in the app.

```bash
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
fdb input --key "search_field" "flutter"   # type into field by key  ← prefer this
fdb input --text "Search" "query text"     # type into field by label text
fdb input "fallback text"                  # type into focused field
```

Output: `INPUT=<type> VALUE=<text>`

Tap the field first if it isn't already focused:
```bash
fdb tap --key "search_field"
fdb input --key "search_field" "flutter"
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

Calls `Navigator.maybePop()` on the root navigator. Returns `POPPED` on success, or an error if already at the root route.

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
fdb describe                               # re-run after every navigation — refs reset on route change
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
