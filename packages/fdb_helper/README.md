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
