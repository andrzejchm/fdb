@TestOn('!windows')
library;

import 'dart:io';

import 'package:fdb/core/process_utils.dart';
import 'package:test/test.dart';

/// Starts the real controller (`bin/controller.dart`) with a fake `flutter`
/// shell script, sends it SIGTERM the way `fdb launch` / `fdb attach` do when
/// they replace a live session, and checks that the fake flutter tool does not
/// outlive it and that the app is not stopped (that is the `kill` command's
/// job).
void main() {
  late Directory root;
  late String marker;
  late String flutterPidPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fdb_controller_sigterm_');
    marker = '${root.path}/marker.txt';
    flutterPidPath = '${root.path}/flutter.pid';
  });

  tearDown(() async {
    final pidFile = File(flutterPidPath);
    if (pidFile.existsSync()) {
      final pid = int.tryParse(pidFile.readAsStringSync().trim());
      if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
    }
    await root.delete(recursive: true);
  });

  for (final mode in ['run', 'attach']) {
    test('$mode mode: SIGTERM stops the flutter tool without stopping the app', () async {
      final flutterPid =
          await _runControllerAndSigterm(root, mode: mode, flutterPidPath: flutterPidPath, marker: marker);

      await _expectProcessDead(flutterPid);
      final log = File(marker).existsSync() ? File(marker).readAsStringSync() : '';
      expect(log, isNot(contains('app.stop')));
    });
  }
}

/// Fake `flutter run|attach --machine`: reports `app.start`, answers
/// `app.stop` with success and exits, and on SIGTERM records it and exits.
String _fakeFlutterScript({required String flutterPidPath, required String marker}) => '''
#!/bin/sh
echo \$\$ > '$flutterPidPath'
trap 'echo SIGTERM >> "$marker"; exit 0' TERM
echo '[{"event":"app.start","params":{"appId":"fake-app"}}]'
while true; do
  if read -r line; then
    case "\$line" in
      *app.stop*)
        echo "\$line" >> '$marker'
        id=\$(echo "\$line" | sed 's/.*"id":\\([0-9]*\\).*/\\1/')
        echo "[{\\"id\\":\$id,\\"result\\":true}]"
        exit 0
        ;;
    esac
  else
    sleep 0.1
  fi
done
''';

Future<int> _runControllerAndSigterm(
  Directory root, {
  required String mode,
  required String flutterPidPath,
  required String marker,
}) async {
  final fakeFlutter = File('${root.path}/flutter');
  fakeFlutter.writeAsStringSync(_fakeFlutterScript(flutterPidPath: flutterPidPath, marker: marker));
  await Process.run('chmod', ['+x', fakeFlutter.path]);

  final sessionDir = '${root.path}/.fdb';
  final controller = await Process.start(Platform.resolvedExecutable, [
    'bin/controller.dart',
    '--mode',
    mode,
    '--session-dir',
    sessionDir,
    '--project',
    root.path,
    '--device',
    'fake-device',
    '--flutter',
    fakeFlutter.path,
  ]);
  addTearDown(() => controller.kill(ProcessSignal.sigkill));

  // Wait for the fake flutter to start and for the controller to have parsed
  // its `app.start` event (the controller log gets created at startup; give
  // the event a moment to be handled after the PID file shows up).
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!File(flutterPidPath).existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(File(flutterPidPath).existsSync(), isTrue, reason: 'fake flutter never started');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final flutterPid = int.parse(File(flutterPidPath).readAsStringSync().trim());

  controller.kill(ProcessSignal.sigterm);
  final exitCode = await controller.exitCode.timeout(const Duration(seconds: 20));
  expect(exitCode, 143);
  return flutterPid;
}

Future<void> _expectProcessDead(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (isProcessAlive(pid) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(isProcessAlive(pid), isFalse, reason: 'fake flutter (PID $pid) outlived the controller');
}
