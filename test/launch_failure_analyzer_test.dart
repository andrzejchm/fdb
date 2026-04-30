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

    // New categories grounded in real flutter run / Xcode / adb output strings.

    test('classifies iOS bundle ID already claimed by another team', () {
      // Fixture uses exact Xcode xcresult error strings surfaced by Flutter tool
      // (mac.dart _handleXCResultIssue): "Failed Registering Bundle Identifier:
      // The app identifier … cannot be registered to your development team because
      // it is not available."
      final output = _readFixture('ios_bundle_id_claimed.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_BUNDLE_ID_CLAIMED');
      expect(result.rootCause.toLowerCase(), contains('ios bundle identifier already claimed'));
      expect(result.contextLines.join('\n'), contains('Failed Registering Bundle Identifier'));
      expect(result.remediationHint, contains('bundle identifier'));
    });

    test('classifies iOS no Apple ID account found for Xcode team', () {
      // Fixture uses exact Xcode xcresult string: "No Account for Team "XXXXXXXXX".
      // Add a new account in Accounts settings or verify that your accounts have
      // valid credentials."
      final output = _readFixture('ios_no_account_for_team.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_NO_ACCOUNT_FOR_TEAM');
      expect(result.rootCause.toLowerCase(), contains('no apple id account found for xcode team'));
      expect(result.contextLines.join('\n'), contains('No Account for Team'));
      expect(result.remediationHint, contains('Apple ID'));
    });

    test('classifies Android SDK license not accepted', () {
      // Fixture uses exact Gradle output line matched by Flutter tool
      // (gradle_errors.dart licenseNotAcceptedHandler):
      // "You have not accepted the license agreements of the following SDK components"
      final output = _readFixture('android_license_not_accepted.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'ANDROID_LICENSE_NOT_ACCEPTED');
      expect(
        result.rootCause.toLowerCase(),
        contains('android sdk license not accepted'),
      );
      expect(
        result.contextLines.join('\n'),
        contains('flutter doctor --android-licenses'),
      );
      expect(result.remediationHint, contains('flutter doctor --android-licenses'));
    });

    test('classifies Android adb install failure via Package install error string', () {
      // Fixture uses exact Flutter tool string from android_device.dart:
      // "Package install error: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: …]"
      // and "Error: ADB exited with exit code 1".
      final output = _readFixture('android_adb_install_failed.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'ANDROID_INSTALL_ADB');
      expect(result.rootCause.toLowerCase(), contains('android install/adb failed'));
      expect(result.contextLines.join('\n'), contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
    });

    test('classifies iOS device locked via Flutter tool string', () {
      // Fixture uses exact Flutter tool string from ios_deploy.dart
      // (_monitorIOSDeployFailure, deviceLockedError = 'e80000e2'):
      // "Your device is locked. Unlock your device first before running."
      final output = _readFixture('ios_device_locked.log');

      final result = analyzeLaunchFailure(output);

      expect(result.category, 'IOS_DEVICE_LOCKED');
      expect(result.rootCause.toLowerCase(), contains('ios device is locked'));
      expect(result.contextLines.join('\n'), contains('Your device is locked'));
      expect(result.remediationHint, contains('Unlock'));
    });

    test('classifies iOS device locked via e80000e2 hex error code', () {
      // Exercises the e80000e2 strong token variant and the
      // "the device was not, or could not be, unlocked" strong token.
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
