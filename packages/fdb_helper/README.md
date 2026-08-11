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
  fdb_helper: ^1.8.0
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

### Custom bindings

If another package also customizes Flutter's binding, compose fdb's service
extensions into your application binding instead of calling
`FdbBinding.ensureInitialized()`:

```dart
import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:other_package/other_package.dart';

class AppBinding extends WidgetsFlutterBinding
    with FdbServiceExtensionsMixin, OtherBindingMixin {}

void main() {
  AppBinding();
  runApp(MyApp());
}
```

Each binding mixin that overrides `initServiceExtensions()` must call its
super implementation so every mixin in the chain can register its extensions.

Unlike the `FdbBinding.ensureInitialized()` setup above, this example
constructs `AppBinding()` unconditionally, without a `if (!kReleaseMode)`
guard: `OtherBindingMixin` (or another composed mixin) may need to run in
release builds too, and gating the whole binding would break it there.
`FdbServiceExtensionsMixin` already no-ops its own extension registration in
release mode, so it is safe to apply in all build modes.

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
