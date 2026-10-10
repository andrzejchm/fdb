import 'dart:convert';
import 'dart:io';

import 'package:fdb/cli/adapters/deeplink_cli.dart';
import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/deeplink/deeplink.dart';
import 'package:fdb/core/commands/grant_permission/grant_permission.dart';
import 'package:fdb/core/commands/screenshot/screenshot.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:test/test.dart';

/// Two booted iOS simulators (A, B), one shut down (C), one Android device.
const _udidA = 'AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA';
const _udidB = 'BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB';
const _udidC = 'CCCCCCCC-3333-4333-8333-CCCCCCCCCCCC';
const _bogus = 'DDDDDDDD-4444-4444-8444-DDDDDDDDDDDD';
const _android = 'emulator-5554';
const _url = 'fdbtest://test/hello?param=value&other=123';

/// Target resolution for `fdb deeplink` (and the other commands that used to
/// fall back to simctl's `booted` alias). Runs against fake `xcrun` and `adb`
/// scripts, so it needs neither Xcode nor a device and is safe on Linux CI.
void main() {
  group('deeplink: iOS simulator target', () {
    test('opens the URL on the session simulator B, never on "booted"', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect((result as DeeplinkOpened).url, _url);
      expect(result.warning, isNull);
      expect(env.xcrunMutatingCalls(), ['openurl $_udidB $_url']);
      expect(env.xcrunCalls().join('\n'), isNot(contains('booted')));
    });

    test('opens the URL on the session simulator A when the session is A', () async {
      final env = await _FakeEnv.create(session: _udidA);

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect(env.xcrunMutatingCalls(), ['openurl $_udidA $_url']);
    });

    test('matches the session UDID case-insensitively and uses the simctl spelling', () async {
      final env = await _FakeEnv.create(session: _udidB.toLowerCase());

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect(env.xcrunMutatingCalls(), ['openurl $_udidB $_url']);
    });

    test('--device A overrides the session simulator B', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: _url, deviceOverride: _udidA));

      expect(result, isA<DeeplinkOpened>());
      expect(env.xcrunMutatingCalls(), ['openurl $_udidA $_url']);
    });

    test('--device works without a session', () async {
      final env = await _FakeEnv.create();

      final result = await openDeeplink((url: _url, deviceOverride: _udidA));

      expect(result, isA<DeeplinkOpened>());
      expect(env.xcrunMutatingCalls(), ['openurl $_udidA $_url']);
    });

    test('a shut down session simulator fails without opening the URL anywhere', () async {
      final env = await _FakeEnv.create(session: _udidC);

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkDeviceUnresolved>());
      final message = (result as DeeplinkDeviceUnresolved).message;
      expect(message, startsWith('The session simulator $_udidC (Simulator C) is not booted (state: Shutdown).'));
      expect(message, contains('--device <udid>'));
      expect(env.xcrunMutatingCalls(), isEmpty);
      expect(env.adbMutatingCalls(), isEmpty);
    });

    test('a shut down --device fails without opening the URL anywhere', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: _url, deviceOverride: _udidC));

      expect(result, isA<DeeplinkDeviceUnresolved>());
      expect((result as DeeplinkDeviceUnresolved).message,
          'Simulator $_udidC (Simulator C) is not booted (state: Shutdown).');
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('an https URL opens on the session simulator with the Universal Links warning', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: 'https://example.com/p/1', deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect((result as DeeplinkOpened).warning, startsWith('WARNING: Universal Links'));
      expect(env.xcrunMutatingCalls(), ['openurl $_udidB https://example.com/p/1']);
    });

    test('a simctl openurl failure is reported with its stderr', () async {
      final env = await _FakeEnv.create(session: _udidB, openurlError: 'OSStatus error -10814');

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkFailed>());
      expect((result as DeeplinkFailed).details, 'OSStatus error -10814');
      expect(env.xcrunMutatingCalls(), ['openurl $_udidB $_url']);
    });
  });

  group('deeplink: Android target', () {
    test('the session Android device is addressed with adb -s', () async {
      final env = await _FakeEnv.create(session: _android);

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect(env.adbMutatingCalls(), [
        '-s $_android shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d $_url',
      ]);
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('--device with an Android serial overrides a simulator session', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: _url, deviceOverride: _android));

      expect(result, isA<DeeplinkOpened>());
      expect(env.adbMutatingCalls().single, startsWith('-s $_android shell am start'));
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('a serial that is only a prefix of a connected device does not match', () async {
      final env = await _FakeEnv.create(session: 'emulator-55');

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkUnsupportedPlatform>());
      expect(env.adbMutatingCalls(), isEmpty);
    });

    test('an am start error is reported as a failure', () async {
      await _FakeEnv.create(session: _android, amStartOutput: 'Error: Activity not started');

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkFailed>());
      expect((result as DeeplinkFailed).details, 'Error: Activity not started');
    });
  });

  group('deeplink: no usable target', () {
    test('no session and no --device reports no session without running any tool', () async {
      final env = await _FakeEnv.create();

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkNoSession>());
      expect(env.xcrunCalls(), isEmpty);
      expect(env.adbCalls(), isEmpty);
    });

    test('a session device that is neither a simulator nor an adb device is unsupported', () async {
      final env = await _FakeEnv.create(session: '00008110-000A1B2C3D4E5F60');

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkUnsupportedPlatform>());
      expect(env.xcrunMutatingCalls(), isEmpty);
      expect(env.adbMutatingCalls(), isEmpty);
    });

    test('an unknown --device fails with a device error, not the platform error', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final result = await openDeeplink((url: _url, deviceOverride: _bogus));

      expect(result, isA<DeeplinkDeviceUnresolved>());
      expect(
        (result as DeeplinkDeviceUnresolved).message,
        'No iOS simulator or Android device with ID $_bogus. List devices with: fdb devices',
      );
      expect(env.xcrunMutatingCalls(), isEmpty);
      expect(env.adbMutatingCalls(), isEmpty);
    });

    test('a failing simctl listing still lets an Android session through', () async {
      final env = await _FakeEnv.create(session: _android, listExitCode: 1);

      final result = await openDeeplink((url: _url, deviceOverride: null));

      expect(result, isA<DeeplinkOpened>());
      expect(env.adbMutatingCalls().single, startsWith('-s $_android '));
    });
  });

  group('deeplink CLI', () {
    test('prints DEEPLINK_OPENED for the session simulator', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final run = await _runCli([_url]);

      expect(run.exitCode, 0, reason: run.stderr);
      expect(run.stdout, 'DEEPLINK_OPENED=$_url\n');
      expect(run.stderr, isEmpty);
      expect(env.xcrunMutatingCalls(), ['openurl $_udidB $_url']);
    });

    for (final args in [
      [_url, '--device', _udidA],
      ['--device', _udidA, _url],
      ['--device=$_udidA', _url],
    ]) {
      test('${args.join(' ')} targets A', () async {
        final env = await _FakeEnv.create(session: _udidB);

        final run = await _runCli(args);

        expect(run.exitCode, 0, reason: run.stderr);
        expect(run.stdout, 'DEEPLINK_OPENED=$_url\n');
        expect(env.xcrunMutatingCalls(), ['openurl $_udidA $_url']);
      });
    }

    test('writes the https warning to stderr and the token to stdout', () async {
      await _FakeEnv.create(session: _udidB);

      final run = await _runCli(['https://example.com']);

      expect(run.exitCode, 0);
      expect(run.stdout, 'DEEPLINK_OPENED=https://example.com\n');
      expect(
        run.stderr,
        'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator\n',
      );
    });

    test('no URL keeps the original error', () async {
      await _FakeEnv.create(session: _udidB);

      final run = await _runCli(['--device', _udidA]);

      expect(run.exitCode, 1);
      expect(run.stderr, 'ERROR: No URL provided\n');
    });

    test('no session keeps the original error', () async {
      await _FakeEnv.create();

      final run = await _runCli([_url]);

      expect(run.exitCode, 1);
      expect(run.stderr, 'ERROR: No active fdb session found. Run fdb launch first.\n');
    });

    test('an open failure keeps the original error prefix', () async {
      await _FakeEnv.create(session: _udidB, openurlError: 'OSStatus error -10814');

      final run = await _runCli([_url]);

      expect(run.exitCode, 1);
      expect(run.stderr, 'ERROR: Failed to open deep link: OSStatus error -10814\n');
    });

    test('an unknown --device prints the device error', () async {
      final env = await _FakeEnv.create(session: _udidB);

      final run = await _runCli([_url, '--device', _bogus]);

      expect(run.exitCode, 1);
      expect(run.stdout, isEmpty);
      expect(run.stderr, startsWith('ERROR: No iOS simulator or Android device with ID $_bogus.'));
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('--help documents --device', () async {
      await _FakeEnv.create();

      final run = await _runCli(['--help']);

      expect(run.exitCode, 0);
      expect(run.stdout, contains('--device'));
    });
  });

  group('screenshot and grant-permission no longer fall back to "booted"', () {
    test('screenshot with no session device captures the only booted simulator', () async {
      final env = await _FakeEnv.create(booted: [_udidA], platform: 'ios');
      final output = '${env.root.path}/shot.png';

      final result = await captureScreenshot((output: output, fullResolution: true));

      expect(result, isA<ScreenshotSaved>(), reason: '$result');
      expect(env.xcrunMutatingCalls(), ['io $_udidA screenshot $output']);
    });

    test('screenshot with no session device and two booted simulators fails instead of guessing', () async {
      final env = await _FakeEnv.create(platform: 'ios');

      final result = await captureScreenshot((output: '${env.root.path}/shot.png', fullResolution: true));

      expect(result, isA<ScreenshotFailed>());
      expect((result as ScreenshotFailed).message, startsWith('Multiple booted iOS simulators'));
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('screenshot still uses the session device directly', () async {
      final env = await _FakeEnv.create(session: _udidB, platform: 'ios');
      final output = '${env.root.path}/shot.png';

      final result = await captureScreenshot((output: output, fullResolution: true));

      expect(result, isA<ScreenshotSaved>(), reason: '$result');
      expect(env.xcrunMutatingCalls(), ['io $_udidB screenshot $output']);
    });

    GrantPermissionInput grantCamera() => (
          permission: 'camera',
          action: GrantPermissionAction.grant,
          resetAll: false,
          bundleOverride: 'com.example.app',
          deviceOverride: null,
        );

    test('grant-permission with no session device targets the only booted simulator', () async {
      final env = await _FakeEnv.create(booted: [_udidA], platform: 'ios');

      final result = await grantPermission(grantCamera());

      expect(result, isA<GrantPermissionIosSimulatorSuccess>(), reason: '$result');
      expect(env.xcrunMutatingCalls(), ['privacy $_udidA grant camera com.example.app']);
    });

    test('grant-permission with no session device and two booted simulators fails instead of guessing', () async {
      final env = await _FakeEnv.create(platform: 'ios');

      final result = await grantPermission(grantCamera());

      expect(result, isA<GrantPermissionError>());
      expect((result as GrantPermissionError).message, startsWith('Multiple booted iOS simulators'));
      expect(env.xcrunMutatingCalls(), isEmpty);
    });

    test('grant-permission still uses the session device directly', () async {
      final env = await _FakeEnv.create(session: _udidB, platform: 'ios');

      final result = await grantPermission(grantCamera());

      expect(result, isA<GrantPermissionIosSimulatorSuccess>(), reason: '$result');
      expect(env.xcrunMutatingCalls(), ['privacy $_udidB grant camera com.example.app']);
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEnv {
  _FakeEnv._(this.root, this._xcrunLog, this._adbLog);

  final Directory root;
  final File _xcrunLog;
  final File _adbLog;

  static Future<_FakeEnv> create({
    List<String> booted = const [_udidA, _udidB],
    String? session,
    String? platform,
    String? openurlError,
    String amStartOutput = 'Starting: Intent { act=android.intent.action.VIEW }\nStatus: ok',
    int listExitCode = 0,
  }) async {
    final root = await Directory.systemTemp.createTemp('fdb_deeplink_resolution_test_');
    final sessionDir = Directory('${root.path}/.fdb')..createSync(recursive: true);

    final previousXcrun = xcrunExecutable;
    final previousAdb = adbExecutable;
    final previousSessionDir = sessionDirPath;
    addTearDown(() async {
      xcrunExecutable = previousXcrun;
      adbExecutable = previousAdb;
      initSessionDirFromPath(previousSessionDir);
      if (root.existsSync()) await root.delete(recursive: true);
    });

    final listFile = File('${root.path}/devices.json')..writeAsStringSync(jsonEncode(_devicesJson(booted)));
    final xcrunLog = File('${root.path}/xcrun.log')..createSync();
    final adbLog = File('${root.path}/adb.log')..createSync();
    final amOutputFile = File('${root.path}/am_start.txt')..writeAsStringSync(amStartOutput);
    final openurlFailure = openurlError == null ? '' : 'echo "$openurlError" >&2\n  exit 1';

    // `shift` drops the leading `simctl`, so each log line is the simctl
    // subcommand and its arguments, e.g. `openurl <udid> <url>`.
    final xcrun = File('${root.path}/xcrun')..writeAsStringSync('''#!/bin/sh
shift
echo "\$*" >> "${xcrunLog.path}"
case "\$1" in
  list)
    cat "${listFile.path}"
    exit $listExitCode
    ;;
  openurl)
    $openurlFailure
    ;;
  io)
    printf 'png' > "\$4"
    ;;
esac
exit 0
''');
    final adb = File('${root.path}/adb')..writeAsStringSync('''#!/bin/sh
echo "\$*" >> "${adbLog.path}"
if [ "\$1" = "devices" ]; then
  printf 'List of devices attached\\n$_android\\tdevice\\nemulator-5556\\toffline\\n\\n'
  exit 0
fi
cat "${amOutputFile.path}"
exit 0
''');
    await Process.run('chmod', ['+x', xcrun.path, adb.path]);

    xcrunExecutable = xcrun.path;
    adbExecutable = adb.path;
    initSessionDirFromPath(sessionDir.path);
    if (session != null) File(deviceFile).writeAsStringSync(session);
    if (platform != null) File(platformFile).writeAsStringSync('$platform true');
    return _FakeEnv._(root, xcrunLog, adbLog);
  }

  static List<String> _lines(File log) => log.readAsLinesSync().where((line) => line.isNotEmpty).toList();

  List<String> xcrunCalls() => _lines(_xcrunLog);

  /// simctl invocations other than the device listing.
  List<String> xcrunMutatingCalls() => xcrunCalls().where((line) => !line.startsWith('list ')).toList();

  List<String> adbCalls() => _lines(_adbLog);

  /// adb invocations other than `adb devices`.
  List<String> adbMutatingCalls() => adbCalls().where((line) => line != 'devices').toList();
}

Map<String, Object> _devicesJson(List<String> booted) {
  Map<String, Object> device(String udid, String name) => {
        'udid': udid,
        'name': name,
        'state': booted.contains(udid) ? 'Booted' : 'Shutdown',
        'isAvailable': true,
      };
  return {
    'devices': {
      'com.apple.CoreSimulator.SimRuntime.iOS-17-5': [device(_udidA, 'Simulator A'), device(_udidC, 'Simulator C')],
      'com.apple.CoreSimulator.SimRuntime.iOS-18-0': [device(_udidB, 'Simulator B')],
    },
  };
}

typedef _CliRun = ({int exitCode, String stdout, String stderr});

Future<_CliRun> _runCli(List<String> args) async {
  final out = _CapturedStdout();
  final err = _CapturedStdout();
  final exitCode = await IOOverrides.runZoned(
    () => runDeeplinkCli(args),
    stdout: () => out,
    stderr: () => err,
  );
  return (exitCode: exitCode, stdout: out.text, stderr: err.text);
}

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
