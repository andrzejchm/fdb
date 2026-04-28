# test_app

The fdb test app — a fixture used by `task test:*` smoke tests and
contributor-driven manual verification of fdb commands across platforms
(Android, iOS sim, iOS physical, macOS, web).

## Setup

```bash
flutter pub get
fdb launch --device <device_id>
```

## iOS physical device

Following the flutter/packages convention, the test app's `.pbxproj` does
not hardcode `DEVELOPMENT_TEAM`. To run on a physical iPhone or iPad:

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target → **Signing & Capabilities**
3. Set **Team** to your own Apple Developer team
4. The bundle ID `dev.andrzejchm.fdb.testApp` is taken — you may need to
   change it to one available under your team (e.g. `<your-domain>.fdbTestApp`)

Close Xcode, then `fdb launch --device <udid>`.
