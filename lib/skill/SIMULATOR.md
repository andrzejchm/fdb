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
fdb simulator defaults write --bundle-id com.example.app featureFlag "true"
fdb simulator defaults read  --bundle-id com.example.app featureFlag   # → true
fdb simulator defaults read  --bundle-id com.example.app               # → all defaults as JSON
fdb simulator defaults delete --bundle-id com.example.app featureFlag
```

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
