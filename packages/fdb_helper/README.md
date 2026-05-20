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
  fdb_helper: ^1.7.1
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

- **Debug** (all platforms): compiles the real native tap implementation.
- **Profile** (all platforms): compiles the real native tap implementation. Profile is intended for on-device profiling/internal distribution (Firebase App Distribution, TestFlight internal), so `fdb native-tap` works there.
- **Release** (all platforms): compiles a safe stub. iOS/macOS exclude the private Objective-C native tap implementation from the pod target. Android compiles a stub via Gradle `src/release` source sets. App Store / Play Store binaries no longer ship the private-API native tap.

The Apple Profile selection works because `fdb_helper` keys its compile flags on the Xcode configuration name (`Profile`) rather than on the CocoaPods configuration type, so Flutter's default `'Profile' => :release` Podfile mapping does not turn Profile into the release stub.

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
