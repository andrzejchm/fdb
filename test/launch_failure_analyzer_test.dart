import 'dart:io';

import 'package:fdb/core/launch_failure_analyzer.dart';
import 'package:test/test.dart';

void main() {
  group('analyzeLaunchFailure', () {
    test('classifies iOS codesign failures and keeps context lines', () {
      final output = _readFixture('ios_codesign_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_CODESIGN_PROVISIONING');
      expect(result.rootCause.toLowerCase(), contains('codesign'));
      expect(result.contextLines.length, inInclusiveRange(10, 20));
      expect(result.contextLines.join('\n'), contains('errSecInternalComponent'));
      expect(result.remediationHint, contains('Possible locked keychain'));
    });

    test('classifies iOS build script failures', () {
      final output = _readFixture('ios_build_script_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_BUILD_SCRIPT');
      expect(result.rootCause.toLowerCase(), contains('build script failed'));
      expect(result.contextLines.join('\n'), contains('xcodebuild failed'));
    });

    test('classifies Android adb/install failures', () {
      final output = _readFixture('android_install_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'ANDROID_INSTALL_ADB');
      expect(result.rootCause.toLowerCase(), contains('android install/adb failed'));
      expect(result.contextLines.join('\n'), contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
    });

    test('classifies missing SDK/toolchain failures', () {
      final output = _readFixture('sdk_toolchain_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'SDK_TOOLCHAIN');
      expect(result.rootCause.toLowerCase(), contains('missing sdk/toolchain'));
      expect(result.contextLines.join('\n'), contains('flutter doctor -v'));
    });

    test('classifies generic Flutter build failures', () {
      final output = _readFixture('flutter_build_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'FLUTTER_BUILD');
      expect(result.rootCause.toLowerCase(), contains('flutter build failed'));
      expect(result.contextLines.join('\n'), contains('compileFlutterBuildDebug'));
    });

    test('falls back to unknown with best-effort snippet', () {
      final output = _readFixture('unknown_failure.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'UNKNOWN');
      expect(result.rootCause, contains('Unhandled exception: socket closed'));
      expect(result.contextLines, isNotEmpty);
    });
  });
}

String _readFixture(String name) {
  final file = File('test/fixtures/launch_failures/$name');
  return file.readAsStringSync();
}
