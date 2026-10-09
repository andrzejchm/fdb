import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/simulator/sim_appearance.dart';
import 'package:fdb/core/commands/simulator/sim_defaults.dart';
import 'package:fdb/core/commands/simulator/sim_location.dart';
import 'package:fdb/core/commands/simulator/sim_push.dart';
import 'package:fdb/core/commands/simulator/sim_status_bar.dart';
import 'package:fdb/core/commands/simulator/sim_text_size.dart';
import 'package:fdb/core/process_utils.dart';

/// Resolves the bundle ID from the explicit CLI option or the fdb session.
///
/// Returns null if no bundle ID could be determined.
String? _resolveBundleId(String? explicit) => explicit ?? readAppId();

const _deviceHelp = "Target simulator UDID (default: the fdb session's device, else the only booted simulator)";

const _usage = '''
Usage: fdb simulator <subcommand> [args] [--device <udid>]

Subcommands:
  appearance  dark|light|get        Toggle or query dark/light mode
  push        <payload.apns>        Send a simulated push notification
  location    set|route|clear       Simulate GPS location
  text-size   <size>|get            Set or query Dynamic Type content size
  status-bar  override|clear        Override or clear status bar
  defaults    read|write|delete     Read/write/delete NSUserDefaults

Options (all subcommands):
  --device <udid>   $_deviceHelp
''';

/// CLI adapter for `fdb simulator <subcommand>`.
Future<int> runSimulatorCli(List<String> args) async {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(_usage);
    return 0;
  }

  final subcommand = args[0];
  final subArgs = args.sublist(1);

  switch (subcommand) {
    case 'appearance':
      return _runAppearance(subArgs);
    case 'push':
      return _runPush(subArgs);
    case 'location':
      return _runLocation(subArgs);
    case 'text-size':
      return _runTextSize(subArgs);
    case 'status-bar':
      return _runStatusBar(subArgs);
    case 'defaults':
      return _runDefaults(subArgs);
    default:
      stderr.writeln('ERROR: Unknown simulator subcommand: $subcommand');
      stderr.writeln(_usage);
      return 1;
  }
}

// ---------------------------------------------------------------------------
// shared arg handling
// ---------------------------------------------------------------------------

/// Body of a simulator adapter: parsed [results], the positional arguments
/// ([positional], negative numbers preserved) and the `--device` UDID.
typedef _SimulatorRun = Future<int> Function(ArgResults results, List<String> positional, String? device);

final _negativeNumber = RegExp(r'^-\.?\d[\d.,\-+eE]*$');
const _negativeSentinel = '\u0000neg';

/// Runs a simulator adapter with a `--device <udid>` option.
///
/// `package:args` rejects positional values that start with `-` (negative
/// coordinates such as `-33.86,151.21`, or `defaults write key -1`) as unknown
/// short options. Before parsing, `--device` is pulled out of [args] and
/// negative-number positionals are swapped for placeholders that are restored
/// in the `positional` list handed to [execute]. `--device` is still declared
/// on [parser] so it shows up in `--help`.
Future<int> _runSimulatorAdapter(
  ArgParser parser,
  List<String> args,
  String usage,
  _SimulatorRun execute,
) async {
  parser.addOption('device', valueHelp: 'udid', help: _deviceHelp);

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('$usage\n\nOptions:\n${parser.usage}');
    return 0;
  }

  String? device;
  final negatives = <String>[];
  final prepared = <String>[];
  var expectsValue = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (expectsValue) {
      prepared.add(arg);
      expectsValue = false;
    } else if (arg == '--') {
      prepared.addAll(args.sublist(i));
      break;
    } else if (arg == '--device') {
      if (i + 1 >= args.length) {
        stderr.writeln('ERROR: Missing argument for "device".');
        return 1;
      }
      device = args[++i];
    } else if (arg.startsWith('--device=')) {
      device = arg.substring('--device='.length);
    } else if (_negativeNumber.hasMatch(arg)) {
      prepared.add('$_negativeSentinel${negatives.length}');
      negatives.add(arg);
    } else {
      if (arg.startsWith('--') && !arg.contains('=')) {
        final option = parser.options[arg.substring(2)];
        expectsValue = option != null && !option.isFlag;
      } else if (arg.length == 2 && arg.startsWith('-')) {
        final option = parser.findByAbbreviation(arg.substring(1));
        expectsValue = option != null && !option.isFlag;
      }
      prepared.add(arg);
    }
  }

  return runCliAdapter(parser, prepared, (results) {
    final positional = [
      for (final arg in results.rest)
        arg.startsWith(_negativeSentinel) ? negatives[int.parse(arg.substring(_negativeSentinel.length))] : arg,
    ];
    return execute(results, positional, device);
  });
}

