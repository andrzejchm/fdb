# fdb_helper

Flutter package for [fdb (Flutter Debug Bridge)](https://pub.dev/packages/fdb) — a CLI tool that lets AI agents interact with running Flutter apps on device.

`fdb_helper` registers VM service extensions that enable:
- Widget tap, long-press, swipe, scroll, text input
- Widget tree inspection and screen description
- SharedPreferences read/write/clear
- App cache and data directory cleanup
- Widget selection mode toggle

## Setup

Add to your Flutter app's `pubspec.yaml`:

```yaml
dev_dependencies:
  fdb_helper: ^1.1.2
```

Initialize in `main.dart`:

```dart
import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';

void main() {
  if (!kReleaseMode) {
    FdbBinding.ensureInitialized();
  }
  runApp(MyApp());
}
```

Then run `flutter pub get` and relaunch the app.

## Build-mode behavior

- **Android debug/profile**: compiles the real native tap implementation. Flutter's Android `profile` build type falls back to the debug plugin variant when the plugin does not publish a profile variant.
- **Android release**: compiles a stub `FdbHelperNativeTapImpl`; `fdb native-tap` falls back to Flutter gestures and cannot reach native overlays.
- **iOS/macOS debug**: compiles the real native tap implementation.
- **iOS/macOS release**: compiles a safe stub and excludes the private iOS native tap Objective-C files from the pod target.
- **iOS/macOS profile**: uses the same safe stub by default. Flutter's default CocoaPods setup maps `Profile` to `:release`, so profile does **not** get the real native tap path unless the consuming app opts in.

If you need the real native tap path in an Apple `Profile` build for local/dev-only testing, override the `fdb_helper` pod target in your app's `Podfile`.

For **iOS** `Profile` builds, add the Swift/ObjC flags and clear the excluded-source override for the `fdb_helper` pod target:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    next unless target.name == 'fdb_helper'

    target.build_configurations.each do |config|
      next unless config.name == 'Profile'

      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) FDB_HELPER_NATIVE_TAP_REAL'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = '$(inherited) FDB_HELPER_NATIVE_TAP_REAL=1'
      config.build_settings['EXCLUDED_SOURCE_FILE_NAMES'] = ''
    end
  end
end
```

For **macOS** `Profile` builds, only the Swift compilation condition is needed:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    next unless target.name == 'fdb_helper'

    target.build_configurations.each do |config|
      next unless config.name == 'Profile'

      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) FDB_HELPER_NATIVE_TAP_REAL'
    end
  end
end
```

Only use that override in internal/dev builds. Do not ship the real Apple native tap implementation in production binaries.

## Usage

Once `fdb_helper` is set up, all fdb commands that require it will work:

```bash
fdb tap --key "submit_button"
fdb input --key "search_field" "hello"
fdb scroll down
fdb shared-prefs set onboarding_done true --type bool
fdb shared-prefs get-all
fdb clean
```

See [fdb on pub.dev](https://pub.dev/packages/fdb) for the full command reference.

## License

MIT
