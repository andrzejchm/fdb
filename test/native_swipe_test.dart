import 'dart:async';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/native_swipe/native_swipe.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:test/test.dart';

const _input = (fromX: 150.0, fromY: 1.0, toX: 150.0, toY: 650.0, durationMs: 600);
const _viewport = 'Viewport INTERNAL: displayId=0, orientation=0, logicalFrame=[0, 0, 402, 874]';

void main() {
  late Directory session;
  setUp(() async {
    session = await Directory.systemTemp.createTemp('fdb-native-swipe-test-');
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

  test('validates both endpoints and bounded positive integer duration before any process', () async {
    metadata('android-arm64 false');
    var calls = 0;
    for (final input in [
      (fromX: double.nan, fromY: 1.0, toX: 1.0, toY: 2.0, durationMs: 600),
      (fromX: 0.0, fromY: 1.0, toX: double.infinity, toY: 2.0, durationMs: 600),
      (fromX: 0.0, fromY: 1.0, toX: 1.0, toY: -2.0, durationMs: 600),
      (fromX: 1.0, fromY: 1.0, toX: 1.0, toY: 1.0, durationMs: 600),
      (fromX: 0.0, fromY: 1.0, toX: 1.0, toY: 2.0, durationMs: 0),
      (fromX: 0.0, fromY: 1.0, toX: 1.0, toY: 2.0, durationMs: 60001),
    ]) {
      expect(
          await nativeSwipe(input, runner: (_, __, ___) async {
            calls++;
            return (exitCode: 0, stdout: _viewport, stderr: '');
          }),
          isA<NativeSwipeError>());
      expect(validateNativeSwipe(input), isNotNull);
    }
    expect(calls, 0);
  });

  test('requires recorded platform and exact device, without choosing a default', () async {
    var calls = 0;
    Future<HidProcessOutput> run(String e, List<String> a, Duration t) async {
      calls++;
      return (exitCode: 0, stdout: '', stderr: '');
    }

    expect(await nativeSwipe(_input, runner: run), isA<NativeSwipeError>());
    for (final platform in ['ios true', 'android-arm64 false']) {
      metadata(platform, device: null);
      expect(await nativeSwipe(_input, runner: run),
          isA<NativeSwipeError>().having((r) => r.message, 'message', contains('No device ID')));
    }
    expect(calls, 0);
  });

  test('macOS and physical iOS fail without running a platform tool', () async {
    for (final platform in ['darwin false', 'ios false']) {
      metadata(platform);
      expect(await nativeSwipe(_input, runner: (_, __, ___) async => throw StateError('must not run')),
          isA<NativeSwipeError>().having((r) => r.message, 'message', contains('not supported')));
    }
  });

  test('Android targets the recorded serial even with dead controller/absent VM metadata', () async {
    metadata('android-arm64 false');
    final calls = <List<String>>[];
    final result = await nativeSwipe(_input, runner: (e, a, t) async {
      expect(e, 'adb');
      calls.add(a);
      if (a.contains('dumpsys')) return (exitCode: 0, stdout: _viewport, stderr: '');
      expect(t, const Duration(milliseconds: 30600));
      return (exitCode: 0, stdout: '', stderr: '');
    });
    expect(result, isA<NativeSwipeSuccess>());
    expect(calls, [
      ['-s', 'exact-device', 'shell', 'dumpsys', 'input'],
      ['-s', 'exact-device', 'shell', 'input', 'swipe', '150.0', '1.0', '150.0', '650.0', '600'],
    ]);
  });

  test('Android rejects end outside rotated display bounds before down', () async {
    metadata('android-arm64 false');
    var calls = 0;
    final result = await nativeSwipe(_input, runner: (e, a, t) async {
      calls++;
      return (exitCode: 0, stdout: _viewport.replaceFirst('402, 874', '874, 402'), stderr: '');
    });
    expect(result, isA<NativeSwipeError>().having((r) => r.message, 'message', contains('outside the screen')));
    expect(calls, 1);
    expect(parseAndroidSwipeScreen('Viewport: displayId=1, logicalFrame=[0, 0, 99, 99]'), isNull);
    expect(parseAndroidSwipeScreen('unknown'), isNull);
  });

  test('Android reports permission denial, transport failure and timeout without retry', () async {
    metadata('android-arm64 false');
    for (final failure in [
      (exitCode: 0, stdout: '', stderr: 'java.lang.SecurityException: INJECT_EVENTS'),
      (exitCode: 1, stdout: '', stderr: 'device offline'),
      TimeoutException('uncertain'),
    ]) {
      var gestures = 0;
      final result = await nativeSwipe(_input, runner: (e, a, t) async {
        if (a.contains('dumpsys')) return (exitCode: 0, stdout: _viewport, stderr: '');
        gestures++;
        if (failure is TimeoutException) throw failure;
        return failure as HidProcessOutput;
      });
      expect(result, isA<NativeSwipeError>());
      expect(gestures, 1);
    }
  });

  group('iOS cached helper', () {
    late Directory cache;
    setUp(() async {
      cache = await Directory.systemTemp.createTemp('fdb-swipe-cache-');
      File(iosSimulatorHidBinaryPath(cache.path)).writeAsStringSync('cached');
    });
    tearDown(() => cache.delete(recursive: true));

    Future<IosSimulatorHidResult> swipe(HidProcessRunner run, {int duration = 600}) => iosSimulatorHidSwipe(
          udid: 'EXACT-UDID',
          fromX: 150,
          fromY: 1,
          toX: 150,
          toY: 650,
          durationMs: duration,
          runner: run,
          cacheDir: cache.path,
          environment: {'DEVELOPER_DIR': '/developer'},
        );

    test('passes exact target and endpoints with duration-aware cleanup budget', () async {
      for (final duration in [1, 600, 60000]) {
        final result = await swipe((e, a, t) async {
          expect(a, ['swipe', '/developer', 'EXACT-UDID', '150.0', '1.0', '150.0', '650.0', '$duration']);
          expect(t.inMilliseconds, duration + 35000);
          return (exitCode: 0, stdout: 'SWIPED', stderr: '');
        }, duration: duration);
        expect(result, isA<IosSimulatorHidTapped>());
      }
    });

    test('partial delivery, silent signal death and timeout never run a second gesture', () async {
      for (final failure in [
        (exitCode: 4, stdout: '', stderr: 'ERROR: touch partially delivered; cleanup failed'),
        (exitCode: -11, stdout: '', stderr: ''),
        TimeoutException('uncertain'),
      ]) {
        var calls = 0;
        final result = await swipe((e, a, t) async {
          calls++;
          if (failure is TimeoutException) throw failure;
          return failure as HidProcessOutput;
        });
        expect(result, isA<IosSimulatorHidFailed>());
        expect(calls, 1);
      }
    });

    test('bounds and unknown orientation remain explicit errors', () async {
      for (final code in [3, 5]) {
        final result = await swipe((e, a, t) async => (exitCode: code, stdout: '', stderr: 'ERROR: refused'));
        expect(result, code == 3 ? isA<IosSimulatorHidOutOfBounds>() : isA<IosSimulatorHidOrientationUnknown>());
      }
    });
  });

  test('CLI validates required flags and malformed numbers even without live session', () async {
    final script = File('bin/fdb.dart').absolute.path;
    for (final args in [
      <String>[],
      ['--from', '1,2'],
      ['--from', '1,2', '--to', '2,3'],
      ['--from', 'NaN,2', '--to', '2,3', '--duration', '600'],
      ['--from', '1,2', '--to', '2,3', '--duration', '1.5'],
      ['--from', '1,2', '--to', '2,3', '--duration', '-1'],
    ]) {
      final result = await Process.run(
          Platform.resolvedExecutable, [script, '--session-dir', session.path, 'native-swipe', ...args]);
      expect(result.exitCode, 1, reason: '$args');
      expect(result.stderr, startsWith('ERROR: '));
      expect(result.stdout, isEmpty);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('process timeout waits for swipe SIGTERM cleanup before returning uncertainty', () async {
    final script = File('${session.path}/helper.sh');
    final marker = File('${session.path}/released');
    await script.writeAsString(r'''#!/bin/sh
trap 'kill "$child"; printf released > "$2"; exit 0' TERM
sleep 60 &
child=$!
wait "$child"
''');
    final chmod = await Process.run('chmod', ['+x', script.path]);
    expect(chmod.exitCode, 0);
    await expectLater(
      runHidProcess(script.path, ['swipe', marker.path], const Duration(seconds: 2)),
      throwsA(isA<TimeoutException>()),
    );
    expect(marker.readAsStringSync(), 'released', reason: 'SIGTERM cleanup completed before timeout returned');
  }, skip: Platform.isWindows ? 'POSIX signal cleanup is used by the macOS-only iOS helper' : false);
}
