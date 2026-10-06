import 'dart:io';

import 'package:fdb/cli/binstub_sdk_check_cli.dart';
import 'package:fdb/core/binstub_sdk_check.dart';
import 'package:test/test.dart';

/// Pub's launcher for `fdb`, hardcoding the snapshot for [version].
String _pubLauncher(String pubCache, String version, {String package = 'fdb'}) {
  final snapshot = '$pubCache/global_packages/$package/bin/fdb.dart-$version.snapshot';
  return '''
#!/usr/bin/env sh
# This file was created by pub v$version.
# Package: $package
# Version: 1.12.0
# Executable: fdb
# Script: fdb
if [ -f $snapshot ]; then
  dart "$snapshot" "\$@"
  exit_code=\$?
  if [ \$exit_code != 253 ]; then
    exit \$exit_code
  fi
fi
dart pub global run $package:fdb "\$@"
''';
}

void main() {
  late Directory tmp;
  late String pubCache;
  late File launcher;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fdb_binstub_test_');
    pubCache = '${tmp.resolveSymbolicLinksSync()}/pub cache';
    launcher = File('$pubCache/bin/fdb')..createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  BinstubSdkMismatch? check(String running, {String? script, bool isWindows = false}) => checkBinstubSdk((
        pubCacheDir: pubCache,
        runningDartVersion: running,
        scriptPath: script ?? '$pubCache/global_packages/fdb/bin/fdb.dart-$running.snapshot',
        isWindows: isWindows,
      ));

  test('mismatch → one warning line, launcher unchanged', () {
    final content = _pubLauncher(pubCache, '3.13.4');
    launcher.writeAsStringSync(content);

    final mismatch = check('3.12.2');

    expect(mismatch, (activated: '3.13.4', running: '3.12.2'));
    expect(
      formatBinstubSdkMismatch(mismatch),
      "WARNING: fdb was activated with Dart 3.13.4 but 'dart' on PATH is 3.12.2; "
      'that causes the "Can\'t load Kernel binary" line above. '
      "Fix: run 'dart pub global activate fdb' with the Dart you use.",
    );
    expect(launcher.readAsStringSync(), content);
  });

  test('silent when there is nothing to report', () {
    final mismatched = _pubLauncher(pubCache, '3.13.4');
    final cases = <String, (String?, BinstubSdkMismatch? Function())>{
      'matching SDK': (_pubLauncher(pubCache, '3.12.2'), () => check('3.12.2')),
      'no launcher': (null, () => check('3.12.2')),
      'non-fdb launcher': (_pubLauncher(pubCache, '3.13.4', package: 'other'), () => check('3.12.2')),
      'runtime launcher': (
        '#!/usr/bin/env sh\n# Package: fdb\n$launcherMarker\n'
            'snapshot="$pubCache/global_packages/fdb/bin/fdb.dart-\$sdk_version.snapshot"\n',
        () => check('3.12.2'),
      ),
      'runtime launcher with a stale snapshot path': (
        _pubLauncher(pubCache, '3.13.4').replaceFirst('# Script: fdb', '# Script: fdb\n$launcherMarker'),
        () => check('3.12.2'),
      ),
      'Windows': (mismatched, () => check('3.12.2', isWindows: true)),
      'path activation': (
        mismatched,
        () => check('3.12.2', script: '/repo/.dart_tool/pub/bin/fdb/fdb.dart-3.12.2.snapshot')
      ),
      'other global package': (
        mismatched,
        () => check('3.12.2', script: '$pubCache/global_packages/fdbx/bin/fdb.dart-3.12.2.snapshot'),
      ),
    };
    for (final MapEntry(key: name, value: (content, run)) in cases.entries) {
      if (content == null) {
        if (launcher.existsSync()) launcher.deleteSync();
      } else {
        launcher.writeAsStringSync(content);
      }
      expect(run(), isNull, reason: name);
      if (content != null) expect(launcher.readAsStringSync(), content, reason: name);
    }
    expect(formatBinstubSdkMismatch(null), isNull);
  });
}