// ---------------------------------------------------------------------------
// appearance
// ---------------------------------------------------------------------------

Future<int> _runAppearance(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator appearance dark|light|get [--device <udid>]\n\n'
      'Set or query the iOS simulator appearance (dark/light mode).',
      (results, positional, device) async {
        if (positional.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator appearance dark|light|get');
          return 1;
        }
        final mode = positional[0];
        if (!const {'dark', 'light', 'get'}.contains(mode)) {
          stderr.writeln('ERROR: Invalid mode: $mode. Expected dark, light, or get');
          return 1;
        }
        final result = await setSimAppearance((mode: mode, deviceOverride: device));
        switch (result) {
          case SimAppearanceSet(:final mode):
            stdout.writeln('APPEARANCE=$mode');
            return 0;
          case SimAppearanceQueried(:final mode):
            stdout.writeln('APPEARANCE=$mode');
            return 0;
          case SimAppearanceFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
        }
      },
    );

// ---------------------------------------------------------------------------
// push
// ---------------------------------------------------------------------------

Future<int> _runPush(List<String> args) => _runSimulatorAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'Target app bundle ID (auto-detected from session)'),
      args,
      'Usage: fdb simulator push [--bundle-id <id>] [--device <udid>] <payload.apns>\n\n'
      'Send a simulated push notification.',
      (results, positional, device) async {
        if (positional.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator push [--bundle-id <id>] <payload.apns>');
          return 1;
        }
        final payload = positional[0];
        final bundleId = _resolveBundleId(results.option('bundle-id'));
        final result = await sendSimPush((bundleId: bundleId, payload: payload, deviceOverride: device));
        switch (result) {
          case SimPushSent(:final bundleId):
            stdout.writeln('PUSH_SENT BUNDLE_ID=$bundleId');
            return 0;
          case SimPushFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
        }
      },
    );

// ---------------------------------------------------------------------------
// location
// ---------------------------------------------------------------------------

Future<int> _runLocation(List<String> args) {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(
      'Usage: fdb simulator location set <lat,lon> [--device <udid>]\n'
      '       fdb simulator location route <scenario> [--device <udid>]\n'
      '       fdb simulator location clear [--device <udid>]\n\n'
      'Scenarios: "City Run", "City Bicycle Ride", "Freeway Drive"',
    );
    return Future.value(0);
  }

  final action = args[0];
  final actionArgs = args.sublist(1);

  switch (action) {
    case 'set':
      return _locationSet(actionArgs);
    case 'route':
      return _locationRoute(actionArgs);
    case 'clear':
      return _locationClear(actionArgs);
    default:
      stderr.writeln('ERROR: Unknown location action: $action. Expected set, route, or clear');
      return Future.value(1);
  }
}

