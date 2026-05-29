## fdb skill: data

App state and data commands — SharedPreferences, clean, VM extensions, and runtime permissions.

## Contents
- Best practices
- SharedPreferences
- Clean app data
- VM service extensions
- Grant, revoke, or reset runtime permissions

## Best practices

- Run `fdb shared-prefs get-all` before asserting app state in a test — know what's there before you check it.
- Seed feature flags and onboarding state with `fdb shared-prefs set` before launching a scenario, not after. This avoids race conditions where the app reads prefs before you write them.
- Run `fdb clean` + `fdb shared-prefs clear` together for a fully hermetic test scenario (clears both file storage and KV storage).
- Pre-grant permissions with `fdb grant-permission` before launching the app — OS permission dialogs are hard to dismiss reliably from fdb. Grant before the session starts.
- Use `fdb ext list` on an unfamiliar app to discover debug hooks the team has registered — you may find shortcuts for clearing caches, resetting auth state, or overriding platform behaviour.

## SharedPreferences

Requires `fdb_helper` in the app.

```bash
fdb shared-prefs get <key>                          # read one key
fdb shared-prefs get-all                            # dump all keys+values as JSON
fdb shared-prefs set <key> <value>                  # write string (default)
fdb shared-prefs set <key> <value> --type bool      # write bool
fdb shared-prefs set <key> <value> --type int       # write int
fdb shared-prefs set <key> <value> --type double    # write double
fdb shared-prefs remove <key>                       # delete one key
fdb shared-prefs clear                              # delete all keys
```

Output tokens: `PREF_VALUE=<v>`, `PREF_NOT_FOUND`, `PREF_ALL=<json>`, `PREF_ENTRY=<key>=<value>`, `PREF_SET=<key>`, `PREF_REMOVED=<key>`, `PREF_CLEARED`

Common patterns:
```bash
# Inspect before asserting
fdb shared-prefs get-all

# Seed feature flag
fdb shared-prefs set new_checkout_flow true --type bool

# Skip onboarding
fdb shared-prefs set onboarding_complete true --type bool

# Reset to first-run state
fdb shared-prefs clear
```

## Clean app data

Requires `fdb_helper` in the app.

```bash
fdb clean
```

Deletes all files inside the app's temporary directory (cache) and application support/documents directories. The app keeps running — no restart needed.

Output: `CLEANED`, `DIRS=<comma-separated paths>`, `DELETED_ENTRIES=<count>`

Use `fdb clean` to reset file-based state (downloaded assets, cached responses, SQLite databases) before a test that requires a clean slate. Combine with `fdb shared-prefs clear` to reset everything:

```bash
fdb clean
fdb shared-prefs clear
# now re-run the scenario from a first-run state
```

## VM service extensions

```bash
fdb ext list                                           # list all registered ext.* extensions
fdb ext call ext.flutter.imageCache.size               # invoke and print JSON result
fdb ext call ext.flutter.platformOverride --arg value=iOS  # pass parameters
fdb ext call ext.myapp.clearAuthCache                  # invoke app-specific extension
```

Output of `fdb ext list`:
```
EXT_LIST_COUNT=<n>
ext.dart.io.getOpenFiles
ext.flutter.debugPaint
ext.flutter.imageCache.clear
ext.flutter.imageCache.size
ext.myapp.clearAuthCache
...
```
(or `EXT_LIST_EMPTY` when no extensions are registered)

Output of `fdb ext call`: pretty-printed JSON returned by the extension.

Does not require `fdb_helper`. Works on any platform the VM service supports (macOS, iOS, Android).

Run `fdb ext list` first to discover what debug hooks are available — many teams register app-specific extensions for clearing auth caches, resetting navigation state, or overriding platform config.

## Grant, revoke, or reset runtime permissions

```bash
# Grant a permission (iOS simulator or Android)
fdb grant-permission camera
# stdout: PERMISSION_GRANTED=camera

# Revoke a permission
fdb grant-permission camera --revoke
# stdout: PERMISSION_REVOKED=camera

# Reset a single permission (re-prompts on next access)
fdb grant-permission camera --reset
# stdout: PERMISSION_RESET=camera

# Reset ALL permissions for the app
fdb grant-permission --reset-all
# stdout: PERMISSION_RESET_ALL=true

# Override bundle ID / package name
fdb grant-permission --bundle com.example.app camera

# Pre-grant before launch on a specific iOS simulator
fdb grant-permission camera --bundle com.example.app --device <simulator_udid>
```

Supported permission tokens: `camera`, `microphone`, `location`, `location-always`, `contacts`, `contacts-read`, `photos`, `photos-add`, `calendar`, `reminders`, `motion`, `media-library`, `siri` (iOS), `notifications` (Android), `screen-capture` (macOS).

**Platform support:**
- iOS simulator: full grant / revoke / reset support. Pass `--bundle` + `--device` to pre-grant before the app is running.
- Android: full grant / revoke / reset support.
- Physical iOS: not supported.
- macOS: `--reset` only; grant/revoke emit `WARNING:` and exit 1.

A successful iOS simulator grant emits `WARNING: Permission change may have terminated the app. Run \`fdb reload\` or \`fdb launch\` to restart.` on stderr — this is expected.

**Pre-grant pattern for automated tests:**
```bash
# Grant all needed permissions before launching
fdb grant-permission camera --bundle com.example.app --device <simulator_udid>
fdb grant-permission microphone --bundle com.example.app --device <simulator_udid>
fdb launch --device <simulator_udid> --project .
# No permission dialogs will appear during the test
```
