## fdb skill: diagnostics

Logging, crash records, and debugging tools — app logs, native system logs, crash reports, websocat fallback, and debugging best practices.

## Contents
- Best practices: instrumentation
- App logs
- Native system logs (Android logcat / iOS syslog / macOS log)
- OS-level crash and OOM records
- Webview debugging
- Fallback: raw websocat

## Best practices: instrumentation

**Use `debugPrint`, not `log()` from `dart:developer`:**
- `debugPrint(...)` goes to stdout → captured in `.fdb/logs.txt` → visible via `fdb logs`
- `dart:developer` `log()` goes to the Dart DevTools protocol only — invisible to `fdb logs`

```dart
// GOOD — appears in fdb logs
debugPrint('[Auth-DEBUG] token refreshed, expires=${token.expiry}');

// BAD — invisible to fdb logs
developer.log('token refreshed', name: 'Auth');
```

**Use consistent tag prefixes so you can filter precisely:**
```dart
debugPrint('[Checkout-DEBUG] cart total=$total items=${cart.length}');
debugPrint('[Checkout-DEBUG] payment result=$result');
```
Then: `fdb logs --tag "Checkout-DEBUG" --last 50`

**Log at boundaries, not inside loops:** log on entering/leaving a screen, after each network call, and on state transitions. Avoid per-frame logging.

**When the app crashes or is killed silently:** check `fdb syslog` and `fdb crash-report` before Crashlytics — jetsam kills and LMK events never reach crash reporting SDKs.

## App logs

```bash
fdb logs --tag "MyTag" --last 50
fdb logs --tag "DEBUG" --last 100
fdb logs --last 200              # tail without tag filter
```

Reads from the tee'd log file at `.fdb/logs.txt`. Use `--tag` to grep for specific tags.

## Native system logs (Android logcat / iOS syslog / macOS log)

```bash
fdb syslog --since 5m --last 50            # last 50 lines from the past 5 minutes
fdb syslog --predicate jetsam              # filter by substring
fdb syslog --follow                        # stream live, exits on Ctrl-C
```

Use this to diagnose native crashes that don't reach Crashlytics or appear in `fdb logs` — iOS jetsam kills, Android low-memory-killer events, kernel-level errors. Dispatches per platform: `adb logcat` (Android), `xcrun simctl spawn <udid> log` (iOS simulator), `idevicesyslog` (iOS physical, requires `brew install libimobiledevice`), or host `log` (macOS).

Flags:
- `--since <duration>` — time window (`30s`, `5m`, `1h`); default `5m`. Not valid with `--follow`.
- `--predicate <substring>` — substring match across platforms (post-filtered for adb / idevicesyslog, native NSPredicate for `log show`).
- `--last <n>` — cap output to last N lines. Not valid with `--follow`.
- `--follow` — stream live, exit cleanly on Ctrl-C.

Output is the raw native log format — not parsed into fdb tokens. Errors print `ERROR: ...` (e.g. `ERROR: idevicesyslog not found. Install: brew install libimobiledevice`).

## OS-level crash and OOM records

```bash
fdb crash-report                           # most recent record, last 1h
fdb crash-report --last 30m               # custom time window
fdb crash-report --all                    # all crash sources in window
fdb crash-report --app-id com.example.app # explicit bundle id / package name
```

Fetches jetsam kills, Android LMK events, and native crash files that **never reach Crashlytics**. Works after the app has died — no running session required, only `.fdb/platform.txt`.

App id is auto-read from `.fdb/app_id.txt` (written by `fdb launch`). Pass `--app-id` to override.

Output tokens: `CRASH_REPORT_FOUND ENTRIES=N` (followed by `---` / `LABEL=` / optional `FILE=` / raw text per entry) or `CRASH_REPORT_NONE`. Errors include install hints when a required platform tool is missing.

**Diagnostic flow when the app disappears silently:**
```bash
fdb crash-report          # check for jetsam / LMK in the last hour
fdb syslog --since 10m --predicate jetsam   # broader system context
fdb syslog --since 10m --predicate "your.bundle.id"
```

## Webview debugging

For webview issues, inject diagnostic JS via `controller.evaluateJavascript()`:
- In `onWebviewCreated` — runs before page loads
- In `onPageFinishedLoading` — runs after page is ready

Wire up all webview callbacks for logging: `onConsoleMessage`, `onReceivedError`, `onReceivedHttpError`, `onNavigationResponse`, `onCreateWindow`.

Use `agent-browser --headed` for testing webview behaviour in a real browser with JS injection.

## Fallback: raw websocat

If fdb's VM service commands fail or return unexpected results, communicate with the VM service directly using `websocat`:

```bash
# Get VM service URI
VM_URI=$(fdb status 2>/dev/null | grep VM_SERVICE_URI | cut -d= -f2)

# Get isolate IDs
echo '{"jsonrpc":"2.0","method":"getVM","params":{},"id":"1"}' \
  | websocat -n1 -B 10485760 "$VM_URI"

# Widget tree (try the second isolate if the first returns null)
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.getRootWidgetSummaryTree","params":{"isolateId":"isolates/<ID>","objectGroup":"g"},"id":"2"}' \
  | websocat -n1 -B 10485760 "$VM_URI"

# Enable widget selection overlay
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.show","params":{"isolateId":"isolates/<ID>","enabled":"true"},"id":"3"}' \
  | websocat -n1 "$VM_URI"

# Get selected widget info
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.getSelectedSummaryWidget","params":{"isolateId":"isolates/<ID>","objectGroup":"g"},"id":"4"}' \
  | websocat -n1 -B 1048576 "$VM_URI"
```

**Key gotchas:**
- Apps have multiple isolates — try each until one returns a non-null widget tree.
- Use `-B 10485760` for large responses (widget trees from complex apps easily exceed the default buffer).
- Both `http://` and `ws://` URI forms work with websocat.