Future<int> _locationSet(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator location set <lat,lon> [--device <udid>]',
      (results, positional, device) async {
        if (positional.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator location set <lat,lon>');
          return 1;
        }
        final coordParts = positional[0].split(',');
        if (coordParts.length != 2) {
          stderr.writeln(
            'ERROR: Invalid coordinates: ${positional[0]}. Expected format: lat,lon (e.g. 37.7749,-122.4194)',
          );
          return 1;
        }
        final lat = double.tryParse(coordParts[0].trim());
        final lon = double.tryParse(coordParts[1].trim());
        if (lat == null || lon == null) {
          stderr.writeln(
            'ERROR: Invalid coordinates: ${positional[0]}. Expected format: lat,lon (e.g. 37.7749,-122.4194)',
          );
          return 1;
        }
        final result = await setSimLocation((
          latitude: lat.toString(),
          longitude: lon.toString(),
          deviceOverride: device,
        ));
        switch (result) {
          case SimLocationSet(:final latitude, :final longitude):
            stdout.writeln('LOCATION_SET LAT=$latitude LON=$longitude');
            return 0;
          case SimLocationFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimLocationRouteStarted():
          case SimLocationCleared():
            return 0; // unreachable
        }
      },
    );

Future<int> _locationRoute(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator location route <scenario> [--device <udid>]',
      (results, positional, device) async {
        if (positional.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator location route <scenario>');
          return 1;
        }
        final scenario = positional.join(' ');
        final result = await runSimLocationRoute((scenario: scenario, deviceOverride: device));
        switch (result) {
          case SimLocationRouteStarted(:final scenario):
            stdout.writeln('LOCATION_ROUTE=$scenario');
            return 0;
          case SimLocationFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimLocationSet():
          case SimLocationCleared():
            return 0; // unreachable
        }
      },
    );

Future<int> _locationClear(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator location clear [--device <udid>]',
      (results, positional, device) async {
        final result = await clearSimLocation((deviceOverride: device));
        switch (result) {
          case SimLocationCleared():
            stdout.writeln('LOCATION_CLEARED');
            return 0;
          case SimLocationFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimLocationSet():
          case SimLocationRouteStarted():
            return 0; // unreachable
        }
      },
    );

// ---------------------------------------------------------------------------
// text-size
// ---------------------------------------------------------------------------

Future<int> _runTextSize(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator text-size <size>|get [--device <udid>]\n\n'
      'Set or query the Dynamic Type content size.\n'
      'Sizes: ${validContentSizes.join(", ")}',
      (results, positional, device) async {
        if (positional.isEmpty) {
          stderr.writeln(
            'ERROR: Expected: fdb simulator text-size <size>|get\n'
            'Sizes: ${validContentSizes.join(", ")}',
          );
          return 1;
        }
        final size = positional[0];
        if (size != 'get' && !validContentSizes.contains(size)) {
          stderr.writeln(
            'ERROR: Invalid size: $size\n'
            'Valid sizes: ${validContentSizes.join(", ")}',
          );
          return 1;
        }
        final result = await setSimTextSize((size: size, deviceOverride: device));
        switch (result) {
          case SimTextSizeSet(:final size):
            stdout.writeln('TEXT_SIZE=$size');
            return 0;
          case SimTextSizeQueried(:final size):
            stdout.writeln('TEXT_SIZE=$size');
            return 0;
          case SimTextSizeFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
        }
      },
    );

// ---------------------------------------------------------------------------
// status-bar
// ---------------------------------------------------------------------------

Future<int> _runStatusBar(List<String> args) {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(
      'Usage: fdb simulator status-bar override [options] [--device <udid>]\n'
      '       fdb simulator status-bar clear [--device <udid>]\n\n'
      'Override options:\n'
      '  --time <string>          Time string (e.g. "9:41")\n'
      '  --data-network <type>    wifi|3g|4g|lte|lte-a|lte+|5g|5g+|5g-uwb|5g-uc|hide\n'
      '  --wifi-mode <mode>       active|searching|failed\n'
      '  --wifi-bars <0-3>        WiFi signal bars\n'
      '  --cellular-mode <mode>   active|searching|failed|notSupported\n'
      '  --cellular-bars <0-4>    Cellular signal bars\n'
      '  --operator <name>        Operator name\n'
      '  --battery-state <state>  charging|charged|discharging\n'
      '  --battery-level <0-100>  Battery percentage\n'
      '  --device <udid>          $_deviceHelp',
    );
    return Future.value(0);
  }

  final action = args[0];

  switch (action) {
    case 'override':
      return _statusBarOverride(args.sublist(1));
    case 'clear':
      return _statusBarClear(args.sublist(1));
    default:
      stderr.writeln('ERROR: Unknown status-bar action: $action. Expected override or clear');
      return Future.value(1);
  }
}

