import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('launch helpers', () {
    test('writePlatformInfoForLaunch soft-fails on timeout', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final label = await writePlatformInfoForLaunch(
        'device-id',
        'flutter',
        processRunner: (_, __) => throw TimeoutException('slow flutter devices'),
      );

      expect(label, isNull);
      expect(File(platformFile).existsSync(), isFalse);
    });

    test('cleanupLaunchSessionFiles removes stale app id file', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      File(appIdFile).writeAsStringSync('com.example.stale');
      File(platformFile).writeAsStringSync('macos false');

      cleanupLaunchSessionFiles();

      expect(File(appIdFile).existsSync(), isFalse);
      expect(File(platformFile).existsSync(), isFalse);
    });

    test('readLaunchPid ignores controller pid file fallback', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      File(controllerPidFile).writeAsStringSync('9999');

      expect(readLaunchPid(), isEmpty);
    });

    test('readLaunchPid prefers app pid over flutter-tools pid', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      File(pidFile).writeAsStringSync('2222');
      File(appPidFile).writeAsStringSync('1111');

      expect(readLaunchPid(), '1111');
    });

    test('initLaunchSession uses explicit session dir instead of project .fdb', () async {
      final root = await Directory.systemTemp.createTemp('fdb_launch_session_');
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final project = Directory('${root.path}/project')..createSync(recursive: true);
      final explicitSession = Directory('${root.path}/custom-session');

      initLaunchSession(project: project.path, sessionDir: explicitSession.path);

      expect(sessionDirPath, explicitSession.absolute.path);
    });

    test('initLaunchSession falls back to project .fdb without explicit session dir', () async {
      final root = await Directory.systemTemp.createTemp('fdb_launch_session_');
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final project = Directory('${root.path}/project')..createSync(recursive: true);

      initLaunchSession(project: project.path);

      expect(sessionDirPath, '${project.absolute.path}/.fdb');
    });

    test('writeAppIdFromProjectForLaunch skips ambiguous app ids when platform hint is unavailable', () async {
      final root = await Directory.systemTemp.createTemp('fdb_launch_project_');
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final session = Directory('${root.path}/session')..createSync(recursive: true);
      initSessionDirFromPath(session.path);

      final project = Directory('${root.path}/project')..createSync(recursive: true);
      Directory('${project.path}/android/app').createSync(recursive: true);
      Directory('${project.path}/ios/Runner').createSync(recursive: true);
      Directory('${project.path}/ios/Runner.xcodeproj').createSync(recursive: true);

      File('${project.path}/android/app/build.gradle').writeAsStringSync('applicationId "com.example.android"');
      File('${project.path}/ios/Runner/Info.plist').writeAsStringSync('''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      File('${project.path}/ios/Runner.xcodeproj/project.pbxproj').writeAsStringSync(
        'PRODUCT_BUNDLE_IDENTIFIER = dev.example.ios;',
      );

      writeAppIdFromProjectForLaunch(project.path);

      expect(File(appIdFile).existsSync(), isFalse);
    });

    test('writeAppIdFromProjectForLaunch keeps Android app id when it is the only candidate', () async {
      final root = await Directory.systemTemp.createTemp('fdb_launch_project_');
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final session = Directory('${root.path}/session')..createSync(recursive: true);
      initSessionDirFromPath(session.path);

      final project = Directory('${root.path}/project')..createSync(recursive: true);
      Directory('${project.path}/android/app').createSync(recursive: true);

      File('${project.path}/android/app/build.gradle').writeAsStringSync('applicationId "com.example.android"');

      writeAppIdFromProjectForLaunch(project.path);

      expect(File(appIdFile).readAsStringSync(), 'com.example.android');
    });
  });
}

Future<Directory> _createTempSessionRoot() async {
  final root = await Directory.systemTemp.createTemp('fdb_launch_test_');
  final session = Directory('${root.path}/.fdb');
  session.createSync(recursive: true);
  initSessionDirFromPath(session.path);
  return root;
}
