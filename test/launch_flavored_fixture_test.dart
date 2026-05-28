import 'dart:io';

import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

/// End-to-end coverage for `writeAppIdFromProjectForLaunch` against a
/// realistic-but-trimmed Flutter project tree under
/// `test/fixtures/flavored_project/`.
///
/// The inline tests in `launch_test.dart` validate the parser against
/// synthetic strings; this file validates that the same parser produces
/// the right `.fdb/app_id.txt` when pointed at the kinds of files a
/// flavored Flutter project actually emits.
void main() {
  const fixturePath = 'test/fixtures/flavored_project';

  group('flavored fixture project', () {
    setUp(() {
      // Sanity check: fixture must exist where every test expects it.
      expect(
        Directory(fixturePath).existsSync(),
        isTrue,
        reason: 'Fixture missing at $fixturePath',
      );
    });

    group('iOS', () {
      test('staging resolves via ios/Flutter/Debug-staging.xcconfig', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('ios', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'staging');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.staging');
      });

      test('prod resolves via pbxproj Debug-prod build config', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('ios', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'prod');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.prod');
      });

      test('no flavor falls back to the shortest pbxproj bundle id', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('ios', false);

        writeAppIdFromProjectForLaunch(fixturePath);

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored');
      });
    });

    group('macOS', () {
      test('staging resolves via macos/Flutter/Debug-staging.xcconfig', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('macos', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'staging');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.macos.staging');
      });

      test('canary resolves via macos/Runner/Configs/Debug-canary.xcconfig', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('macos', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'canary');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.macos.canary');
      });

      test('internal resolves via pbxproj Debug-internal build config', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('macos', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'internal');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.macos.internal');
      });

      test('no flavor falls back to AppInfo.xcconfig', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('macos', false);

        writeAppIdFromProjectForLaunch(fixturePath);

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored.macos');
      });
    });

    group('Android', () {
      test('staging composes explicit flavor applicationId + flavor + debug suffixes', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('android-arm64', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'staging');

        expect(
          File(appIdFile).readAsStringSync(),
          'com.example.flavored.staging.s.debug',
        );
      });

      test('prod composes defaultConfig applicationId + flavor suffix + debug suffix', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('android-arm64', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'prod');

        expect(
          File(appIdFile).readAsStringSync(),
          'com.example.flavored.p.debug',
        );
      });

      test('unknown flavor falls back to defaultConfig applicationId without suffixes', () async {
        final session = await _newSession();
        addTearDown(() async => session.delete(recursive: true));
        writePlatformInfo('android-arm64', false);

        writeAppIdFromProjectForLaunch(fixturePath, flavor: 'nosuchflavor');

        expect(File(appIdFile).readAsStringSync(), 'com.example.flavored');
      });
    });
  });
}

Future<Directory> _newSession() async {
  final root = await Directory.systemTemp.createTemp('fdb_flavor_fixture_');
  final session = Directory('${root.path}/.fdb')..createSync(recursive: true);
  initSessionDirFromPath(session.path);
  return root;
}