Future<int> _statusBarOverride(List<String> args) => _runSimulatorAdapter(
      ArgParser()
        ..addOption('time', help: 'Time string (e.g. "9:41")')
        ..addOption('data-network', help: 'Data network type')
        ..addOption('wifi-mode', help: 'WiFi mode')
        ..addOption('wifi-bars', help: 'WiFi bars (0-3)')
        ..addOption('cellular-mode', help: 'Cellular mode')
        ..addOption('cellular-bars', help: 'Cellular bars (0-4)')
        ..addOption('operator', help: 'Operator name')
        ..addOption('battery-state', help: 'Battery state')
        ..addOption('battery-level', help: 'Battery level (0-100)'),
      args,
      'Usage: fdb simulator status-bar override [options] [--device <udid>]',
      (results, positional, device) async {
        final wifiBarsRaw = results.option('wifi-bars');
        final cellularBarsRaw = results.option('cellular-bars');
        final batteryLevelRaw = results.option('battery-level');

        int? wifiBars;
        if (wifiBarsRaw != null) {
          wifiBars = int.tryParse(wifiBarsRaw);
          if (wifiBars == null || wifiBars < 0 || wifiBars > 3) {
            stderr.writeln('ERROR: --wifi-bars must be 0-3');
            return 1;
          }
        }

        int? cellularBars;
        if (cellularBarsRaw != null) {
          cellularBars = int.tryParse(cellularBarsRaw);
          if (cellularBars == null || cellularBars < 0 || cellularBars > 4) {
            stderr.writeln('ERROR: --cellular-bars must be 0-4');
            return 1;
          }
        }

        int? batteryLevel;
        if (batteryLevelRaw != null) {
          batteryLevel = int.tryParse(batteryLevelRaw);
          if (batteryLevel == null || batteryLevel < 0 || batteryLevel > 100) {
            stderr.writeln('ERROR: --battery-level must be 0-100');
            return 1;
          }
        }

        final time = results.option('time');
        final dataNetwork = results.option('data-network');
        final wifiMode = results.option('wifi-mode');
        final cellularMode = results.option('cellular-mode');
        final operatorName = results.option('operator');
        final batteryState = results.option('battery-state');

        if (time == null &&
            dataNetwork == null &&
            wifiMode == null &&
            wifiBars == null &&
            cellularMode == null &&
            cellularBars == null &&
            operatorName == null &&
            batteryState == null &&
            batteryLevel == null) {
          stderr.writeln('ERROR: At least one override option is required. See: fdb simulator status-bar --help');
          return 1;
        }

        final input = (
          time: time,
          dataNetwork: dataNetwork,
          wifiMode: wifiMode,
          wifiBars: wifiBars,
          cellularMode: cellularMode,
          cellularBars: cellularBars,
          operatorName: operatorName,
          batteryState: batteryState,
          batteryLevel: batteryLevel,
          deviceOverride: device,
        );

        final result = await overrideSimStatusBar(input);
        switch (result) {
          case SimStatusBarOverridden():
            stdout.writeln('STATUS_BAR_OVERRIDDEN');
            return 0;
          case SimStatusBarCleared():
            return 0; // unreachable
          case SimStatusBarFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
        }
      },
    );

Future<int> _statusBarClear(List<String> args) => _runSimulatorAdapter(
      ArgParser(),
      args,
      'Usage: fdb simulator status-bar clear [--device <udid>]',
      (results, positional, device) async {
        final result = await clearSimStatusBar((deviceOverride: device));
        switch (result) {
          case SimStatusBarCleared():
            stdout.writeln('STATUS_BAR_CLEARED');
            return 0;
          case SimStatusBarOverridden():
            return 0; // unreachable
          case SimStatusBarFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
        }
      },
    );

