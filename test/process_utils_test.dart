import 'dart:io';

import 'package:fdb/core/commands/kill/kill.dart';
import 'package:fdb/src/controller/process_utils.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('isToolOnPath (which/where dispatch — which branch exercised on the current host)', () {
    test('returns true for a tool that is definitely on PATH', () {
      // The test runner itself is invoked via `dart`, so it must be resolvable.
      expect(isToolOnPath('dart'), isTrue);
    });

    test('returns false for a tool name that does not exist', () {
      expect(isToolOnPath('fdb-definitely-not-a-real-binary-xyz'), isFalse);
    });
  });

  group('non-positive PIDs', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fdb_pid_nonpositive_test_');
      final session = Directory('${root.path}/.fdb')..createSync(recursive: true);
      initSessionDirFromPath(session.path);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('PID readers return null for 0 and negative values', () {
      for (final content in ['0', '-1', ' -1\n']) {
        File(pidFile).writeAsStringSync(content);
        File(appPidFile).writeAsStringSync(content);
        File(controllerPidFile).writeAsStringSync(content);
        File(logCollectorPidFile).writeAsStringSync(content);

        expect(readPid(), isNull, reason: 'readPid for "$content"');
        expect(readAppPid(), isNull, reason: 'readAppPid for "$content"');
        expect(readControllerPid(), isNull, reason: 'readControllerPid for "$content"');
        expect(readLogCollectorPid(), isNull, reason: 'readLogCollectorPid for "$content"');
      }
    });

    test('PID readers still return positive PIDs', () {
      File(pidFile).writeAsStringSync('123');
      File(appPidFile).writeAsStringSync('456\n');
      File(controllerPidFile).writeAsStringSync('789');
      File(logCollectorPidFile).writeAsStringSync('1011');

      expect(readPid(), 123);
      expect(readAppPid(), 456);
      expect(readControllerPid(), 789);
      expect(readLogCollectorPid(), 1011);
    });

    test('isAppPidAlive returns false for 0 and negative PIDs on every platform', () {
      for (final platform in ['macos false', 'ios true', 'ios false', 'linux false', 'web-javascript false']) {
        File(platformFile).writeAsStringSync(platform);
        expect(isAppPidAlive(0), isFalse, reason: platform);
        expect(isAppPidAlive(-1), isFalse, reason: platform);
      }
    });

    test('isAppPidAlive still returns true for the current process', () {
      File(platformFile).writeAsStringSync('macos false');
      expect(isAppPidAlive(pid), isTrue);
    });

    test('isAndroidAppPidAlive returns false for 0 and negative PIDs', () {
      // A fake adb whose `ps -A` output lists PIDs -1 and 0, so only the guard
      // keeps these from matching.
      final fakeAdb = File('${root.path}/adb')..writeAsStringSync('''#!/bin/sh
echo "USER PID PPID NAME"
echo "u0_a1 -1 1 com.example.app"
echo "u0_a1 0 1 com.example.app"
exit 0
''');
      Process.runSync('chmod', ['+x', fakeAdb.path]);
      final originalAdb = adbExecutable;
      adbExecutable = fakeAdb.path;
      addTearDown(() => adbExecutable = originalAdb);
      File(platformFile).writeAsStringSync('android-arm64 true');
      File(deviceFile).writeAsStringSync('emulator-5554');

      expect(isAndroidAppPidAlive(-1), isFalse);
      expect(isAndroidAppPidAlive(0), isFalse);
      expect(isAppPidAlive(-1), isFalse);
    });

    // These tests only ever use a recording fake signaller, so even with the
    // guards removed they cannot send a real signal to 0 or -1.
    test('terminateProcess never signals 0 or negative PIDs', () async {
      final signalled = <int>[];
      bool fakeSignal(int target, ProcessSignal signal) {
        signalled.add(target);
        return true;
      }

      for (final target in [-1, 0]) {
        final stopped = await terminateProcess(
          target,
          timeout: const Duration(milliseconds: 100),
          sendSignal: fakeSignal,
        );
        expect(stopped, isTrue, reason: 'pid $target');
      }
      expect(signalled, isEmpty);
    });

    test('terminateProcess sends signals through the injected signaller', () async {
      final process = await Process.start('sleep', ['60']);
      addTearDown(process.kill);
      final signals = <(int, ProcessSignal)>[];
      bool fakeSignal(int target, ProcessSignal signal) {
        signals.add((target, signal));
        // Only ever forward to the sleep process started above.
        return target == process.pid && process.kill(signal);
      }

      final stopped = await terminateProcess(
        process.pid,
        timeout: const Duration(seconds: 5),
        sendSignal: fakeSignal,
      );

      expect(stopped, isTrue);
      expect(signals, [(process.pid, ProcessSignal.sigterm)]);
    });

    test('killApp never signals 0 or negative PIDs from PID files', () async {
      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync('-1');
      File(pidFile).writeAsStringSync('-1');
      File(controllerPidFile).writeAsStringSync('0');
      File(logCollectorPidFile).writeAsStringSync('-1');
      final signalled = <int>[];

      final result = await killApp((), sendSignal: (target, signal) {
        signalled.add(target);
        return true;
      });

      expect(result, isA<KillSuccess>());
      expect(signalled, isEmpty);
      expect(File(appPidFile).existsSync(), isFalse);
    });
  });
}
