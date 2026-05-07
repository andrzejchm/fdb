import 'dart:io';

import 'package:fdb/core/commands/kill/kill.dart';
import 'package:fdb/core/commands/status/status.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('status', () {
    test('reports running from disk VM URI when controller is unavailable', () async {
      final root = await _createTempSessionRoot();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.transform(WebSocketTransformer()).listen((socket) => socket.close());
      addTearDown(() async {
        await server.close(force: true);
        await root.delete(recursive: true);
      });

      final uri = 'ws://127.0.0.1:${server.port}/ws';
      File(vmUriFile).writeAsStringSync(uri);

      final result = await getStatus(());

      expect(result.running, isTrue);
      expect(result.pid, isNull);
      expect(result.vmServiceUri, uri);
    });

    test('reports running with live app PID when VM URI is stale', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      final toolProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await _killIfAlive(toolProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(pidFile).writeAsStringSync(toolProcess.pid.toString());
      File(vmUriFile).writeAsStringSync('ws://127.0.0.1:1/stale');

      final result = await getStatus(());

      expect(result.running, isTrue);
      expect(result.pid, appProcess.pid);
      expect(result.vmServiceUri, isNull);
    });

    test('reports running with live iOS simulator app PID when VM URI is stale', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('ios true');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(vmUriFile).writeAsStringSync('ws://127.0.0.1:1/stale');

      final result = await getStatus(());

      expect(result.running, isTrue);
      expect(result.pid, appProcess.pid);
      expect(result.vmServiceUri, isNull);
    });
  });

  group('kill', () {
    test('best-effort cleans session when controller is unavailable', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      final toolProcess = await _startSleepProcess();
      final controllerProcess = await _startSleepProcess();
      final collectorProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await _killIfAlive(toolProcess.pid);
        await _killIfAlive(controllerProcess.pid);
        await _killIfAlive(collectorProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(pidFile).writeAsStringSync(toolProcess.pid.toString());
      File(controllerPidFile).writeAsStringSync(controllerProcess.pid.toString());
      File(logCollectorPidFile).writeAsStringSync(collectorProcess.pid.toString());
      File(vmUriFile).writeAsStringSync('ws://127.0.0.1:1/stale');

      final result = await killApp(());

      expect(result, isA<KillSuccess>());
      await _expectProcessDead(appProcess.pid);
      await _expectProcessDead(toolProcess.pid);
      await _expectProcessDead(controllerProcess.pid);
      await _expectProcessDead(collectorProcess.pid);
      expect(File(appPidFile).existsSync(), isFalse);
      expect(File(pidFile).existsSync(), isFalse);
      expect(File(controllerPidFile).existsSync(), isFalse);
      expect(File(logCollectorPidFile).existsSync(), isFalse);
      expect(File(vmUriFile).existsSync(), isFalse);
    });

    test('force-stops Android app during fallback cleanup', () async {
      final root = await _createTempSessionRoot();
      final fakeAdb = File('${root.path}/adb');
      fakeAdb.writeAsStringSync('''#!/bin/sh
printf '%s\n' "\$@" > "${root.path}/adb_args"
exit 0
''');
      await Process.run('chmod', ['+x', fakeAdb.path]);
      final originalAdb = adbExecutable;
      adbExecutable = fakeAdb.path;
      addTearDown(() async {
        adbExecutable = originalAdb;
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('android-arm64 false');
      File(deviceFile).writeAsStringSync('emulator-5554');
      File(appIdFile).writeAsStringSync('com.example.app');
      File(appPidFile).writeAsStringSync('1234');
      File(vmUriFile).writeAsStringSync('ws://127.0.0.1:1/stale');

      final result = await killApp(());

      expect(result, isA<KillSuccess>());
      expect(
        File('${root.path}/adb_args').readAsLinesSync(),
        ['-s', 'emulator-5554', 'shell', 'am', 'force-stop', 'com.example.app'],
      );
      expect(File(appPidFile).existsSync(), isFalse);
    });
  });
}

Future<Directory> _createTempSessionRoot() async {
  final root = await Directory.systemTemp.createTemp('fdb_session_test_');
  final session = Directory('${root.path}/.fdb');
  session.createSync(recursive: true);
  initSessionDirFromPath(session.path);
  return root;
}

Future<Process> _startSleepProcess() {
  return Process.start('/bin/sleep', ['60']);
}

Future<void> _expectProcessDead(int pid) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (!isProcessAlive(pid)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  fail('Expected process $pid to be dead');
}

Future<void> _killIfAlive(int pid) async {
  if (!isProcessAlive(pid)) {
    return;
  }

  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {
    return;
  }

  await _expectProcessDead(pid);
}