// ---------------------------------------------------------------------------
// defaults
// ---------------------------------------------------------------------------

Future<int> _runDefaults(List<String> args) {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(
      'Usage: fdb simulator defaults read [--bundle-id <id>] [--device <udid>] [<key>]\n'
      '       fdb simulator defaults write [--bundle-id <id>] [--device <udid>] [--type <type>] <key> <value>\n'
      '       fdb simulator defaults delete [--bundle-id <id>] [--device <udid>] <key>\n\n'
      'Types for write: string, int, float, bool\n'
      'Bundle ID is auto-detected from the fdb session if not provided.',
    );
    return Future.value(0);
  }

  final action = args[0];
  final actionArgs = args.sublist(1);

  switch (action) {
    case 'read':
      return _defaultsRead(actionArgs);
    case 'write':
      return _defaultsWrite(actionArgs);
    case 'delete':
      return _defaultsDelete(actionArgs);
    default:
      stderr.writeln('ERROR: Unknown defaults action: $action. Expected read, write, or delete');
      return Future.value(1);
  }
}

Future<int> _defaultsRead(List<String> args) => _runSimulatorAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)'),
      args,
      'Usage: fdb simulator defaults read [--bundle-id <id>] [--device <udid>] [<key>]',
      (results, positional, device) async {
        final bundleId = _resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        final key = positional.isNotEmpty ? positional[0] : null;
        final result = await readSimDefaults((bundleId: bundleId, key: key, deviceOverride: device));
        switch (result) {
          case SimDefaultsReadSuccess(:final output):
            stdout.writeln(output);
            return 0;
          case SimDefaultsFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimDefaultsWritten():
          case SimDefaultsDeleted():
            return 0; // unreachable
        }
      },
    );

Future<int> _defaultsWrite(List<String> args) => _runSimulatorAdapter(
      ArgParser()
        ..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)')
        ..addOption('type', abbr: 't', defaultsTo: 'string', help: 'Value type: string, int, float, bool'),
      args,
      'Usage: fdb simulator defaults write [--bundle-id <id>] [--device <udid>] [--type <type>] <key> <value>',
      (results, positional, device) async {
        final bundleId = _resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        if (positional.length < 2) {
          stderr.writeln('ERROR: Expected: fdb simulator defaults write [--bundle-id <id>] <key> <value>');
          return 1;
        }
        final key = positional[0];
        final value = positional[1];
        final type = results.option('type')!;
        if (!const {'string', 'int', 'float', 'bool'}.contains(type)) {
          stderr.writeln('ERROR: Invalid type: $type. Expected: string, int, float, bool');
          return 1;
        }
        final result = await writeSimDefaults((
          bundleId: bundleId,
          key: key,
          value: value,
          type: type,
          deviceOverride: device,
        ));
        switch (result) {
          case SimDefaultsWritten(:final key, :final value):
            stdout.writeln('DEFAULTS_WRITTEN KEY=$key VALUE=$value');
            return 0;
          case SimDefaultsFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimDefaultsReadSuccess():
          case SimDefaultsDeleted():
            return 0; // unreachable
        }
      },
    );

Future<int> _defaultsDelete(List<String> args) => _runSimulatorAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)'),
      args,
      'Usage: fdb simulator defaults delete [--bundle-id <id>] [--device <udid>] <key>',
      (results, positional, device) async {
        final bundleId = _resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        if (positional.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator defaults delete [--bundle-id <id>] <key>');
          return 1;
        }
        final key = positional[0];
        final result = await deleteSimDefaults((bundleId: bundleId, key: key, deviceOverride: device));
        switch (result) {
          case SimDefaultsDeleted(:final key):
            stdout.writeln('DEFAULTS_DELETED KEY=$key');
            return 0;
          case SimDefaultsFailed(:final message):
            stderr.writeln('ERROR: $message');
            return 1;
          case SimDefaultsReadSuccess():
          case SimDefaultsWritten():
            return 0; // unreachable
        }
      },
    );
