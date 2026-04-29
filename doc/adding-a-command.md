# Adding a New Command

Worked example: a hypothetical `fdb wakeup` command that wakes a sleeping device. Two arguments: `--device` (required) and `--brightness` (optional, default 100).

## 1. Core: `lib/core/commands/wakeup.dart`

```dart
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

typedef WakeupInput = ({String device, int brightness});

sealed class WakeupResult extends CommandResult {
  const WakeupResult();
}

class WakeupSuccess extends WakeupResult {
  final int brightness;
  const WakeupSuccess(this.brightness);
}

class WakeupDeviceNotFound extends WakeupResult {
  final String device;
  const WakeupDeviceNotFound(this.device);
}

class WakeupError extends WakeupResult {
  final String message;
  const WakeupError(this.message);
}

Future<WakeupResult> wakeupDevice(WakeupInput input) async {
  try {
    final response = await vmServiceCall(
      'ext.fdb.wakeup',
      params: {'device': input.device, 'brightness': '${input.brightness}'},
    );
    final result = unwrapRawExtensionResult(response);
    if (result is Map<String, dynamic>) {
      if (result['status'] == 'Success') {
        return WakeupSuccess(input.brightness);
      }
      if (result['error'] == 'device not found') {
        return WakeupDeviceNotFound(input.device);
      }
      return WakeupError(result['error'] as String? ?? 'unknown');
    }
    return WakeupError('Unexpected response: $result');
  } catch (e) {
    return WakeupError(e.toString());
  }
}
```

Notes:
- Input is a record. Empty record `()` if no args.
- Result is sealed for exhaustive matching.
- Never throws across the public API. `try`/`catch` translates exceptions to `WakeupError`.
- No `dart:io`, no `package:args`, no stdout/stderr writes.

## 2. CLI adapter: `lib/cli/adapters/wakeup_cli.dart`

```dart
import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/wakeup.dart';

Future<int> runWakeupCli(List<String> args) =>
    runCliAdapter(_buildParser(), args, _execute);

ArgParser _buildParser() => ArgParser()
  ..addOption('device', help: 'Target device ID')
  ..addOption('brightness', defaultsTo: '100', help: 'Brightness 0-100');

Future<int> _execute(ArgResults r) async {
  final device = r.option('device');
  if (device == null) {
    stderr.writeln('ERROR: --device is required');
    return 1;
  }

  final rawBrightness = r.option('brightness') ?? '100';
  final brightness = int.tryParse(rawBrightness);
  if (brightness == null) {
    stderr.writeln('ERROR: Invalid value for --brightness: $rawBrightness');
    return 1;
  }

  final result = await wakeupDevice((device: device, brightness: brightness));
  return _format(result);
}

int _format(WakeupResult result) {
  switch (result) {
    case WakeupSuccess(:final brightness):
      stdout.writeln('AWAKE BRIGHTNESS=$brightness');
      return 0;
    case WakeupDeviceNotFound(:final device):
      stderr.writeln('ERROR: Device not found: $device');
      return 1;
    case WakeupError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
```

Notes:
- `runCliAdapter` handles `--help`/`-h` and `FormatException` automatically. Don't add a help flag.
- ArgParser stores values as strings. Parse them in `_execute`.
- Required options: explicit null-check. Verbatim wording for the error message.
- Cross-flag validation lives here, not in core.
- `_format` is exhaustive — Dart fails compilation if a sealed variant is missed.

## 3. Wire into dispatcher: `bin/fdb.dart`

Add the import alphabetically and a `case` in `_runCommand`:

```dart
import 'package:fdb/cli/adapters/wakeup_cli.dart';
// ...
case 'wakeup':
  return runWakeupCli(args);
```

## 4. Update top-level usage

Add a line to the `usage` const in `bin/fdb.dart`:

```
  wakeup      Wake the device (--device required, --brightness optional)
```

## 5. README commands table

Add a row to `README.md` under "Commands".

## Verifying

- `dart analyze lib/ bin/ test/` → no issues.
- `dart run bin/fdb.dart wakeup --help` → exit 0, prints `--device` and `--brightness`.
- `dart run bin/fdb.dart wakeup` → `ERROR: --device is required`, exit 1.
- `dart run bin/fdb.dart wakeup --device foo --brightness abc` → `ERROR: Invalid value for --brightness: abc`, exit 1.
