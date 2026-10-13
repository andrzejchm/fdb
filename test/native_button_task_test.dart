import 'dart:io';

import 'package:test/test.dart';

// Exercise the actual Taskfile with fake host tools. Never contact a device.
void main() {
  group('native-button integration task choices', () {
    late Directory temp;
    late File calls;
    late Map<String, String> environment;
    final taskfile = File('Taskfile.yml').absolute.path;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fdb-button-task-');
      await Directory('${temp.path}/.fdb').create();
      await File('${temp.path}/.fdb/platform.txt').writeAsString('android-arm64 false');
      await File('${temp.path}/.fdb/device.txt').writeAsString('exact-serial');
      await File('${temp.path}/.fdb/app_id.txt').writeAsString('test.app');
      calls = File('${temp.path}/calls');
      for (final entry in {'fdb': _fdb, 'adb': _adb}.entries) {
        final file = File('${temp.path}/${entry.key}');
        await file.writeAsString(entry.value);
        final chmod = await Process.run('chmod', ['+x', file.path]);
        expect(chmod.exitCode, 0);
      }
      environment = {
        'PATH': '${temp.path}:${Platform.environment['PATH']}',
        'CALLS': calls.path,
        'POWER_STATE': '${temp.path}/power',
      };
    });
    tearDown(() => temp.delete(recursive: true));

    Future<ProcessResult> run(String task) => Process.run(
          'task',
          ['--taskfile', taskfile, task, 'TEST_APP=${temp.path}', 'FDB=${temp.path}/fdb'],
          environment: environment,
        );

    test('default Home test on unlocked secure Android never presses power or dismisses keyguard', () async {
      final result = await run('test:native-button');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('SKIP: native-button lock sleep/wake'));
      expect(result.stdout, contains('lock tested=false'));
      final log = await calls.readAsString();
      expect(log, contains('BUTTON=home'));
      expect(log, isNot(contains('BUTTON=lock')));
      expect(log, isNot(contains('dismiss-keyguard')));
      expect(log, contains('adb -s exact-serial shell monkey -p test.app'));
    });

    test('explicit lock test verifies sleep/wake then reports secure restoration blocker', () async {
      final result = await run('test:native-button-lock');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keyguard still showing'));
      expect(result.stderr, contains('did not restore the app'));
      final log = await calls.readAsString();
      expect('BUTTON=lock'.allMatches(log).length, 2);
      expect(log, isNot(contains('shell monkey')));
      expect(result.stdout, isNot(contains('PASS: fdb native-button')));
    });

    test('uncertain first lock delivery gets no cleanup power retry', () async {
      environment['FAIL_LOCK'] = 'true';
      final result = await run('test:native-button-lock');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('No automatic button retry'));
      expect('BUTTON=lock'.allMatches(await calls.readAsString()).length, 1);
    });

    test('sleeping device fails preflight before Home or power injection', () async {
      environment['INITIAL_ASLEEP'] = 'true';
      final result = await run('test:native-button');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('wake Android exact-serial'));
      expect(await calls.readAsString(), isNot(contains('BUTTON=')));
    });

    test('cached widgets do not count as foreground app restoration', () async {
      for (final warning in [
        'WARNING: App is not in the foreground (lifecycle=paused)',
        'WARNING: App is inactive (lifecycle=inactive)',
        'WARNING: App is not responding to the VM service',
      ]) {
        environment['RESTORE_WARNING'] = warning;
        final result = await run('test:native-button');
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('did not confirm usable foreground Flutter'));
        expect(result.stderr, contains('did not restore the app'));
        expect(result.stdout, isNot(contains('PASS: fdb native-button')));
      }
    });
  }, skip: Platform.isWindows ? 'Taskfile integration uses POSIX shell' : false);
}

const _fdb = r'''#!/bin/sh
set -eu
if [ "${1:-}" = --session-dir ]; then shift 2; fi
case "$1" in
  native-button)
    shift
    if [ "$#" -ne 1 ] || { [ "$1" != home ] && [ "$1" != lock ]; }; then
      echo 'ERROR: Expected one button: home or lock.' >&2
      exit 1
    fi
    echo "BUTTON=$1" >> "$CALLS"
    if [ "$1" = lock ]; then
      if [ "${FAIL_LOCK:-}" = true ]; then exit 1; fi
      if [ ! -f "$POWER_STATE" ]; then echo Asleep > "$POWER_STATE"; else echo Awake > "$POWER_STATE"; fi
    fi
    echo "NATIVE_BUTTON=$1 PLATFORM=android" ;;
  wait) echo FOUND ;;
  describe)
    if [ -n "${RESTORE_WARNING:-}" ]; then echo "$RESTORE_WARNING"; fi
    echo 'SCREEN=home' ;;
  *) exit 1 ;;
esac
''';

const _adb = r'''#!/bin/sh
set -eu
echo "adb $*" >> "$CALLS"
[ "$1" = -s ] && [ "$2" = exact-serial ] || exit 1
shift 2
case "$*" in
  'shell dumpsys window policy')
    if [ -f "$POWER_STATE" ]; then echo 'secure=true showing=true'; else echo 'secure=true showing=false'; fi ;;
  'shell dumpsys power')
    if [ -f "$POWER_STATE" ]; then STATE=$(cat "$POWER_STATE");
    elif [ "${INITIAL_ASLEEP:-}" = true ]; then STATE=Asleep; else STATE=Awake; fi
    echo "mWakefulness=$STATE" ;;
  'exec-out screencap -p') echo image ;;
  'shell wm dismiss-keyguard'|'shell monkey -p test.app -c android.intent.category.LAUNCHER 1') : ;;
  *) exit 1 ;;
esac
''';
