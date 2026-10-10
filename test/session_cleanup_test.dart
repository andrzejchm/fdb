@TestOn('!windows')
library;

import 'dart:io';

import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/controller_transport.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('replacePreviousSession', () {
    test('stops leftover processes of a dead session and warns once', () async {
      final session = await _seedSession(appAlive: false, controllerResponds: false);

      final progress = <String>[];
      await replacePreviousSession(onProgress: progress.add);

      expect(
          progress.where((line) => line.startsWith('WARNING:')), [startsWith('WARNING: Cleaned up a stale session')]);
      for (final pid in [session.controller, session.flutterTool, session.collector]) {
        await _expectProcessDead(pid);
      }
      _expectRuntimeFilesRemoved();
    });

    test('replaces a live session without a warning', () async {
      final session = await _seedSession(appAlive: true, controllerResponds: true);

      final progress = <String>[];
      await replacePreviousSession(onProgress: progress.add);

      expect(progress, isNot(contains(startsWith('WARNING:'))));
      expect(progress, contains('launch: stopping previous session'));
      await _expectProcessDead(session.controller);
      await _expectProcessDead(session.collector);
      _expectRuntimeFilesRemoved();
      expect(session.commands, isNot(contains(ControllerCommand.kill)));
    });

    test('with stopApp asks the live controller to stop the app first', () async {
      final session = await _seedSession(appAlive: true, controllerResponds: true);

      await replacePreviousSession(stopApp: true);

      expect(session.commands, contains(ControllerCommand.kill));
      await _expectProcessDead(session.controller);
      _expectRuntimeFilesRemoved();
    });

    test('waits for a controller that takes a while to exit on SIGTERM', () async {
      // Stands in for a controller stopping its flutter tool: exits ~1 s
      // after SIGTERM.
      final session = await _seedSession(
        appAlive: true,
        controllerResponds: true,
        controllerCommand: ['sh', '-c', 'trap "sleep 1; exit 0" TERM; while true; do sleep 0.1; done'],
      );
      // Let sh install its trap before the signal arrives.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final progress = <String>[];
      final stopwatch = Stopwatch()..start();
      await replacePreviousSession(onProgress: progress.add);
      stopwatch.stop();

      expect(isProcessAlive(session.controller), isFalse, reason: 'controller must be gone on return');
      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
      expect(progress, contains('launch: waiting for the previous session to exit'));
    });
  });
}

typedef _SessionPids = ({int controller, int flutterTool, int collector, List<ControllerCommand> commands});

/// Seeds a temp session dir whose controller, flutter tool and log collector
/// are `sleep` processes. The app PID is a live `sleep` when [appAlive],
/// otherwise a PID that has already exited. When [controllerResponds], a fake
/// controller answers on the recorded port.
///
/// [controllerCommand] replaces the controller's `sleep` process.
Future<_SessionPids> _seedSession({
  required bool appAlive,
  required bool controllerResponds,
  List<String>? controllerCommand,
}) async {
  final root = await Directory.systemTemp.createTemp('fdb_session_cleanup_');
  initSessionDirFromPath(Directory('${root.path}/.fdb').path);
  ensureSessionDir();

  final processes = [
    controllerCommand == null
        ? await Process.start('sleep', ['60'])
        : await Process.start(controllerCommand.first, controllerCommand.sublist(1)),
    for (var i = 1; i < 4; i++) await Process.start('sleep', ['60'])
  ];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  addTearDown(() async {
    await server.close();
    for (final process in processes) {
      process.kill(ProcessSignal.sigkill);
    }
    await root.delete(recursive: true);
  });

  final app = processes[3];
  if (!appAlive) {
    app.kill(ProcessSignal.sigkill);
    await app.exitCode;
  }
  final commands = <ControllerCommand>[];
  if (controllerResponds) {
    server.listen((socket) async {
      commands.add((await readControllerRequest(socket)).command);
      await writeControllerResponse(socket, ControllerResponse.success({'running': true}));
      await socket.close();
    });
  } else {
    await server.close();
  }

  File(platformFile).writeAsStringSync('macos false');
  File(appPidFile).writeAsStringSync('${app.pid}');
  File(controllerPidFile).writeAsStringSync('${processes[0].pid}');
  File(pidFile).writeAsStringSync('${processes[1].pid}');
  File(logCollectorPidFile).writeAsStringSync('${processes[2].pid}');
  File(controllerPortFile).writeAsStringSync('$port');
  File(controllerTokenFile).writeAsStringSync('token');
  File(vmUriFile).writeAsStringSync('ws://127.0.0.1:1/ws');

  return (
    controller: processes[0].pid,
    flutterTool: processes[1].pid,
    collector: processes[2].pid,
    commands: commands,
  );
}

void _expectRuntimeFilesRemoved() {
  for (final path in [
    pidFile,
    appPidFile,
    controllerPidFile,
    controllerPortFile,
    controllerTokenFile,
    logCollectorPidFile,
    vmUriFile,
  ]) {
    expect(File(path).existsSync(), isFalse, reason: path);
  }
}

Future<void> _expectProcessDead(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (isProcessAlive(pid) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(isProcessAlive(pid), isFalse, reason: 'PID $pid should have exited');
}
