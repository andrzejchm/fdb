## fdb skill: simulator

iOS simulator control — appearance, text size, status bar, location, push notifications, and NSUserDefaults.

`fdb simulator` commands control the booted iOS simulator directly. No running app session required — commands work from any directory.

## Contents
- Best practices
- Appearance (dark / light mode)
- Dynamic Type size
- Status bar
- Location simulation
- Push notifications
- NSUserDefaults
- System prompts and the software keyboard
- Output tokens

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

fdb can't tap system UI on the iOS simulator: `fdb native-tap` and `fdb tap` inject touches inside the app process, and SpringBoard prompts run outside it. Support for tapping system dialogs is planned. Until then, keep prompts from appearing:

- **Permission prompts:** run `fdb grant-permission <perm>` BEFORE the app requests it (pass `--bundle` and `--device` to do it before launch). Covers what `xcrun simctl privacy` covers: location, location-always, photos, photos-add, camera, contacts, contacts-read, microphone, calendar, reminders, motion, media-library, siri. A grant can terminate the running app; relaunch afterwards. See `fdb skill data`.
- **Notification prompt:** NOT covered. `simctl privacy` has no notifications service, so `fdb grant-permission notifications` fails on the iOS simulator with `ERROR: 'notifications' on ios-simulator requires an external tool`. Skip the prompt in the app's debug build, or grant it with the external tool the error names.
- **Paste prompt** ("would like to paste from CoreSimulator-Bridge"): don't paste. `fdb input` sets the field text directly.
- **System photo picker:** fdb can't drive it. Add a debug-only test hook in the app (e.g. a VM extension called with `fdb ext call`) that injects a picked file.
- **Photos grant:** `fdb grant-permission photos` prints `WARNING: Photos permission via simctl is unreliable on iOS simulator.` The app may still prompt or report denied.

**Software keyboard.** Simulator connects the Mac keyboard as a hardware keyboard by default (I/O > Keyboard > Connect Hardware Keyboard, Shift+Cmd+K). With it on, iOS shows no on-screen keyboard, so `MediaQuery.viewInsets.bottom` stays 0 and layouts that react to keyboard insets (bottom-pinned inputs, padding, scroll-into-view) don't change. Don't treat that as a device-accurate result.

- `fdb input` and `fdb input --action <name>` need no keyboard.
- To show the keyboard, use I/O > Keyboard > Toggle Software Keyboard (Cmd+K) in Simulator. fdb has no command for this, and `native-tap` can't type on the keyboard.

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
