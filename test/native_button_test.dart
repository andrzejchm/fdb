import 'dart:async';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/native_button/native_button.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:test/test.dart';

void main() {
  late Directory session;
  setUp(() async {
    session = await Directory.systemTemp.createTemp('fdb-button-test-');
    initSessionDirFromPath(session.path);
  });
  tearDown(() async {
    await session.delete(recursive: true);
    initSessionDir(Directory.current.path);
  });
  void metadata(String platform, {String? device = 'exact-device'}) {
    File(platformFile).writeAsStringSync(platform);
    if (device != null) File(deviceFile).writeAsStringSync(device);
  }

  test('invalid button, missing metadata/device and unsupported targets deliver nothing', () async {
    Future<HidProcessOutput> forbidden(String e, List<String> a, Duration t) async => throw StateError('must not run');
    expect(await nativeButton((button: 'home'), runner: forbidden), isA<NativeButtonError>());
    metadata('android-arm64 false', device: null);
    expect(await nativeButton((button: 'lock'), runner: forbidden),
        isA<NativeButtonError>().having((r) => r.message, 'message', contains('No device ID')));
    for (final platform in ['ios false', 'darwin false', 'windows false']) {
      metadata(platform);
      expect(await nativeButton((button: 'home'), runner: forbidden),
          isA<NativeButtonError>().having((r) => r.message, 'message', contains('not supported')));
    }
    expect(await nativeButton((button: 'power'), runner: forbidden),
        isA<NativeButtonError>().having((r) => r.message, 'message', contains('home or lock')));
  });

  test('Android sends only one exact-serial keyevent without VM or display probes', () async {
    metadata('android-arm64 false');
    for (final button in ['home', 'lock']) {
      var calls = 0;
      final result = await nativeButton((button: button), runner: (e, a, t) async {
        calls++;
        expect(e, 'adb');
        expect(a,
            ['-s', 'exact-device', 'shell', 'input', 'keyevent', button == 'home' ? 'KEYCODE_HOME' : 'KEYCODE_POWER']);
        return (exitCode: 0, stdout: '', stderr: '');
      });
      expect(result, isA<NativeButtonSuccess>().having((r) => r.button, 'button', button));
      expect(calls, 1);
    }
  });

  test('Android failures and timeout are not retried', () async {
    metadata('android-arm64 false');
    for (final failure in [
      (exitCode: 0, stdout: '', stderr: 'SecurityException: INJECT_EVENTS'),
      (exitCode: 1, stdout: '', stderr: 'device offline'),
      (exitCode: 0, stdout: 'Error: unknown key', stderr: ''),
      TimeoutException('uncertain'),
    ]) {
      var calls = 0;
      final result = await nativeButton((button: 'lock'), runner: (e, a, t) async {
        calls++;
        if (failure is TimeoutException) throw failure;
        return failure as HidProcessOutput;
      });
      expect(result, isA<NativeButtonError>());
      expect(calls, 1);
    }
  });

  test('cached simulator button targets exact UDID and requires delivery acknowledgement', () async {
    File(iosSimulatorHidBinaryPath(session.path)).writeAsStringSync('cached');
    for (final button in ['home', 'lock']) {
      for (final output in [
        (exitCode: 0, stdout: 'BUTTON=$button\n', stderr: ''),
        (exitCode: 0, stdout: '', stderr: ''),
        (exitCode: 1, stdout: '', stderr: 'ERROR: simulator not booted'),
        (exitCode: 4, stdout: '', stderr: 'ERROR: uncertain down'),
        (exitCode: -11, stdout: '', stderr: ''),
        TimeoutException('uncertain'),
      ]) {
        var calls = 0;
        final result = await iosSimulatorHidButton(
          udid: 'EXACT-UDID',
          button: button,
          cacheDir: session.path,
          environment: {'DEVELOPER_DIR': '/developer'},
          runner: (e, a, t) async {
            calls++;
            expect(a, ['button', '/developer', 'EXACT-UDID', button]);
            if (output is TimeoutException) throw output;
            return output as HidProcessOutput;
          },
        );
        expect(
            result,
            output is HidProcessOutput && output.stdout.startsWith('BUTTON=')
                ? isA<IosSimulatorHidTapped>()
                : isNot(isA<IosSimulatorHidTapped>()));
        expect(calls, 1, reason: 'even silent signal death must not repeat lock');
      }
    }
  });

  test('CLI validation and help work with absent or dead session', () async {
    final script = File('bin/fdb.dart').absolute.path;
    for (final args in [
      <String>[],
      ['power'],
      ['HOME'],
      ['home', 'lock'],
      ['home', '--device', 'other']
    ]) {
      final result = await Process.run(
          Platform.resolvedExecutable, [script, '--session-dir', session.path, 'native-button', ...args]);
      expect(result.exitCode, 1);
      expect(result.stderr, 'ERROR: Expected one button: home or lock.\n');
      expect(result.stdout, isEmpty);
    }
    for (final flag in ['--help', '-h']) {
      final result = await Process.run(Platform.resolvedExecutable, [script, 'native-button', flag]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('home|lock'));
      expect(result.stdout, contains('may sleep or wake'));
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
