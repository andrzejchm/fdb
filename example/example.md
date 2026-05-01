## Basic usage

```bash
# List connected devices
fdb devices

# Launch your app on a connected device
fdb launch --device <device_id> --project /path/to/flutter/app

# Take a screenshot
fdb screenshot

# Hot reload after code changes
fdb reload

# Inspect the widget tree
fdb tree --depth 5 --user-only

# Read filtered logs
fdb logs --tag "MyFeature" --last 30

# Tap a widget by its text
fdb tap --text "Submit"

# Enter text into a focused field
fdb input "Hello, world!"

# Kill the app
fdb kill
```

## Widget interaction setup

Add `fdb_helper` to your Flutter app for tap, input, scroll commands:

```yaml
# pubspec.yaml
dev_dependencies:
  fdb_helper: ^1.6.0
```

```dart
// main.dart
import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';

void main() {
  if (!kReleaseMode) {
    FdbBinding.ensureInitialized();
  }
  runApp(MyApp());
}
```
