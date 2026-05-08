import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/doctor/doctor.dart';
import 'package:fdb/core/commands/kill/kill.dart';
import 'package:fdb/core/commands/reload/reload.dart';
import 'package:fdb/core/commands/restart/restart.dart';
import 'package:fdb/core/commands/status/status.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_client.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/controller_transport.dart';
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

    test('soft-fails to not running when stale dead app PID remains on disk', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());

      await _killIfAlive(appProcess.pid);

      final result = await getStatus(());

      expect(result.running, isFalse);
      expect(result.pid, isNull);
      expect(result.vmServiceUri, isNull);
    });

    test('ignores stale dead PID reported by controller when VM service is reachable', () async {
      final root = await _createTempSessionRoot();
      final staleAppProcess = await _startSleepProcess();
      final vmServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final controllerServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = 'status-token';
      final vmUri = 'ws://127.0.0.1:${vmServer.port}/ws';

      vmServer.transform(WebSocketTransformer()).listen((socket) => socket.close());

      addTearDown(() async {
        await controllerServer.close();
        await vmServer.close(force: true);
        await _killIfAlive(staleAppProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(controllerPortFile).writeAsStringSync(controllerServer.port.toString());
      File(controllerTokenFile).writeAsStringSync(token);

      await _killIfAlive(staleAppProcess.pid);

      controllerServer.listen((socket) async {
        await readControllerRequest(socket);
        await writeControllerResponse(
          socket,
          ControllerResponse.success({
            'running': true,
            'pid': staleAppProcess.pid,
            'vmServiceUri': vmUri,
          }),
        );
        await socket.close();
      });

      final result = await getStatus(());

      expect(result.running, isTrue);
      expect(result.pid, isNull);
      expect(result.vmServiceUri, vmUri);
    });
  });

  group('controller client', () {
    test('re-checks dead app state after controller socket connect failure', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(controllerPortFile).writeAsStringSync('1');
      File(controllerTokenFile).writeAsStringSync('test-token');

      await _killIfAlive(appProcess.pid);

      expect(
        () => sendControllerCommand(ControllerCommand.status),
        throwsA(isA<AppDiedException>()),
      );
    });

    test('maps controller disconnect-before-response to controller unavailable', () async {
      final root = await _createTempSessionRoot();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = 'disconnect-token';
      addTearDown(() async {
        await server.close();
        await root.delete(recursive: true);
      });

      File(controllerPortFile).writeAsStringSync(server.port.toString());
      File(controllerTokenFile).writeAsStringSync(token);

      server.listen((socket) async {
        await readControllerRequest(socket);
        await socket.close();
      });

      expect(
        () => sendControllerCommand(ControllerCommand.status),
        throwsA(isA<ControllerUnavailable>()),
      );
    });

    test('maps controller response timeout to controller unavailable', () async {
      final root = await _createTempSessionRoot();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
        await root.delete(recursive: true);
      });

      File(controllerPortFile).writeAsStringSync(server.port.toString());
      File(controllerTokenFile).writeAsStringSync('timeout-token');

      server.listen(sockets.add);

      expect(
        () => sendControllerCommand(
          ControllerCommand.status,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<ControllerUnavailable>()),
      );
    });
  });

  group('reload', () {
    test('returns process-dead result when app died during controller request', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(controllerPortFile).writeAsStringSync('1');
      File(controllerTokenFile).writeAsStringSync('test-token');

      await _killIfAlive(appProcess.pid);

      final result = await reloadApp(());

      expect(result, isA<ReloadProcessDead>());
      expect((result as ReloadProcessDead).pid, appProcess.pid);
    });
  });

  group('restart', () {
    test('returns process-dead result when app died during controller request', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      addTearDown(() async {
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(controllerPortFile).writeAsStringSync('1');
      File(controllerTokenFile).writeAsStringSync('test-token');

      await _killIfAlive(appProcess.pid);

      final result = await restartApp(());

      expect(result, isA<RestartProcessDead>());
      expect((result as RestartProcessDead).pid, appProcess.pid);
    });
  });

  group('doctor', () {
    test('completes all five checks when fdb_helper check sees app died', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      final vmServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      vmServer.transform(WebSocketTransformer()).listen((socket) => socket.close());
      final controllerServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = 'doctor-token';
      final vmUri = 'ws://127.0.0.1:${vmServer.port}/ws';

      addTearDown(() async {
        await controllerServer.close();
        await vmServer.close(force: true);
        await _killIfAlive(appProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(deviceFile).writeAsStringSync('macos');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(vmUriFile).writeAsStringSync(vmUri);
      File(controllerPortFile).writeAsStringSync(controllerServer.port.toString());
      File(controllerTokenFile).writeAsStringSync(token);

      controllerServer.listen((socket) async {
        final request = await readControllerRequest(socket);
        switch (request.command) {
          case ControllerCommand.status:
            await writeControllerResponse(
              socket,
              ControllerResponse.success({
                'running': true,
                'pid': appProcess.pid,
                'vmServiceUri': vmUri,
              }),
            );
            break;
          case ControllerCommand.findAllIsolateIds:
            await writeControllerResponse(
              socket,
              ControllerResponse.success({
                'isolates': ['isolates/1']
              }),
            );
            break;
          case ControllerCommand.checkFdbHelper:
            await writeControllerResponse(
              socket,
              ControllerResponse.appDied(logLines: const ['last log line']),
            );
            break;
          default:
            await writeControllerResponse(socket, ControllerResponse.failure('Unexpected command'));
            break;
        }
        await socket.close();
      });

      final result = await runDoctor([]);

      expect(result.checks, hasLength(5));
      expect(result.failedCount, greaterThan(0));
      expect(result.checks[0].name, 'app_running');
      expect(result.checks[1].name, 'vm_service');
      expect(result.checks[1].status.name, 'pass');
      expect(result.checks[2].name, 'fdb_helper');
      expect(result.checks[2].status.name, 'fail');
      expect(result.checks[3].name, 'platform_tools');
      expect(result.checks[4].name, 'device');
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

    test('waits for visible session processes after controller kill succeeds', () async {
      final root = await _createTempSessionRoot();
      final appProcess = await _startSleepProcess();
      final toolProcess = await _startSleepProcess();
      final controllerProcess = await _startSleepProcess();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close();
        await _killIfAlive(appProcess.pid);
        await _killIfAlive(toolProcess.pid);
        await _killIfAlive(controllerProcess.pid);
        await root.delete(recursive: true);
      });

      File(platformFile).writeAsStringSync('macos false');
      File(appPidFile).writeAsStringSync(appProcess.pid.toString());
      File(pidFile).writeAsStringSync(toolProcess.pid.toString());
      File(controllerPidFile).writeAsStringSync(controllerProcess.pid.toString());
      File(controllerPortFile).writeAsStringSync(server.port.toString());
      File(controllerTokenFile).writeAsStringSync('test-token');

      server.listen((socket) async {
        await readControllerRequest(socket);
        await writeControllerResponse(
          socket,
          ControllerResponse.success({'stopped': true}),
        );
        await socket.close();
      });

      final result = await killApp(());

      expect(result, isA<KillSuccess>());
      await _expectProcessDead(appProcess.pid);
      await _expectProcessDead(toolProcess.pid);
      await _expectProcessDead(controllerProcess.pid);
      expect(File(appPidFile).existsSync(), isFalse);
      expect(File(pidFile).existsSync(), isFalse);
      expect(File(controllerPidFile).existsSync(), isFalse);
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
