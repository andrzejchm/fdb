import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/core/process_utils.dart';
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

    test('buildLaunchControllerArgs keeps repeated define flags as separate arguments', () {
      expect(
        buildLaunchControllerArgs(
          ['controller.dart'],
          sessionDir: '/tmp/.fdb',
          project: '/tmp/project',
          device: 'macos',
          flutter: '/opt/flutter/bin/flutter',
          flavor: 'staging',
          target: 'lib/main_staging.dart',
          dartDefines: ['API_BASE_URL=https://example.com/v1,canary'],
          dartDefineFromFiles: ['config/dev,canary.json'],
          verbose: true,
        ),
        [
          'controller.dart',
          '--session-dir',
          '/tmp/.fdb',
          '--project',
          '/tmp/project',
          '--device',
          'macos',
          '--flutter',
          '/opt/flutter/bin/flutter',
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
          '--dart-define',
          'API_BASE_URL=https://example.com/v1,canary',
          '--dart-define-from-file',
          'config/dev,canary.json',
          '--verbose',
        ],
      );
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

    test('writeAppIdFromProjectForLaunch resolves iOS flavored bundle id from Debug xcconfig', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('ios', false);
      _writeFile('${setup.project.path}/ios/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/ios/Flutter/Debug-staging.xcconfig',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.ios.staging',
      );
      _writeFile(
        '${setup.project.path}/ios/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.ios.base;',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.ios.staging');
    });

    test('writeAppIdFromProjectForLaunch resolves iOS flavored bundle id from pbxproj build config', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('ios', false);
      _writeFile('${setup.project.path}/ios/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/ios/Runner.xcodeproj/project.pbxproj',
        '''
Debug = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.base;
};
Debug-staging-RunnerTests = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.staging.RunnerTests;
};
Debug-staging = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.staging;
};
RunnerTests = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.base.RunnerTests;
};
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.staging');
    });

    test('writeAppIdFromProjectForLaunch resolves macOS flavored bundle id from Flutter xcconfig', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('macos', false);
      _writeFile('${setup.project.path}/macos/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/macos/Flutter/Debug-staging.xcconfig',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.flutter-staging',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.macos.flutter-staging');
    });

    test('writeAppIdFromProjectForLaunch resolves macOS flavored bundle id from Runner config xcconfig', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('macos', false);
      _writeFile('${setup.project.path}/macos/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/macos/Runner/Configs/Debug-staging.xcconfig',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.runner-staging',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.macos.runner-staging');
    });

    test('writeAppIdFromProjectForLaunch keeps macOS AppInfo fallback without flavor', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('macos', false);
      _writeFile('${setup.project.path}/macos/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/macos/Runner/Configs/AppInfo.xcconfig',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.base',
      );

      writeAppIdFromProjectForLaunch(setup.project.path);

      expect(File(appIdFile).readAsStringSync(), 'com.example.macos.base');
    });

    test('writeAppIdFromProjectForLaunch prefers macOS flavored pbxproj over AppInfo fallback', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('macos', false);
      _writeFile('${setup.project.path}/macos/Runner/Info.plist', '''
<plist>
  <dict>
    <key>CFBundleIdentifier</key>
    <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </dict>
</plist>
''');
      _writeFile(
        '${setup.project.path}/macos/Runner/Configs/AppInfo.xcconfig',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.base',
      );
      _writeFile(
        '${setup.project.path}/macos/Runner.xcodeproj/project.pbxproj',
        '''
Debug = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.base;
};
Debug-staging = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.macos.staging;
};
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.macos.staging');
    });

    test('writeAppIdFromProjectForLaunch resolves Android Groovy flavor applicationId', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle',
        '''
android {
  defaultConfig {
    applicationId "com.example.base"
  }
  productFlavors {
    staging {
      applicationId "com.example.staging"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.staging');
    });

    test('writeAppIdFromProjectForLaunch resolves Android Kotlin flavor applicationId', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle.kts',
        '''
android {
  defaultConfig {
    applicationId = "com.example.base"
  }
  productFlavors {
    create("staging") {
      applicationId = "com.example.staging"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.staging');
    });

    test('writeAppIdFromProjectForLaunch appends suffixes to Android explicit flavor applicationId', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle',
        '''
android {
  defaultConfig {
    applicationId "com.example.base"
  }
  productFlavors {
    staging {
      applicationId "com.example.staging"
      applicationIdSuffix ".flavor"
    }
  }
  buildTypes {
    debug {
      applicationIdSuffix ".debug"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.staging.flavor.debug');
    });

    test('writeAppIdFromProjectForLaunch composes Android flavor and build-type suffixes', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle',
        '''
android {
  defaultConfig {
    applicationId "com.example.base"
  }
  productFlavors {
    staging {
      applicationIdSuffix ".staging"
    }
  }
  buildTypes {
    debug {
      applicationIdSuffix ".debug"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.base.staging.debug');
    });

    test('writeAppIdFromProjectForLaunch composes Android namespace with suffixes', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle',
        '''
android {
  namespace "com.example.base"
  productFlavors {
    staging {
      applicationIdSuffix ".staging"
    }
  }
  buildTypes {
    debug {
      applicationIdSuffix ".debug"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.base.staging.debug');
    });

    test('writeAppIdFromProjectForLaunch falls back to base app id when flavor is unresolved', () async {
      final setup = await _createTempProjectWithSession();
      addTearDown(() async {
        await setup.root.delete(recursive: true);
      });

      writePlatformInfo('android-arm64', false);
      _writeFile(
        '${setup.project.path}/android/app/build.gradle',
        '''
android {
  defaultConfig {
    applicationId "com.example.base"
  }
  productFlavors {
    production {
      applicationId "com.example.production"
    }
  }
}
''',
      );

      writeAppIdFromProjectForLaunch(setup.project.path, flavor: 'staging');

      expect(File(appIdFile).readAsStringSync(), 'com.example.base');
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

Future<({Directory root, Directory project})> _createTempProjectWithSession() async {
  final root = await Directory.systemTemp.createTemp('fdb_launch_project_');
  final session = Directory('${root.path}/session')..createSync(recursive: true);
  initSessionDirFromPath(session.path);

  final project = Directory('${root.path}/project')..createSync(recursive: true);
  return (root: root, project: project);
}

void _writeFile(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
