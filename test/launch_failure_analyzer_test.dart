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

    test('classifies iOS bundle ID already claimed by another team', () {
      final output = _readFixture('ios_bundle_id_claimed.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_BUNDLE_ID_CLAIMED');
      expect(result.rootCause.toLowerCase(), contains('ios bundle identifier already claimed'));
      expect(result.contextLines.join('\n'), contains('Failed Registering Bundle Identifier'));
      expect(result.remediationHint, contains('bundle identifier'));
    });

    test('classifies iOS no Apple ID account found for Xcode team', () {
      final output = _readFixture('ios_no_account_for_team.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_NO_ACCOUNT_FOR_TEAM');
      expect(result.rootCause.toLowerCase(), contains('no apple id account found for xcode team'));
      expect(result.contextLines.join('\n'), contains('No Account for Team'));
      expect(result.remediationHint, contains('Apple ID'));
    });

    test('classifies Android SDK license not accepted', () {
      final output = _readFixture('android_license_not_accepted.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'ANDROID_LICENSE_NOT_ACCEPTED');
      expect(result.rootCause.toLowerCase(), contains('android sdk license not accepted'));
      expect(result.contextLines.join('\n'), contains('flutter doctor --android-licenses'));
      expect(result.remediationHint, contains('flutter doctor --android-licenses'));
    });

    test('classifies Android adb install failure via Package install error string', () {
      final output = _readFixture('android_adb_install_failed.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'ANDROID_INSTALL_ADB');
      expect(result.rootCause.toLowerCase(), contains('android install/adb failed'));
      expect(result.contextLines.join('\n'), contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
    });

    test('classifies iOS device locked', () {
      final output = _readFixture('ios_device_locked.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_DEVICE_LOCKED');
      expect(result.rootCause.toLowerCase(), contains('ios device is locked'));
      expect(result.contextLines.join('\n'), contains('Your device is locked'));
      expect(result.remediationHint, contains('Unlock'));
    });

    test('classifies iOS device locked via e80000e2 hex error code', () {
      const output = 'Installing and launching...\n'
          'Error 0xe80000e2: The device was not, or could not be, unlocked.\n'
          'Try relaunching Xcode and reconnecting the device.';

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_DEVICE_LOCKED');
      expect(result.rootCause.toLowerCase(), contains('ios device is locked'));
      expect(result.remediationHint, contains('Unlock'));
    });

    test('returns UNKNOWN category with non-empty hint for empty log', () {
      final result = analyzeLaunchFailure('');

      expect(result.category, 'UNKNOWN');
      expect(result.remediationHint, isNotNull);
      expect(result.remediationHint, isNotEmpty);
    });
  });
}

String _readFixture(String name) {
  final file = File('test/fixtures/launch_failures/$name');
  return file.readAsStringSync();
}
