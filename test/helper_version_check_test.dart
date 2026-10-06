import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/helper_version_check.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('helperVersionWarnings', () {
    List<String> warn(RunningHelperVersion running, {String? resolved, String cli = '1.13.0'}) =>
        helperVersionWarnings(running: running, resolved: resolved, cliVersion: cli);

    test('silent when running, resolved and CLI agree', () {
      expect(warn(const HelperVersionReported('1.13.0'), resolved: '1.13.0'), isEmpty);
      expect(warn(const HelperVersionReported('1.13.2'), resolved: '1.13.2', cli: '1.13.0'), isEmpty);
    });

    test('silent when the version could not be queried', () {
      expect(warn(const HelperVersionUnavailable(), resolved: '1.12.0', cli: '2.0.0'), isEmpty);
    });

    test('warns when the running helper differs from the resolved one', () {
      expect(warn(const HelperVersionReported('1.13.0'), resolved: '1.13.1'), [
        'WARNING: The app runs fdb_helper 1.13.0 but the project resolves 1.13.1. '
            'Hot reload/restart does not reload it; stop and rebuild the app (fdb kill, then fdb launch).',
      ]);
    });

    test('warns when the running helper is older than the CLI major.minor', () {
      expect(warn(const HelperVersionReported('1.13.0'), resolved: '1.13.0', cli: '1.14.0'), [
        'WARNING: fdb 1.14.0 with fdb_helper 1.13.0; update fdb_helper to ^1.14.0 and rebuild.',
      ]);
    });

    test('unknown resolved version still compares against the CLI', () {
      expect(warn(const HelperVersionReported('1.13.0'), cli: '2.0.0'), hasLength(1));
    });

    test('unreported version counts as older only once the CLI reports versions', () {
      expect(warn(const HelperVersionNotReported(), resolved: '1.12.0', cli: '1.12.0'), isEmpty);
      expect(warn(const HelperVersionNotReported(), resolved: '1.12.0', cli: '1.13.0'), [
        'WARNING: fdb 1.13.0 with an fdb_helper that does not report its version (older than 1.13); '
            'update fdb_helper to ^1.13.0 and rebuild.',
      ]);
    });

    test('unreported version with a newer resolved helper means a stale build', () {
      expect(warn(const HelperVersionNotReported(), resolved: '1.13.0', cli: '1.12.0'), [
        'WARNING: The app runs an fdb_helper that does not report its version (older than 1.13) but the project '
            'resolves 1.13.0. Hot reload/restart does not reload it; stop and rebuild the app (fdb kill, then fdb launch).',
      ]);
    });

    test('reads the version from an extension payload', () {
      expect(RunningHelperVersion.fromPayload({'fdbHelperVersion': '1.13.0'}), isA<HelperVersionReported>());
      expect(RunningHelperVersion.fromPayload({'lifecycleState': 'resumed'}), isA<HelperVersionNotReported>());
    });
  });

  group('readResolvedHelperVersion', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('fdb_helper_version_'));
    tearDown(() => project.deleteSync(recursive: true));

    void writeConfig(String rootUri) {
      File('${project.path}/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'meta', 'rootUri': 'file:///nowhere/meta-1.0.0', 'packageUri': 'lib/'},
            {'name': 'fdb_helper', 'rootUri': rootUri, 'packageUri': 'lib/'},
          ],
        }));
    }

    test('reads a relative path dependency pubspec', () {
      File('${project.path}/helper/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: fdb_helper\nversion: 1.13.0 # comment\n');
      writeConfig('../helper');

      expect(readResolvedHelperVersion(project.path), '1.13.0');
    });

    test('falls back to the hosted cache directory name', () {
      writeConfig('file:///pub-cache/hosted/pub.dev/fdb_helper-1.12.3');

      expect(readResolvedHelperVersion(project.path), '1.12.3');
    });

    test('returns null without package_config.json or fdb_helper entry', () {
      expect(readResolvedHelperVersion(project.path), isNull);

      File('${project.path}/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"configVersion": 2, "packages": []}');
      expect(readResolvedHelperVersion(project.path), isNull);
    });
  });

  test('readProjectPath prefers the stored path and falls back to the session dir parent', () {
    final root = Directory.systemTemp.createTempSync('fdb_project_path_');
    addTearDown(() => root.deleteSync(recursive: true));
    initSessionDirFromPath('${root.path}/.fdb');
    ensureSessionDir();

    expect(readProjectPath(), Directory(root.path).absolute.path);

    writeProjectPath('${root.path}/elsewhere/.');
    expect(readProjectPath(), Directory('${root.path}/elsewhere').absolute.path);
  });
}
