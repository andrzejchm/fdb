@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

const _udidA = 'AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA';
const _udidB = 'BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB';

/// End-to-end checks that the `fdb simulator` CLI targets the session's
/// simulator when two simulators are booted. Runs `bin/fdb.dart` as a
/// subprocess with a fake `xcrun` first on PATH; no real simulator is touched.
void main() {
  test('simulator status-bar override targets the --session-dir device when two simulators are booted', () async {
    final env = await _E2eEnv.create(sessionDevice: _udidB);

    final result = await env
        .runFdb(['--session-dir', env.sessionDir.path, 'simulator', 'status-bar', 'override', '--time', '9:41']);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stdout, contains('STATUS_BAR_OVERRIDDEN'));
    expect(env.mutatingCalls(), ['status_bar $_udidB override --time 9:41']);
  });

  test('session device A is targeted when device.txt holds A', () async {
    final env = await _E2eEnv.create(sessionDevice: _udidA);

    final result = await env.runFdb(['--session-dir', env.sessionDir.path, 'simulator', 'status-bar', 'clear']);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(env.mutatingCalls(), ['status_bar $_udidA clear']);
  });

  test('without a session and with two booted simulators it fails listing both UDIDs and --device', () async {
    final env = await _E2eEnv.create();

    final result = await env.runFdb(['simulator', 'status-bar', 'override', '--time', '9:41']);

    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    final stderr = result.stderr;
    expect(stderr, contains('ERROR:'));
    expect(stderr, contains(_udidA));
    expect(stderr, contains(_udidB));
    expect(stderr, contains('--device'));
    expect(result.stdout, isNot(contains('STATUS_BAR_OVERRIDDEN')));
    expect(env.mutatingCalls(), isEmpty);
  });

  test('--device after the subcommand beats the session device', () async {
    final env = await _E2eEnv.create(sessionDevice: _udidB);

    final result = await env.runFdb([
      '--session-dir',
      env.sessionDir.path,
      'simulator',
      'status-bar',
      'override',
      '--device',
      _udidA,
      '--time',
      '9:41',
    ]);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stdout, contains('STATUS_BAR_OVERRIDDEN'));
    expect(env.mutatingCalls(), ['status_bar $_udidA override --time 9:41']);
  });

  test('--device resolves a target even without any session', () async {
    final env = await _E2eEnv.create();

    final result = await env.runFdb(['simulator', 'status-bar', 'override', '--device', _udidA, '--time', '9:41']);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(env.mutatingCalls(), ['status_bar $_udidA override --time 9:41']);
  });
}

/// Upper bound for one `bin/fdb.dart` subprocess; a cold `dart` compile of the
/// CLI can take a while on a busy machine.
const _fdbRunTimeout = Duration(seconds: 120);

/// Locates the fdb package root (the directory holding `bin/fdb.dart`).
///
/// Prefers resolving `package:fdb` through the active package config, so it
/// does not depend on the directory `dart test` was started from; falls back
/// to walking up from the current directory and the test script.
Future<Directory> _packageRoot() async {
  bool isRoot(Directory dir) =>
      File('${dir.path}/bin/fdb.dart').existsSync() && File('${dir.path}/pubspec.yaml').existsSync();

  final libUri = await Isolate.resolvePackageUri(Uri.parse('package:fdb/constants.dart'));
  if (libUri != null && libUri.scheme == 'file') {
    final root = File.fromUri(libUri).parent.parent;
    if (isRoot(root)) return root;
  }

  final starts = <Directory>[Directory.current];
  if (Platform.script.scheme == 'file') starts.add(File.fromUri(Platform.script).parent);
  for (final start in starts) {
    var dir = start.absolute;
    while (true) {
      if (isRoot(dir)) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  throw StateError('Could not locate the fdb package root (bin/fdb.dart) from ${Directory.current.path}');
}

class _E2eEnv {
  _E2eEnv._(this.sessionDir, this._workDir, this._binDir, this._callLog, this._fdbScript);

  final Directory sessionDir;
  final Directory _workDir;
  final Directory _binDir;
  final File _callLog;
  final String _fdbScript;

  /// Subprocesses started by [runFdb] that have not exited yet; the teardown
  /// kills and awaits them before the temp directory is removed.
  final List<({Process process, Future<int> exit})> _running = [];

  static Future<_E2eEnv> create({String? sessionDevice}) async {
    final fdbScript = '${(await _packageRoot()).path}/bin/fdb.dart';
    final root = await Directory.systemTemp.createTemp('fdb_sim_e2e_test_');

    final sessionDir = Directory('${root.path}/project/.fdb')..createSync(recursive: true);
    if (sessionDevice != null) File('${sessionDir.path}/device.txt').writeAsStringSync(sessionDevice);

    // A different, empty working directory: nothing to walk up to.
    final workDir = Directory('${root.path}/elsewhere')..createSync(recursive: true);
    final binDir = Directory('${root.path}/bin')..createSync(recursive: true);

    final listFile = File('${root.path}/devices.json')
      ..writeAsStringSync(
        jsonEncode({
          'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-17-5': [
              {'udid': _udidA, 'name': 'Simulator A', 'state': 'Booted'},
            ],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-0': [
              {'udid': _udidB, 'name': 'Simulator B', 'state': 'Booted'},
            ],
          },
        }),
      );
    final callLog = File('${root.path}/calls.log')..createSync();

    final xcrun = File('${binDir.path}/xcrun')..writeAsStringSync('''#!/bin/sh
shift
echo "\$*" >> "${callLog.path}"
if [ "\$1" = "list" ]; then
  cat "${listFile.path}"
fi
exit 0
''');
    await Process.run('chmod', ['+x', xcrun.path]);

    final env = _E2eEnv._(sessionDir, workDir, binDir, callLog, fdbScript);
    addTearDown(() async {
      // Never delete the fake xcrun / session files under a live child.
      await env._killRunning();
      if (root.existsSync()) await root.delete(recursive: true);
    });
    return env;
  }

  Future<void> _killRunning() async {
    for (final entry in _running) {
      entry.process.kill(ProcessSignal.sigkill);
      await entry.exit.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    }
    _running.clear();
  }

  /// Runs `bin/fdb.dart` with the fake `xcrun` first on PATH. On timeout the
  /// child is killed and reaped before a [TimeoutException] is thrown.
  Future<({int exitCode, String stdout, String stderr})> runFdb(List<String> args) async {
    final path = Platform.environment['PATH'] ?? '';
    final process = await Process.start(
      Platform.resolvedExecutable,
      [_fdbScript, ...args],
      workingDirectory: _workDir.path,
      environment: {'PATH': '${_binDir.path}:$path'},
    );
    final exit = process.exitCode;
    _running.add((process: process, exit: exit));

    final stdoutText = utf8.decodeStream(process.stdout);
    final stderrText = utf8.decodeStream(process.stderr);
    try {
      final exitCode = await exit.timeout(_fdbRunTimeout);
      return (exitCode: exitCode, stdout: await stdoutText, stderr: await stderrText);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await exit;
      throw TimeoutException('fdb ${args.join(' ')} did not finish', _fdbRunTimeout);
    }
  }

  /// Recorded simctl invocations other than the device listing.
  List<String> mutatingCalls() =>
      _callLog.readAsLinesSync().where((line) => line.isNotEmpty && !line.startsWith('list ')).toList();
}
