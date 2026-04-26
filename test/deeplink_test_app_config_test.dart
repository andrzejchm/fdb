import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('example test app deeplink configuration', () {
    test('registers the fdbtest URL scheme on Android', () {
      final manifest = File(
        'example/test_app/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(manifest, contains('android:scheme="fdbtest"'));
    });

    test('registers the fdbtest URL scheme on iOS', () {
      final infoPlist = File(
        'example/test_app/ios/Runner/Info.plist',
      ).readAsStringSync();

      expect(infoPlist, contains('<string>fdbtest</string>'));
      expect(infoPlist, isNot(contains('<string>missing-scheme</string>')));
    });
  });
}
