## fdb skill: simulator

iOS simulator control — appearance, text size, status bar, location, push notifications, and NSUserDefaults.

`fdb simulator` commands control one iOS simulator directly, picked as described in "Which simulator these commands target". No running app is required: with one booted simulator and no session they work from any directory.

## Contents
- Which simulator these commands target
- Best practices
- Appearance (dark / light mode)
- Dynamic Type size
- Status bar
- Location simulation
- Push notifications
- NSUserDefaults
- System prompts and the software keyboard
- Output tokens

## Which simulator these commands target

Every `fdb simulator` subcommand acts on exactly one simulator, chosen in this order:

1. `--device <udid>`, accepted by every `fdb simulator` subcommand. The simulator must exist and be booted. Get UDIDs from `fdb devices` or `xcrun simctl list devices booted`.
2. The session's device (`.fdb/device.txt`, written by `fdb launch --device <udid>` / `fdb attach`), when it is a known iOS simulator. If that simulator is not booted the command fails; it never falls back to another simulator. A session device that is not an iOS simulator (Android, macOS, a physical iPhone) is ignored.
3. The only booted iOS simulator. Booted watchOS, tvOS and visionOS simulators are not counted here; they are used only when named explicitly with `--device` or by the session.

`push` and `defaults` also read the bundle ID from the session (`app_id.txt`) when `--bundle-id` is omitted. fdb does not use simctl's `booted` alias.

**Where the session comes from.** fdb finds it the way other fdb commands do:

- `fdb --session-dir <path>/.fdb simulator ...` uses that directory as given. The flag is global, so it goes BEFORE `simulator`.
- Otherwise fdb walks up from the current directory and uses the nearest `.fdb` with a live session (a running app or controller).
- If no live session exists anywhere above, the `.fdb` in the current directory is still read when present. A leftover `device.txt` from a dead session in the current directory is therefore still honored (and fails if that simulator is shut down), while the same leftover one level down in a subdirectory is skipped.

**Stale session.** If a dead session keeps pointing at the wrong simulator, run `fdb kill` (it removes `.fdb/device.txt`), delete `.fdb/`, or pass `--device <udid>`.

**`--device` position.** `--device` goes after the subcommand and action, not before them:

```bash
fdb simulator status-bar override --time 9:41 --device <udid>
fdb simulator appearance dark --device <udid>
```

`fdb simulator --device <udid> appearance dark` is not supported.

With two simulators booted, target the one your app runs on:

```bash
fdb --session-dir path/to/.fdb simulator status-bar override --time 9:41   # session's simulator
fdb simulator appearance dark --device <udid>                              # explicit simulator
```

With more than one booted simulator and neither a session simulator nor `--device`, the command fails and lists them:

```
ERROR: Multiple booted iOS simulators and no fdb session simulator to choose from. Pass --device <udid> with one of:
  <UDID> (<name>)
  <UDID> (<name>)
```

A session simulator that is not booted fails with `ERROR: The session simulator <UDID> (<name>) is not booted (state: Shutdown). Boot it, or target another booted simulator with --device <udid>.` With none booted the command fails with `ERROR: No booted iOS simulator. Boot one with: xcrun simctl boot <udid>`.

## Best practices

- **Override the status bar before every App Store screenshot.** Use `9:41`, full battery, full signal — this is the Apple-standard marketing time. Run `fdb simulator status-bar clear` to restore after.
- **Test dark mode before shipping.** Run through your key screens with `fdb simulator appearance dark`. Many colour and contrast bugs only appear in dark mode.
- **Test large text before shipping.** Run `fdb simulator text-size extra-extra-extra-large` and check for layout overflows, truncated labels, and clipped buttons. Accessibility text sizes frequently expose fixed-height containers.
- **Use `fdb simulator defaults write` to toggle feature flags during development** instead of rebuilding. Write the flag, hot-reload, verify, reset — much faster than rebuilding for each toggle.
- **Use `fdb simulator push` to test notification-deep-link flows** without needing a real push backend. Set the `deeplink` payload field to your custom URL scheme to exercise end-to-end navigation.
- **Use `fdb simulator location set` to test geo-dependent features** without physically moving. Test edge cases: international coordinates, coordinates at permission boundaries, 0,0 (null island).

## Appearance (dark / light mode)

```bash
fdb simulator appearance dark
fdb simulator appearance light
fdb simulator appearance get    # → APPEARANCE=dark
```

Changes affect all apps system-wide instantly.

## Dynamic Type size

```bash
fdb simulator text-size extra-small
fdb simulator text-size small
fdb simulator text-size medium
fdb simulator text-size large             # system default
fdb simulator text-size extra-large
fdb simulator text-size extra-extra-large
fdb simulator text-size extra-extra-extra-large
fdb simulator text-size accessibility-medium
fdb simulator text-size accessibility-large
fdb simulator text-size accessibility-extra-large
fdb simulator text-size accessibility-extra-extra-large
fdb simulator text-size accessibility-extra-extra-extra-large
fdb simulator text-size get              # → TEXT_SIZE=large
```

