import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/simulator/simulator.g.dart';
import 'package:fdb/core/xcrun.dart';
import 'package:test/test.dart';

/// Two booted simulators (A, B) on different runtimes and one shut down (C).
const _udidA = 'AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA';
const _udidB = 'BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB';
const _udidC = 'CCCCCCCC-3333-4333-8333-CCCCCCCCCCCC';
const _udidWatch = 'EEEEEEEE-5555-4555-8555-EEEEEEEEEEEE';
const _udidIpad = 'FFFFFFFF-6666-4666-8666-FFFFFFFFFFFF';

/// An additional simulator on an arbitrary runtime, merged into the fixture.
typedef _ExtraSim = ({String runtime, String udid, String name, bool booted});

_ExtraSim _watch() => (
      runtime: 'com.apple.CoreSimulator.SimRuntime.watchOS-11-0',
      udid: _udidWatch,
      name: 'Apple Watch Series 10',
      booted: true,
    );

void main() {
  group('simulator device resolution: every verb targets the session simulator', () {
    for (final verb in _verbs) {
      test('${verb.name} targets the session simulator B, not A and not "booted"', () async {
        final env = await _FakeEnv.create(session: _udidB);

        final result = await verb.run(null);

        expect(verb.succeeded(result), isTrue, reason: 'unexpected result: ${_describeResult(result)}');
        expect(env.mutatingCalls(), [verb.expectedCall(_udidB)]);
        expect(env.mutatingCalls().join('\n'), isNot(contains(_udidA)));
        expect(env.mutatingCalls().join('\n'), isNot(contains('booted')));
      });
    }

    test('push sends the payload to the session simulator B', () async {
      final env = await _FakeEnv.create(session: _udidB);
      final payload = File('${env.root.path}/payload.json')..writeAsStringSync('{"aps":{"alert":"hi"}}');

      final result = await sendSimPush((bundleId: 'com.example.app', payload: payload.path, deviceOverride: null));

      expect(result, isA<SimPushSent>());
      expect(env.mutatingCalls(), ['push $_udidB com.example.app ${payload.path}']);
    });

    test('push without a bundle id targets the session simulator B', () async {
      final env = await _FakeEnv.create(session: _udidB);
      final payload = File('${env.root.path}/payload.json')..writeAsStringSync('{}');

      final result = await sendSimPush((bundleId: null, payload: payload.path, deviceOverride: null));

      expect(result, isA<SimPushSent>());
      expect(env.mutatingCalls(), ['push $_udidB ${payload.path}']);
    });

    test('appearance get returns the value reported by the session simulator', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimAppearance((mode: 'get', deviceOverride: null));

      expect(result, isA<SimAppearanceQueried>());
      expect((result as SimAppearanceQueried).mode, 'dark');
      expect(env.mutatingCalls(), ['ui $_udidB appearance']);
    });

    test('text-size get returns the value reported by the session simulator', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimTextSize((size: 'get', deviceOverride: null));

      expect(result, isA<SimTextSizeQueried>());
      expect((result as SimTextSizeQueried).size, 'large');
      expect(env.mutatingCalls(), ['ui $_udidB content_size']);
    });

    test('push with a nonexistent payload fails on the payload before resolving the device', () async {
      final env = await _FakeEnv.create();

      final result =
          await sendSimPush((bundleId: 'com.example.app', payload: '/nonexistent.json', deviceOverride: null));

      expect(result, isA<SimPushFailed>());
      expect((result as SimPushFailed).message, 'Payload file not found: /nonexistent.json');
      expect(env.calls(), isEmpty);
    });

    test('push with an existing payload and an ambiguous device fails with the ambiguity error', () async {
      final env = await _FakeEnv.create();
      final payload = File('${env.root.path}/payload.json')..writeAsStringSync('{}');

      final result = await sendSimPush((bundleId: 'com.example.app', payload: payload.path, deviceOverride: null));

      expect(result, isA<SimPushFailed>());
      final message = (result as SimPushFailed).message;
      expect(message, contains('Multiple booted iOS simulators'));
      expect(message, contains('--device'));
      expect(env.calls(), ['list devices -j']);
    });
  });

  group('simulator device resolution: session vs. original bug', () {
    test('session = A selects A', () async {
      final env = await _FakeEnv.create(session: _udidA);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    test('session = B selects B', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidB appearance dark']);
    });

    test('switching the session device between calls switches the target', () async {
      final env = await _FakeEnv.create(session: _udidA);
      await overrideSimStatusBar((
        time: '9:41',
        dataNetwork: null,
        wifiMode: null,
        wifiBars: null,
        cellularMode: null,
        cellularBars: null,
        operatorName: null,
        batteryState: null,
        batteryLevel: null,
        deviceOverride: null,
      ));

      env.writeSessionDevice(_udidB);
      await clearSimStatusBar((deviceOverride: null));

      expect(env.mutatingCalls(), ['status_bar $_udidA override --time 9:41', 'status_bar $_udidB clear']);
    });
  });

  group('simulator device resolution: --device override', () {
    test('deviceOverride beats the session device', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimAppearance((mode: 'light', deviceOverride: _udidA));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidA appearance light']);
    });

    test('deviceOverride works with no session and several booted simulators', () async {
      final env = await _FakeEnv.create();

      final result = await clearSimLocation((deviceOverride: _udidB));

      expect(result, isA<SimLocationCleared>());
      expect(env.mutatingCalls(), ['location $_udidB clear']);
    });

    test('deviceOverride with an unknown UDID fails and runs no mutating call', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: 'DDDDDDDD-4444-4444-8444-DDDDDDDDDDDD'));

      expect(result, isA<SimAppearanceFailed>());
      expect((result as SimAppearanceFailed).message, contains('DDDDDDDD-4444-4444-8444-DDDDDDDDDDDD'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('deviceOverride that is shut down fails and runs no mutating call', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidC));

      expect(result, isA<SimAppearanceFailed>());
      final message = (result as SimAppearanceFailed).message;
      expect(message, contains(_udidC));
      expect(message, contains('not booted'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('deviceOverride matches the UDID case-insensitively', () async {
      final env = await _FakeEnv.create();

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidA.toLowerCase()));

      expect(result, isA<SimAppearanceSet>());
      // The call uses the canonical UDID reported by simctl.
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    test('deviceOverride that is only a prefix of a UDID does not match', () async {
      final env = await _FakeEnv.create();

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidA.substring(0, 8)));

      expect(result, isA<SimAppearanceFailed>());
      expect(env.mutatingCalls(), isEmpty);
    });
  });

  group('simulator device resolution: no session', () {
    test('two booted simulators: fails listing both UDIDs and --device, with no mutating call', () async {
      final env = await _FakeEnv.create();

      final result = await overrideSimStatusBar((
        time: '9:41',
        dataNetwork: null,
        wifiMode: null,
        wifiBars: null,
        cellularMode: null,
        cellularBars: null,
        operatorName: null,
        batteryState: null,
        batteryLevel: null,
        deviceOverride: null,
      ));

      expect(result, isA<SimStatusBarFailed>());
      final message = (result as SimStatusBarFailed).message;
      expect(message, contains(_udidA));
      expect(message, contains(_udidB));
      expect(message, contains('Simulator A'));
      expect(message, contains('Simulator B'));
      expect(message, contains('--device'));
      expect(message, isNot(contains(_udidC)), reason: 'shut down simulators are not candidates');
      expect(env.calls(), ['list devices -j']);
    });

    test('exactly one booted simulator: targets its UDID, not "booted"', () async {
      final env = await _FakeEnv.create(booted: [_udidB]);

      final result = await setSimTextSize((size: 'large', deviceOverride: null));

      expect(result, isA<SimTextSizeSet>());
      expect(env.mutatingCalls(), ['ui $_udidB content_size large']);
    });

    test('zero booted simulators: fails with a clear message and no mutating call', () async {
      final env = await _FakeEnv.create(booted: []);

      final result = await setSimTextSize((size: 'large', deviceOverride: null));

      expect(result, isA<SimTextSizeFailed>());
      expect((result as SimTextSizeFailed).message, contains('No booted iOS simulator'));
      expect(env.calls(), ['list devices -j']);
    });

    test('every verb fails without a mutating call when two simulators are booted', () async {
      for (final verb in _verbs) {
        final env = await _FakeEnv.create();

        final result = await verb.run(null);

        expect(verb.succeeded(result), isFalse, reason: '${verb.name}: ${_describeResult(result)}');
        expect(_describeResult(result), contains('--device'), reason: verb.name);
        expect(env.calls(), ['list devices -j'], reason: verb.name);
      }
    });
  });

  group('simulator device resolution: only iOS runtimes are auto-pick candidates', () {
    test('booted watchOS + exactly one booted iPhone, no session: targets the iPhone', () async {
      final env = await _FakeEnv.create(booted: [_udidA], extra: [_watch()]);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    test('booted watchOS + two booted iPhones: ambiguity error lists only the iPhones', () async {
      final env = await _FakeEnv.create(extra: [_watch()]);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      final message = (result as SimAppearanceFailed).message;
      expect(message, contains('Multiple booted iOS simulators'));
      expect(message, contains(_udidA));
      expect(message, contains(_udidB));
      expect(message, isNot(contains(_udidWatch)));
      expect(message, isNot(contains('Watch')));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('only a booted watchOS device: No booted iOS simulator', () async {
      final env = await _FakeEnv.create(booted: [], extra: [_watch()]);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      expect((result as SimAppearanceFailed).message, contains('No booted iOS simulator'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('--device with a watchOS UDID still resolves', () async {
      final env = await _FakeEnv.create(extra: [_watch()]);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidWatch));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidWatch appearance dark']);
    });

    test('a booted iPad on the iOS runtime counts as iOS', () async {
      final env = await _FakeEnv.create(
        booted: [],
        extra: [
          (
            runtime: 'com.apple.CoreSimulator.SimRuntime.iOS-18-0',
            udid: _udidIpad,
            name: 'iPad Pro',
            booted: true,
          ),
        ],
      );

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidIpad appearance dark']);
    });
  });

  group('simulator device resolution: non-simulator session device', () {
    test('Android id + one booted simulator: uses the booted simulator', () async {
      final env = await _FakeEnv.create(booted: [_udidA], session: 'b433094a');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    test('Android id + two booted simulators: ambiguity error', () async {
      final env = await _FakeEnv.create(session: 'b433094a');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      final message = (result as SimAppearanceFailed).message;
      expect(message, contains(_udidA));
      expect(message, contains(_udidB));
      expect(message, contains('--device'));
      expect(env.calls(), ['list devices -j']);
    });

    test('Android id + deviceOverride: the override wins', () async {
      final env = await _FakeEnv.create(session: 'b433094a');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidB));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidB appearance dark']);
    });

    test('Android id + zero booted simulators: fails with a clear message', () async {
      final env = await _FakeEnv.create(booted: [], session: 'b433094a');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      expect((result as SimAppearanceFailed).message, contains('No booted iOS simulator'));
      expect(env.mutatingCalls(), isEmpty);
    });
  });

  group('simulator device resolution: session simulator is not booted', () {
    test('shut down session simulator fails mentioning not booted, with no mutating call', () async {
      final env = await _FakeEnv.create(session: _udidC);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      final message = (result as SimAppearanceFailed).message;
      expect(message, contains(_udidC));
      expect(message, contains('not booted'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('shut down session simulator does not fall back to the only booted simulator', () async {
      final env = await _FakeEnv.create(booted: [_udidA], session: _udidC);

      final result = await clearSimStatusBar((deviceOverride: null));

      expect(result, isA<SimStatusBarFailed>());
      expect((result as SimStatusBarFailed).message, contains('not booted'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('shut down session simulator is overridden by a booted deviceOverride', () async {
      final env = await _FakeEnv.create(session: _udidC);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: _udidA));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidA appearance dark']);
    });

    test('every verb fails without a mutating call for a shut down session simulator', () async {
      for (final verb in _verbs) {
        final env = await _FakeEnv.create(session: _udidC);

        final result = await verb.run(null);

        expect(verb.succeeded(result), isFalse, reason: '${verb.name}: ${_describeResult(result)}');
        expect(_describeResult(result), contains('not booted'), reason: verb.name);
        expect(env.mutatingCalls(), isEmpty, reason: verb.name);
      }
    });
  });

  group('simulator device resolution: UDID matching', () {
    test('session id that is a substring of a UDID does not match it', () async {
      // The unmatched session id is ignored, so with two booted simulators this is ambiguous.
      final env = await _FakeEnv.create(session: _udidB.substring(9, 22));

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>(), reason: 'substring must not select B');
      expect((result as SimAppearanceFailed).message, contains('--device'));
      expect(env.mutatingCalls(), isEmpty);
    });

    test('session id that is a UDID prefix does not match it', () async {
      final env = await _FakeEnv.create(session: _udidB.substring(0, 8));

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      expect(env.mutatingCalls(), isEmpty);
    });

    test('session id matches a UDID case-insensitively', () async {
      final env = await _FakeEnv.create(session: _udidB.toLowerCase());

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidB appearance dark']);
    });

    test('session id with surrounding whitespace in device.txt still matches', () async {
      final env = await _FakeEnv.create(session: '  $_udidB\n');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceSet>());
      expect(env.mutatingCalls(), ['ui $_udidB appearance dark']);
    });
  });

  group('simulator device resolution: simctl failures', () {
    test('a failing `simctl list` becomes a Failed result with no mutating call', () async {
      final env = await _FakeEnv.create(listExitCode: 1);

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      expect(env.mutatingCalls(), isEmpty);
    });

    test('unparseable `simctl list` output becomes a Failed result with no mutating call', () async {
      final env = await _FakeEnv.create(rawListOutput: 'not json');

      final result = await setSimAppearance((mode: 'dark', deviceOverride: null));

      expect(result, isA<SimAppearanceFailed>());
      expect((result as SimAppearanceFailed).message, contains('Could not parse'));
      expect(env.mutatingCalls(), isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Verb table
// ---------------------------------------------------------------------------

/// One invocation of a core verb with expected simctl arguments for a given UDID.
class _Verb {
  const _Verb({
    required this.name,
    required this.run,
    required this.succeeded,
    required this.expectedCall,
  });

  final String name;
  final Future<Object> Function(String? deviceOverride) run;
  final bool Function(Object result) succeeded;
  final String Function(String udid) expectedCall;
}

final _verbs = <_Verb>[
  _Verb(
    name: 'status-bar override',
    run: (deviceOverride) => overrideSimStatusBar((
      time: '9:41',
      dataNetwork: null,
      wifiMode: null,
      wifiBars: null,
      cellularMode: null,
      cellularBars: null,
      operatorName: null,
      batteryState: null,
      batteryLevel: null,
      deviceOverride: deviceOverride,
    )),
    succeeded: (r) => r is SimStatusBarOverridden,
    expectedCall: (udid) => 'status_bar $udid override --time 9:41',
  ),
  _Verb(
    name: 'status-bar clear',
    run: (deviceOverride) => clearSimStatusBar((deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimStatusBarCleared,
    expectedCall: (udid) => 'status_bar $udid clear',
  ),
  _Verb(
    name: 'appearance set',
    run: (deviceOverride) => setSimAppearance((mode: 'dark', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimAppearanceSet,
    expectedCall: (udid) => 'ui $udid appearance dark',
  ),
  _Verb(
    name: 'appearance get',
    run: (deviceOverride) => setSimAppearance((mode: 'get', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimAppearanceQueried,
    expectedCall: (udid) => 'ui $udid appearance',
  ),
  _Verb(
    name: 'text-size set',
    run: (deviceOverride) => setSimTextSize((size: 'large', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimTextSizeSet,
    expectedCall: (udid) => 'ui $udid content_size large',
  ),
  _Verb(
    name: 'text-size get',
    run: (deviceOverride) => setSimTextSize((size: 'get', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimTextSizeQueried,
    expectedCall: (udid) => 'ui $udid content_size',
  ),
  _Verb(
    name: 'location set',
    run: (deviceOverride) =>
        setSimLocation((latitude: '52.2297', longitude: '21.0122', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimLocationSet,
    expectedCall: (udid) => 'location $udid set 52.2297,21.0122',
  ),
  _Verb(
    name: 'location route',
    run: (deviceOverride) => runSimLocationRoute((scenario: 'City Run', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimLocationRouteStarted,
    expectedCall: (udid) => 'location $udid run City Run',
  ),
  _Verb(
    name: 'location clear',
    run: (deviceOverride) => clearSimLocation((deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimLocationCleared,
    expectedCall: (udid) => 'location $udid clear',
  ),
  _Verb(
    name: 'defaults read',
    run: (deviceOverride) =>
        readSimDefaults((bundleId: 'com.example.app', key: 'theme', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimDefaultsReadSuccess,
    expectedCall: (udid) => 'spawn $udid defaults read com.example.app theme',
  ),
  _Verb(
    name: 'defaults write',
    run: (deviceOverride) => writeSimDefaults((
      bundleId: 'com.example.app',
      key: 'theme',
      value: 'dark',
      type: 'string',
      deviceOverride: deviceOverride,
    )),
    succeeded: (r) => r is SimDefaultsWritten,
    expectedCall: (udid) => 'spawn $udid defaults write com.example.app theme -string dark',
  ),
  _Verb(
    name: 'defaults delete',
    run: (deviceOverride) =>
        deleteSimDefaults((bundleId: 'com.example.app', key: 'theme', deviceOverride: deviceOverride)),
    succeeded: (r) => r is SimDefaultsDeleted,
    expectedCall: (udid) => 'spawn $udid defaults delete com.example.app theme',
  ),
];

String _describeResult(Object result) => switch (result) {
      SimStatusBarFailed(:final message) => message,
      SimAppearanceFailed(:final message) => message,
      SimTextSizeFailed(:final message) => message,
      SimLocationFailed(:final message) => message,
      SimDefaultsFailed(:final message) => message,
      SimPushFailed(:final message) => message,
      _ => result.runtimeType.toString(),
    };

// ---------------------------------------------------------------------------
// Fake `xcrun` environment
// ---------------------------------------------------------------------------

/// Temp session dir plus a fake `xcrun` that serves a controllable
/// `simctl list devices -j` and records every other invocation.
///
/// Installing the fake replaces [xcrunExecutable] and the active session
/// directory; both are restored when the current test finishes.
class _FakeEnv {
  _FakeEnv._(this.root, this._callLog);

  final Directory root;
  final File _callLog;

  static Future<_FakeEnv> create({
    List<String> booted = const [_udidA, _udidB],
    List<_ExtraSim> extra = const [],
    String? session,
    int listExitCode = 0,
    String? rawListOutput,
  }) async {
    final root = await Directory.systemTemp.createTemp('fdb_sim_resolution_test_');
    final sessionDir = Directory('${root.path}/.fdb')..createSync(recursive: true);

    final previousXcrun = xcrunExecutable;
    final previousSessionDir = sessionDirPath;
    addTearDown(() async {
      xcrunExecutable = previousXcrun;
      initSessionDirFromPath(previousSessionDir);
      if (root.existsSync()) await root.delete(recursive: true);
    });

    final listFile = File('${root.path}/devices.json')
      ..writeAsStringSync(rawListOutput ?? jsonEncode(_devicesJson(booted, extra)));
    final callLog = File('${root.path}/calls.log')..createSync();

    // `$*` after `shift` drops the leading `simctl`, so each log line is the
    // simctl subcommand and its arguments, e.g. `status_bar <udid> clear`.
    final script = File('${root.path}/xcrun')..writeAsStringSync('''#!/bin/sh
shift
if [ "\$1" = "list" ]; then
  echo "\$*" >> "${callLog.path}"
  cat "${listFile.path}"
  exit $listExitCode
fi
echo "\$*" >> "${callLog.path}"
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
    final env = _FakeEnv._(root, callLog);
    if (session != null) env.writeSessionDevice(session);
    return env;
  }

  void writeSessionDevice(String device) => File(deviceFile).writeAsStringSync(device);

  /// Every recorded simctl invocation, one `subcommand args...` string per call.
  List<String> calls() => _callLog.readAsLinesSync().where((line) => line.isNotEmpty).toList();

  /// Recorded invocations other than the device listing.
  List<String> mutatingCalls() => calls().where((line) => !line.startsWith('list ')).toList();
}

Map<String, Object> _devicesJson(List<String> booted, List<_ExtraSim> extra) {
  Map<String, Object> device(String udid, String name, {bool? isBooted}) => {
        'udid': udid,
        'name': name,
        'state': (isBooted ?? booted.contains(udid)) ? 'Booted' : 'Shutdown',
        'isAvailable': true,
      };
  final devices = <String, List<Object>>{
    'com.apple.CoreSimulator.SimRuntime.iOS-17-5': [
      device(_udidA, 'Simulator A'),
      device(_udidC, 'Simulator C'),
    ],
    'com.apple.CoreSimulator.SimRuntime.iOS-18-0': [
      device(_udidB, 'Simulator B'),
    ],
    'com.apple.CoreSimulator.SimRuntime.watchOS-11-0': <Object>[],
  };
  for (final sim in extra) {
    devices.putIfAbsent(sim.runtime, () => <Object>[]).add(device(sim.udid, sim.name, isBooted: sim.booted));
  }
  return {'devices': devices};
}
