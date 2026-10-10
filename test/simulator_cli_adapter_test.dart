import 'dart:convert';
import 'dart:io';

import 'package:fdb/cli/adapters/simulator_cli.dart';
import 'package:fdb/constants.dart';
import 'package:fdb/core/xcrun.dart';
import 'package:test/test.dart';

/// Two booted simulators (A, B); the fdb session points at B.
const _udidA = 'AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA';
const _udidB = 'BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB';
const _bogusUdid = 'DDDDDDDD-4444-4444-8444-DDDDDDDDDDDD';

/// Tests for `runSimulatorCli`: `--device` extraction, negative-number
/// positionals and the unchanged output tokens. Runs in-process against a fake
/// `xcrun`; no real simulator is touched.
void main() {
  group('simulator CLI: every subcommand targets the session simulator by default', () {
    for (final c in _cases) {
      test('${c.name} without --device targets session simulator B', () async {
        final env = await _CliEnv.create();

        final run = await env.run(c.args(env));

        expect(run.exitCode, 0, reason: run.describe());
        expect(run.stdout, c.stdout, reason: run.describe());
        expect(env.mutatingCalls(), [c.call(env, _udidB)]);
      });
    }
  });

  group('simulator CLI: --device overrides the session simulator', () {
    for (final c in _cases) {
      for (final placement in _DevicePlacement.values) {
        test('${c.name} with ${placement.label} targets A and never B', () async {
          final env = await _CliEnv.create();

          final run = await env.run(placement.apply(c, env, _udidA));

          expect(run.exitCode, 0, reason: run.describe());
          expect(run.stdout, c.stdout, reason: run.describe());
          expect(env.mutatingCalls(), [c.call(env, _udidA)]);
          expect(env.mutatingCalls().join('\n'), isNot(contains(_udidB)));
        });
      }
    }

    for (final c in _cases) {
      test('${c.name} with an unknown --device fails without a mutating simctl call', () async {
        final env = await _CliEnv.create();

        final run = await env.run(_DevicePlacement.afterArgs.apply(c, env, _bogusUdid));

        expect(run.exitCode, 1, reason: run.describe());
        expect(run.stderr, startsWith('ERROR: No iOS simulator with UDID $_bogusUdid'));
        expect(run.stdout, isEmpty);
        expect(env.mutatingCalls(), isEmpty);
      });
    }

    test('an empty --device value is rejected without a mutating simctl call', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['appearance', 'dark', '--device', '']);

      expect(run.exitCode, 1, reason: run.describe());
      expect(run.stderr, startsWith('ERROR: No iOS simulator with UDID'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('a shut down --device is rejected without a mutating simctl call', () async {
      final env = await _CliEnv.create(shutdown: [_udidA]);

      final run = await env.run(['appearance', 'dark', '--device', _udidA]);

      expect(run.exitCode, 1, reason: run.describe());
      expect(run.stderr, startsWith('ERROR: Simulator $_udidA'));
      expect(run.stderr, contains('not booted'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('--device is matched case-insensitively', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['appearance', 'dark', '--device', _udidA.toLowerCase()]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    for (final args in [
      ['appearance', 'dark', '--device'],
      ['appearance', '--device'],
      ['text-size', 'large', '--device'],
      ['status-bar', 'override', '--time', '9:41', '--device'],
      ['status-bar', 'clear', '--device'],
      ['location', 'set', '37.7,-122.4', '--device'],
      ['location', 'route', 'City Run', '--device'],
      ['location', 'clear', '--device'],
      ['push', '--bundle-id', 'x', '{payload}', '--device'],
      ['defaults', 'read', '--bundle-id', 'x', '--device'],
      ['defaults', 'write', '--bundle-id', 'x', 'k', 'v', '--device'],
      ['defaults', 'delete', '--bundle-id', 'x', 'k', '--device'],
    ]) {
      test('${args.join(' ')} (missing --device value) fails with an ERROR naming "device"', () async {
        final env = await _CliEnv.create();

        final run = await env.run(env.fill(args));

        expect(run.exitCode, 1, reason: run.describe());
        expect(run.stderr, startsWith('ERROR:'));
        expect(run.stderr, contains('device'));
        expect(run.stdout, isEmpty);
        expect(env.calls(), isEmpty);
      });
    }

    test('the last --device wins when it is repeated', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['appearance', 'dark', '--device', _udidB, '--device', _udidA]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });
  });

  group('simulator CLI: negative-number positionals', () {
    test('location set with a negative latitude reaches simctl verbatim', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'set', '-33.86,151.21']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'LOCATION_SET LAT=-33.86 LON=151.21\n');
      expect(env.mutatingCalls(), ['location $_udidB set -33.86,151.21']);
    });

    test('location set with two negative parts and --device after reaches simctl verbatim', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'set', '-33.86,-151.21', '--device', _udidA]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'LOCATION_SET LAT=-33.86 LON=-151.21\n');
      expect(env.mutatingCalls(), ['location $_udidA set -33.86,-151.21']);
    });

    test('location set with --device before the negative coordinates', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'set', '--device', _udidA, '-33.86,151.21']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['location $_udidA set -33.86,151.21']);
    });

    test('location set with --device=<udid> before the negative coordinates', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'set', '--device=$_udidA', '-33.86,-151.21']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['location $_udidA set -33.86,-151.21']);
    });

    test('defaults write passes a negative int value as "-int -1"', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['defaults', 'write', '--bundle-id', 'x', 'k', '-1', '--type', 'int']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'DEFAULTS_WRITTEN KEY=k VALUE=-1\n');
      expect(env.mutatingCalls(), ['spawn $_udidB defaults write x k -int -1']);
    });

    test('defaults write with the short -t/-b options and a negative value', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['defaults', 'write', '-b', 'x', '-t', 'int', 'k', '-1']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['spawn $_udidB defaults write x k -int -1']);
    });

    test('defaults write passes a negative float and --device before it', () async {
      final env = await _CliEnv.create();

      final run = await env.run([
        'defaults',
        'write',
        '--bundle-id',
        'x',
        '--device',
        _udidA,
        '--type',
        'float',
        'k',
        '-0.5',
      ]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'DEFAULTS_WRITTEN KEY=k VALUE=-0.5\n');
      expect(env.mutatingCalls(), ['spawn $_udidA defaults write x k -float -0.5']);
    });

    test('defaults write accepts a negative value after "--"', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['defaults', 'write', '--bundle-id', 'x', '--type', 'int', '--', 'k', '-1']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(env.mutatingCalls(), ['spawn $_udidB defaults write x k -int -1']);
    });

    test('a negative option value is not mistaken for a positional (status-bar --battery-level -5)', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['status-bar', 'override', '--battery-level', '-5']);

      expect(run.exitCode, 1, reason: run.describe());
      expect(run.stderr, 'ERROR: --battery-level must be 0-100\n');
      expect(env.calls(), isEmpty);
    });

    test('a non-numeric dash value is still rejected as an unknown option', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['defaults', 'write', '--bundle-id', 'x', 'k', '-abc']);

      expect(run.exitCode, 1, reason: run.describe());
      expect(run.stderr, startsWith('ERROR:'));
      expect(env.calls(), isEmpty);
    });
  });

  group('simulator CLI: location route scenario', () {
    test('multiple words are joined into one scenario', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'route', 'City', 'Run']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'LOCATION_ROUTE=City Run\n');
      expect(env.mutatingCalls(), ['location $_udidB run City Run']);
    });

    test('a single quoted argument gives the same scenario', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'route', 'City Run']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'LOCATION_ROUTE=City Run\n');
      expect(env.mutatingCalls(), ['location $_udidB run City Run']);
    });

    test('--device between the scenario words does not leak into the scenario', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'route', 'City', '--device', _udidA, 'Bicycle', 'Ride']);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'LOCATION_ROUTE=City Bicycle Ride\n');
      expect(env.mutatingCalls(), ['location $_udidA run City Bicycle Ride']);
    });
  });

  group('simulator CLI: bundle id from the fdb session', () {
    test('push without --bundle-id uses the session app id and the session simulator', () async {
      final env = await _CliEnv.create(appId: 'com.session.app');

      final run = await env.run(env.fill(['push', '{payload}']));

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'PUSH_SENT BUNDLE_ID=com.session.app\n');
      expect(env.mutatingCalls(), ['push $_udidB com.session.app ${env.payload.path}']);
    });

    test('defaults read without --bundle-id uses the session app id', () async {
      final env = await _CliEnv.create(appId: 'com.session.app');

      final run = await env.run(['defaults', 'read', 'theme', '--device', _udidA]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, 'theme = dark;\n');
      expect(env.mutatingCalls(), ['spawn $_udidA defaults read com.session.app theme']);
    });

    test('defaults read without a bundle id and without a session app id fails before simctl', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['defaults', 'read', 'theme']);

      expect(run.exitCode, 1, reason: run.describe());
      expect(
        run.stderr,
        'ERROR: No bundle ID. Pass --bundle-id or run from a project with an active fdb session.\n',
      );
      expect(env.calls(), isEmpty);
    });
  });

  group('simulator CLI: --help', () {
    for (final args in [
      ['--help'],
      ['appearance', '--help'],
      ['text-size', '--help'],
      ['push', '--help'],
      ['push', '-h'],
      ['location', '--help'],
      ['location', 'set', '--help'],
      ['location', 'route', '--help'],
      ['location', 'clear', '--help'],
      ['status-bar', '--help'],
      ['status-bar', 'override', '--help'],
      ['status-bar', 'clear', '--help'],
      ['defaults', '--help'],
      ['defaults', 'read', '--help'],
      ['defaults', 'write', '--help'],
      ['defaults', 'delete', '--help'],
    ]) {
      test('${args.join(' ')} exits 0 and documents --device', () async {
        final env = await _CliEnv.create();

        final run = await env.run(args);

        expect(run.exitCode, 0, reason: run.describe());
        expect(run.stdout, contains('--device'));
        expect(run.stderr, isEmpty);
        expect(env.calls(), isEmpty);
      });
    }

    test('no arguments prints the usage and exits 0', () async {
      final env = await _CliEnv.create();

      final run = await env.run([]);

      expect(run.exitCode, 0, reason: run.describe());
      expect(run.stdout, contains('Usage: fdb simulator <subcommand>'));
      expect(run.stdout, contains('--device'));
    });
  });

  group('simulator CLI: validation errors are unchanged and happen before any simctl call', () {
    for (final c in _validationCases) {
      test('${c.args.join(' ')} => ${c.stderrStart}', () async {
        final env = await _CliEnv.create();

        final run = await env.run(env.fill(c.args));

        expect(run.exitCode, 1, reason: run.describe());
        expect(run.stderr, startsWith(c.stderrStart));
        expect(run.stdout, isEmpty);
        expect(env.calls(), isEmpty, reason: 'validation must not reach simctl');
      });

      test('${c.args.join(' ')} --device A => same error', () async {
        final env = await _CliEnv.create();

        final run = await env.run([...env.fill(c.args), '--device', _udidA]);

        expect(run.exitCode, 1, reason: run.describe());
        expect(run.stderr, startsWith(c.stderrStart));
        expect(env.calls(), isEmpty, reason: 'validation must not reach simctl');
      });
    }

    test('appearance bogus prints the exact error', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['appearance', 'bogus']);

      expect(run.exitCode, 1);
      expect(run.stderr, 'ERROR: Invalid mode: bogus. Expected dark, light, or get\n');
    });

    test('location set abc prints the exact error', () async {
      final env = await _CliEnv.create();

      final run = await env.run(['location', 'set', 'abc']);

      expect(run.exitCode, 1);
      expect(
        run.stderr,
        'ERROR: Invalid coordinates: abc. Expected format: lat,lon (e.g. 37.7749,-122.4194)\n',
      );
    });
  });

  group('simulator CLI: simctl failures', () {
    test('a failing simctl call is reported as ERROR with exit code 1', () async {
      final env = await _CliEnv.create(failMutating: 'boom from simctl');

      final run = await env.run(['appearance', 'dark']);

      expect(run.exitCode, 1, reason: run.describe());
      expect(run.stderr, 'ERROR: boom from simctl\n');
      expect(run.stdout, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Case tables
// ---------------------------------------------------------------------------

/// One happy-path invocation. [args] and [call] may contain `{payload}`.
class _Case {
  const _Case(this.name, this._args, this._call, this._stdout);

  final String name;
  final List<String> _args;
  final String Function(String udid) _call;
  final String _stdout;

  List<String> args(_CliEnv env) => env.fill(_args);
  String call(_CliEnv env, String udid) => env.fillOne(_call(udid));
  String get stdout => '$_stdout\n';
}

/// Where `--device` goes relative to the case's own arguments.
enum _DevicePlacement {
  /// `... --device <udid>` after every other argument.
  afterArgs('--device <udid> at the end'),

  /// `... --device=<udid>` after every other argument.
  afterArgsEquals('--device=<udid> at the end'),

  /// Right after the action, before the remaining options and positionals.
  beforePositionals('--device <udid> before positionals');

  const _DevicePlacement(this.label);

  final String label;

  List<String> apply(_Case c, _CliEnv env, String udid) {
    final args = c.args(env);
    // `location`, `status-bar` and `defaults` have a separate action word.
    final actionLength = const {'location', 'status-bar', 'defaults'}.contains(args.first) ? 2 : 1;
    return switch (this) {
      _DevicePlacement.afterArgs => [...args, '--device', udid],
      _DevicePlacement.afterArgsEquals => [...args, '--device=$udid'],
      _DevicePlacement.beforePositionals => [
          ...args.take(actionLength),
          '--device',
          udid,
          ...args.skip(actionLength),
        ],
    };
  }
}

final _cases = <_Case>[
  _Case('appearance dark', ['appearance', 'dark'], (u) => 'ui $u appearance dark', 'APPEARANCE=dark'),
  _Case('appearance light', ['appearance', 'light'], (u) => 'ui $u appearance light', 'APPEARANCE=light'),
  _Case('appearance get', ['appearance', 'get'], (u) => 'ui $u appearance', 'APPEARANCE=dark'),
  _Case('text-size large', ['text-size', 'large'], (u) => 'ui $u content_size large', 'TEXT_SIZE=large'),
  _Case('text-size get', ['text-size', 'get'], (u) => 'ui $u content_size', 'TEXT_SIZE=large'),
  _Case(
    'status-bar override --time',
    ['status-bar', 'override', '--time', '9:41'],
    (u) => 'status_bar $u override --time 9:41',
    'STATUS_BAR_OVERRIDDEN',
  ),
  _Case(
    'status-bar override with several options',
    ['status-bar', 'override', '--time', '9:41', '--wifi-bars', '3', '--battery-level', '100'],
    (u) => 'status_bar $u override --time 9:41 --wifiBars 3 --batteryLevel 100',
    'STATUS_BAR_OVERRIDDEN',
  ),
  _Case('status-bar clear', ['status-bar', 'clear'], (u) => 'status_bar $u clear', 'STATUS_BAR_CLEARED'),
  _Case(
    'location set',
    ['location', 'set', '37.7749,-122.4194'],
    (u) => 'location $u set 37.7749,-122.4194',
    'LOCATION_SET LAT=37.7749 LON=-122.4194',
  ),
  _Case(
    'location route (two words)',
    ['location', 'route', 'City', 'Run'],
    (u) => 'location $u run City Run',
    'LOCATION_ROUTE=City Run',
  ),
  _Case(
    'location route (one quoted argument)',
    ['location', 'route', 'City Run'],
    (u) => 'location $u run City Run',
    'LOCATION_ROUTE=City Run',
  ),
  _Case('location clear', ['location', 'clear'], (u) => 'location $u clear', 'LOCATION_CLEARED'),
  _Case(
    'push --bundle-id',
    ['push', '--bundle-id', 'x', '{payload}'],
    (u) => 'push $u x {payload}',
    'PUSH_SENT BUNDLE_ID=x',
  ),
  _Case(
    'defaults read',
    ['defaults', 'read', '--bundle-id', 'x', 'theme'],
    (u) => 'spawn $u defaults read x theme',
    'theme = dark;',
  ),
  _Case(
    'defaults write',
    ['defaults', 'write', '--bundle-id', 'x', 'k', 'v'],
    (u) => 'spawn $u defaults write x k -string v',
    'DEFAULTS_WRITTEN KEY=k VALUE=v',
  ),
  _Case(
    'defaults write --type int',
    ['defaults', 'write', '--bundle-id', 'x', '--type', 'int', 'k', '7'],
    (u) => 'spawn $u defaults write x k -int 7',
    'DEFAULTS_WRITTEN KEY=k VALUE=7',
  ),
  _Case(
    'defaults delete',
    ['defaults', 'delete', '--bundle-id', 'x', 'k'],
    (u) => 'spawn $u defaults delete x k',
    'DEFAULTS_DELETED KEY=k',
  ),
];

class _Validation {
  const _Validation(this.args, this.stderrStart);

  final List<String> args;
  final String stderrStart;
}

const _validationCases = <_Validation>[
  _Validation(['appearance'], 'ERROR: Expected: fdb simulator appearance dark|light|get'),
  _Validation(['appearance', 'bogus'], 'ERROR: Invalid mode: bogus. Expected dark, light, or get'),
  _Validation(['text-size'], 'ERROR: Expected: fdb simulator text-size <size>|get'),
  _Validation(['text-size', 'huge'], 'ERROR: Invalid size: huge\nValid sizes: '),
  _Validation(['push'], 'ERROR: Expected: fdb simulator push [--bundle-id <id>] <payload.apns>'),
  _Validation(['location', 'set'], 'ERROR: Expected: fdb simulator location set <lat,lon>'),
  _Validation(
    ['location', 'set', 'abc'],
    'ERROR: Invalid coordinates: abc. Expected format: lat,lon (e.g. 37.7749,-122.4194)',
  ),
  _Validation(
    ['location', 'set', '1,2,3'],
    'ERROR: Invalid coordinates: 1,2,3. Expected format: lat,lon (e.g. 37.7749,-122.4194)',
  ),
  _Validation(
    ['location', 'set', 'a,b'],
    'ERROR: Invalid coordinates: a,b. Expected format: lat,lon (e.g. 37.7749,-122.4194)',
  ),
  _Validation(['location', 'route'], 'ERROR: Expected: fdb simulator location route <scenario>'),
  _Validation(
    ['location', 'bogus'],
    'ERROR: Unknown location action: bogus. Expected set, route, or clear',
  ),
  _Validation(
    ['status-bar', 'bogus'],
    'ERROR: Unknown status-bar action: bogus. Expected override or clear',
  ),
  _Validation(
    ['status-bar', 'override'],
    'ERROR: At least one override option is required. See: fdb simulator status-bar --help',
  ),
  _Validation(['status-bar', 'override', '--wifi-bars', '9'], 'ERROR: --wifi-bars must be 0-3'),
  _Validation(['status-bar', 'override', '--cellular-bars', 'x'], 'ERROR: --cellular-bars must be 0-4'),
  _Validation(['status-bar', 'override', '--battery-level', '101'], 'ERROR: --battery-level must be 0-100'),
  _Validation(['status-bar', 'override', '--battery-level', '-5'], 'ERROR: --battery-level must be 0-100'),
  _Validation(
    ['defaults', 'bogus'],
    'ERROR: Unknown defaults action: bogus. Expected read, write, or delete',
  ),
  _Validation(
    ['defaults', 'write', '--bundle-id', 'x', 'k'],
    'ERROR: Expected: fdb simulator defaults write [--bundle-id <id>] <key> <value>',
  ),
  _Validation(
    ['defaults', 'write', '--bundle-id', 'x', '--type', 'bogus', 'k', 'v'],
    'ERROR: Invalid type: bogus. Expected: string, int, float, bool',
  ),
  _Validation(
    ['defaults', 'delete', '--bundle-id', 'x'],
    'ERROR: Expected: fdb simulator defaults delete [--bundle-id <id>] <key>',
  ),
  _Validation(['appearance', '--bogus'], 'ERROR: Could not find an option named "--bogus".'),
  _Validation(['bogus'], 'ERROR: Unknown simulator subcommand: bogus'),
];

// ---------------------------------------------------------------------------
// Fake `xcrun` environment and in-process CLI runner
// ---------------------------------------------------------------------------

/// Result of one in-process `runSimulatorCli` call.
class _CliRun {
  _CliRun(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  String describe() => 'exit: $exitCode\nstdout: $stdout\nstderr: $stderr';
}

/// Temp session dir (device.txt = B) plus a fake `xcrun` that serves
/// `simctl list devices -j` and records every other invocation.
///
/// Installing the fake replaces [xcrunExecutable] and the active session
/// directory; both are restored when the current test finishes.
class _CliEnv {
  _CliEnv._(this.root, this.payload, this._callLog);

  final Directory root;
  final File payload;
  final File _callLog;

  static Future<_CliEnv> create({
    List<String> shutdown = const [],
    String? appId,
    String? failMutating,
  }) async {
    final root = await Directory.systemTemp.createTemp('fdb_sim_cli_test_');
    final sessionDir = Directory('${root.path}/.fdb')..createSync(recursive: true);

    final previousXcrun = xcrunExecutable;
    final previousSessionDir = sessionDirPath;
    addTearDown(() async {
      xcrunExecutable = previousXcrun;
      initSessionDirFromPath(previousSessionDir);
      if (root.existsSync()) await root.delete(recursive: true);
    });

    Map<String, Object> device(String udid, String name) => {
          'udid': udid,
          'name': name,
          'state': shutdown.contains(udid) ? 'Shutdown' : 'Booted',
          'isAvailable': true,
        };
    final listFile = File('${root.path}/devices.json')
      ..writeAsStringSync(
        jsonEncode({
          'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-17-5': [device(_udidA, 'Simulator A')],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-0': [device(_udidB, 'Simulator B')],
          },
        }),
      );
    final callLog = File('${root.path}/calls.log')..createSync();
    final payload = File('${root.path}/payload.apns')..writeAsStringSync('{"aps":{"alert":"hi"}}');

    // `shift` drops the leading `simctl`, so each log line is the simctl
    // subcommand and its arguments, e.g. `status_bar <udid> clear`.
    final failure = failMutating == null ? '' : 'echo "$failMutating" >&2\n  exit 1';
    final script = File('${root.path}/xcrun')..writeAsStringSync('''#!/bin/sh
shift
echo "\$*" >> "${callLog.path}"
if [ "\$1" = "list" ]; then
  cat "${listFile.path}"
  exit 0
fi
$failure
case "\$*" in
  "ui "*" appearance") echo dark ;;
  "ui "*" content_size") echo large ;;
  "spawn "*" defaults read "*) echo "theme = dark;" ;;
esac
exit 0
''');
    await Process.run('chmod', ['+x', script.path]);

    xcrunExecutable = script.path;
    initSessionDirFromPath(sessionDir.path);
    File(deviceFile).writeAsStringSync(_udidB);
    if (appId != null) File(appIdFile).writeAsStringSync(appId);
    return _CliEnv._(root, payload, callLog);
  }

  /// Replaces the `{payload}` placeholder with this environment's payload file.
  String fillOne(String value) => value.replaceAll('{payload}', payload.path);

  List<String> fill(List<String> args) => [for (final arg in args) fillOne(arg)];

  /// Runs `runSimulatorCli` in-process, capturing everything written to the
  /// zone's stdout and stderr.
  Future<_CliRun> run(List<String> args) async {
    final out = _CapturedStdout();
    final err = _CapturedStdout();
    final exitCode = await IOOverrides.runZoned(
      () => runSimulatorCli(args),
      stdout: () => out,
      stderr: () => err,
    );
    return _CliRun(exitCode, out.text, err.text);
  }

  /// Every recorded simctl invocation, one `subcommand args...` string per call.
  List<String> calls() => _callLog.readAsLinesSync().where((line) => line.isNotEmpty).toList();

  /// Recorded invocations other than the device listing.
  List<String> mutatingCalls() => calls().where((line) => !line.startsWith('list ')).toList();
}

/// Minimal in-memory [Stdout] that records what is written to it.
class _CapturedStdout implements Stdout {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) => _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Future<void> flush() async {}

  @override
  bool get hasTerminal => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