Affects all apps system-wide. Reset with `fdb simulator text-size large`.

## Status bar

```bash
# Override for clean screenshots
fdb simulator status-bar override \
  --time "9:41" \
  --battery-state charged \
  --battery-level 100 \
  --wifi-bars 3 \
  --cellular-bars 4 \
  --operator "Carrier"

# Restore to real status bar
fdb simulator status-bar clear
```

## Location simulation

```bash
fdb simulator location set 48.8584,2.2945    # set fixed location (Eiffel Tower)
fdb simulator location route "Freeway Drive" # animate along a named route
fdb simulator location route "City Run"
fdb simulator location clear                 # stop simulation, use real location
```

## Push notifications

Requires notification permission granted in the app.

```bash
cat > /tmp/push.apns <<'EOF'
{
  "aps": {
    "alert": { "title": "Hello", "body": "Test notification" },
    "sound": "default"
  },
  "deeplink": "myapp://some/path"
}
EOF

fdb simulator push /tmp/push.apns                               # auto-detects bundle ID from session
fdb simulator push --bundle-id com.example.app /tmp/push.apns  # explicit bundle ID
```

## NSUserDefaults

Read/write/delete app settings without rebuilding. Useful for toggling feature flags and overriding configuration during development.

```bash
fdb simulator defaults write --bundle-id com.example.app featureFlag "true"              # string (default)
fdb simulator defaults write --bundle-id com.example.app featureFlag true --type bool    # string|int|float|bool
fdb simulator defaults read  --bundle-id com.example.app featureFlag   # → true
fdb simulator defaults read  --bundle-id com.example.app               # → all defaults as JSON
fdb simulator defaults delete --bundle-id com.example.app featureFlag
```

## System prompts and the software keyboard

`fdb native-tap --at x,y` taps system UI on the iOS simulator. It injects the touch through the simulator's HID stack, so it reaches SpringBoard prompts that run outside the app: permission prompts, "Open in <App>?" URL confirmations, the paste prompt. Coordinates are points in portrait screen orientation (in landscape they differ from `fdb tap --at`); see `fdb skill interact` for converting screenshot pixels. `fdb tap` still injects inside the app process and can't reach these prompts.

Tapping a prompt means finding its buttons on a screenshot, so avoid the prompt when you can:

- **Permission prompts:** run `fdb grant-permission <perm>` BEFORE the app requests it (pass `--bundle` and `--device` to do it before launch). When you know the permission, this is more reliable than tapping the prompt. Covers what `xcrun simctl privacy` covers: location, location-always, photos, photos-add, camera, contacts, contacts-read, microphone, calendar, reminders, motion, media-library, siri. A grant can terminate the running app; relaunch afterwards. See `fdb skill data`.
- **Notification prompt:** `simctl privacy` has no notifications service, so `fdb grant-permission notifications` fails on the iOS simulator with `ERROR: 'notifications' on ios-simulator requires an external tool`. Tap "Allow" with `fdb native-tap`, skip the prompt in the app's debug build, or grant it with the external tool the error names.
- **Paste prompt** ("would like to paste from CoreSimulator-Bridge"): `fdb native-tap` can tap "Allow Paste", but you rarely need to paste. `fdb input` sets the field text directly.
- **System photo picker:** add a debug-only test hook in the app (e.g. a VM extension called with `fdb ext call`) that injects a picked file. Driving the picker by coordinates is fragile.
- **Photos grant:** `fdb grant-permission photos` prints `WARNING: Photos permission via simctl is unreliable on iOS simulator.` The app may still prompt or report denied; tap the prompt with `fdb native-tap` if it does.

If native-tap prints `WARNING: iOS simulator HID tap unavailable (...)`, it fell back to an in-process tap that can't reach these prompts. The reason in the warning says what failed (it needs Xcode and `xcrun swiftc`).

**Software keyboard.** Simulator connects the Mac keyboard as a hardware keyboard by default (I/O > Keyboard > Connect Hardware Keyboard, Shift+Cmd+K). With it on, iOS shows no on-screen keyboard, so `MediaQuery.viewInsets.bottom` stays 0 and layouts that react to keyboard insets (bottom-pinned inputs, padding, scroll-into-view) don't change. Don't treat that as a device-accurate result.

- `fdb input` and `fdb input --action <name>` need no keyboard.
- To show the keyboard, use I/O > Keyboard > Toggle Software Keyboard (Cmd+K) in Simulator. fdb has no command for this. Use `fdb input` for text, not `native-tap`.

## Output tokens

- `APPEARANCE=dark|light`
- `TEXT_SIZE=<size>`
- `STATUS_BAR_OVERRIDDEN` / `STATUS_BAR_CLEARED`
- `LOCATION_SET LAT=<lat> LON=<lon>`
- `LOCATION_ROUTE=<scenario>`
- `LOCATION_CLEARED`
- `PUSH_SENT BUNDLE_ID=<id>`
- `DEFAULTS_WRITTEN KEY=<key> VALUE=<value>`
- `DEFAULTS_DELETED KEY=<key>`
