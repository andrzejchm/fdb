import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/simulator/sim_appearance.dart';
import 'package:fdb/core/commands/simulator/sim_defaults.dart';
import 'package:fdb/core/commands/simulator/sim_location.dart';
import 'package:fdb/core/commands/simulator/sim_push.dart';
import 'package:fdb/core/commands/simulator/sim_status_bar.dart';
import 'package:fdb/core/commands/simulator/sim_text_size.dart';

const _usage = '''
Usage: fdb simulator <subcommand> [args]

Subcommands:
  appearance  dark|light|get        Toggle or query dark/light mode
  push        <payload.apns>        Send a simulated push notification
  location    set|route|clear       Simulate GPS location
  text-size   <size>|get            Set or query Dynamic Type content size
  status-bar  override|clear        Override or clear status bar
  defaults    read|write|delete     Read/write/delete NSUserDefaults
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
// appearance
// ---------------------------------------------------------------------------

Future<int> _runAppearance(List<String> args) => runSimpleCliAdapter(
      args,
      (args) async {
        if (args.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator appearance dark|light|get');
          return 1;
        }
        final mode = args[0];
        if (!const {'dark', 'light', 'get'}.contains(mode)) {
          stderr.writeln('ERROR: Invalid mode: $mode. Expected dark, light, or get');
          return 1;
        }
        final result = await setSimAppearance((mode: mode));
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
      helpText: 'Usage: fdb simulator appearance dark|light|get\n\n'
          'Set or query the iOS simulator appearance (dark/light mode).',
    );

// ---------------------------------------------------------------------------
// push
// ---------------------------------------------------------------------------

Future<int> _runPush(List<String> args) => runCliAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'Target app bundle ID (auto-detected from session)'),
      args,
      (results) async {
        final rest = results.rest;
        if (rest.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator push [--bundle-id <id>] <payload.apns>');
          return 1;
        }
        final payload = rest[0];
        final bundleId = results.option('bundle-id');
        final result = await sendSimPush((bundleId: bundleId, payload: payload));
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
      'Usage: fdb simulator location set <lat,lon>\n'
      '       fdb simulator location route <scenario>\n'
      '       fdb simulator location clear\n\n'
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
      return _locationClear();
    default:
      stderr.writeln('ERROR: Unknown location action: $action. Expected set, route, or clear');
      return Future.value(1);
  }
}

Future<int> _locationSet(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Expected: fdb simulator location set <lat,lon>');
    return 1;
  }
  final coords = parseXY(args[0]);
  if (coords == null) {
    stderr.writeln('ERROR: Invalid coordinates: ${args[0]}. Expected format: lat,lon (e.g. 37.7749,-122.4194)');
    return 1;
  }
  final (lat, lon) = coords;
  final result = await setSimLocation((latitude: lat.toString(), longitude: lon.toString()));
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
}

Future<int> _locationRoute(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Expected: fdb simulator location route <scenario>');
    return 1;
  }
  final scenario = args.join(' ');
  final result = await runSimLocationRoute((scenario: scenario));
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
}

Future<int> _locationClear() async {
  final result = await clearSimLocation(());
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
}

// ---------------------------------------------------------------------------
// text-size
// ---------------------------------------------------------------------------

Future<int> _runTextSize(List<String> args) => runSimpleCliAdapter(
      args,
      (args) async {
        if (args.isEmpty) {
          stderr.writeln(
            'ERROR: Expected: fdb simulator text-size <size>|get\n'
            'Sizes: ${validContentSizes.join(", ")}',
          );
          return 1;
        }
        final size = args[0];
        if (size != 'get' && !validContentSizes.contains(size)) {
          stderr.writeln(
            'ERROR: Invalid size: $size\n'
            'Valid sizes: ${validContentSizes.join(", ")}',
          );
          return 1;
        }
        final result = await setSimTextSize((size: size));
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
      helpText: 'Usage: fdb simulator text-size <size>|get\n\n'
          'Set or query the Dynamic Type content size.\n'
          'Sizes: ${validContentSizes.join(", ")}',
    );

// ---------------------------------------------------------------------------
// status-bar
// ---------------------------------------------------------------------------

Future<int> _runStatusBar(List<String> args) {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(
      'Usage: fdb simulator status-bar override [options]\n'
      '       fdb simulator status-bar clear\n\n'
      'Override options:\n'
      '  --time <string>          Time string (e.g. "9:41")\n'
      '  --data-network <type>    wifi|3g|4g|lte|lte-a|lte+|5g|5g+|5g-uwb|5g-uc|hide\n'
      '  --wifi-mode <mode>       active|searching|failed\n'
      '  --wifi-bars <0-3>        WiFi signal bars\n'
      '  --cellular-mode <mode>   active|searching|failed|notSupported\n'
      '  --cellular-bars <0-4>    Cellular signal bars\n'
      '  --operator <name>        Operator name\n'
      '  --battery-state <state>  charging|charged|discharging\n'
      '  --battery-level <0-100>  Battery percentage',
    );
    return Future.value(0);
  }

  final action = args[0];

  switch (action) {
    case 'override':
      return _statusBarOverride(args.sublist(1));
    case 'clear':
      return _statusBarClear();
    default:
      stderr.writeln('ERROR: Unknown status-bar action: $action. Expected override or clear');
      return Future.value(1);
  }
}

Future<int> _statusBarOverride(List<String> args) => runCliAdapter(
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
      (results) async {
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

        final input = (
          time: results.option('time'),
          dataNetwork: results.option('data-network'),
          wifiMode: results.option('wifi-mode'),
          wifiBars: wifiBars,
          cellularMode: results.option('cellular-mode'),
          cellularBars: cellularBars,
          operatorName: results.option('operator'),
          batteryState: results.option('battery-state'),
          batteryLevel: batteryLevel,
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

Future<int> _statusBarClear() async {
  final result = await clearSimStatusBar();
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
}

// ---------------------------------------------------------------------------
// defaults
// ---------------------------------------------------------------------------

Future<int> _runDefaults(List<String> args) {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stdout.writeln(
      'Usage: fdb simulator defaults read [--bundle-id <id>] [<key>]\n'
      '       fdb simulator defaults write [--bundle-id <id>] <key> -<type> <value>\n'
      '       fdb simulator defaults delete [--bundle-id <id>] <key>\n\n'
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

Future<int> _defaultsRead(List<String> args) => runCliAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)'),
      args,
      (results) async {
        final bundleId = resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        final key = results.rest.isNotEmpty ? results.rest[0] : null;
        final result = await readSimDefaults((bundleId: bundleId, key: key));
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

Future<int> _defaultsWrite(List<String> args) => runCliAdapter(
      ArgParser()
        ..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)')
        ..addOption('type', abbr: 't', defaultsTo: 'string', help: 'Value type: string, int, float, bool'),
      args,
      (results) async {
        final bundleId = resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        if (results.rest.length < 2) {
          stderr.writeln('ERROR: Expected: fdb simulator defaults write [--bundle-id <id>] <key> <value>');
          return 1;
        }
        final key = results.rest[0];
        final value = results.rest[1];
        final type = results['type'] as String;
        if (!const {'string', 'int', 'float', 'bool'}.contains(type)) {
          stderr.writeln('ERROR: Invalid type: $type. Expected: string, int, float, bool');
          return 1;
        }
        final result = await writeSimDefaults((bundleId: bundleId, key: key, value: value, type: type));
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

Future<int> _defaultsDelete(List<String> args) => runCliAdapter(
      ArgParser()..addOption('bundle-id', abbr: 'b', help: 'App bundle ID (auto-detected from session)'),
      args,
      (results) async {
        final bundleId = resolveBundleId(results.option('bundle-id'));
        if (bundleId == null) {
          stderr.writeln(
            'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.',
          );
          return 1;
        }
        if (results.rest.isEmpty) {
          stderr.writeln('ERROR: Expected: fdb simulator defaults delete [--bundle-id <id>] <key>');
          return 1;
        }
        final key = results.rest[0];
        final result = await deleteSimDefaults((bundleId: bundleId, key: key));
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
