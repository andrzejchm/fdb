import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('app id resolution from native project files', () {
    // ---------------------------------------------------------------------------
    // iOS — Info.plist with $(PRODUCT_BUNDLE_IDENTIFIER) variable reference
    // ---------------------------------------------------------------------------

    group('iOS', () {
      test('Info.plist CFBundleIdentifier is a variable reference', () {
        final plist = File('example/test_app/ios/Runner/Info.plist').readAsStringSync();
        // Confirm this is the broken scenario: the plist contains the variable.
        expect(plist, contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)'));
      });

      test('project.pbxproj contains PRODUCT_BUNDLE_IDENTIFIER for Runner target', () {
        final pbxproj = File(
          'example/test_app/ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();

        final matches = RegExp(
          r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([A-Za-z0-9._-]+)\s*;',
        ).allMatches(pbxproj).toList();

        expect(matches, isNotEmpty);

        // The shortest match is the main Runner target (not RunnerTests).
        final ids = matches.map((m) => m.group(1)!).toList()..sort((a, b) => a.length.compareTo(b.length));
        expect(ids.first, equals('dev.andrzejchm.fdb.testApp'));
      });

      test('pbxproj resolver selects the main bundle id (shortest), not a test target', () {
        final pbxproj = File(
          'example/test_app/ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();

        final allMatches = RegExp(
          r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([A-Za-z0-9._-]+)\s*;',
        ).allMatches(pbxproj).map((m) => m.group(1)!).toList();

        // There must be both main and test targets present.
        expect(allMatches.any((id) => id.contains('RunnerTests')), isTrue);
        expect(allMatches.any((id) => !id.contains('RunnerTests')), isTrue);

        // Picking the shortest correctly gives the main app bundle id.
        allMatches.sort((a, b) => a.length.compareTo(b.length));
        expect(allMatches.first, equals('dev.andrzejchm.fdb.testApp'));
      });
    });

    // ---------------------------------------------------------------------------
    // macOS — Info.plist with $(PRODUCT_BUNDLE_IDENTIFIER) + AppInfo.xcconfig
    // ---------------------------------------------------------------------------

    group('macOS', () {
      test('Info.plist CFBundleIdentifier is a variable reference', () {
        final plist = File('example/test_app/macos/Runner/Info.plist').readAsStringSync();
        expect(plist, contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)'));
      });

      test('AppInfo.xcconfig contains the resolved PRODUCT_BUNDLE_IDENTIFIER', () {
        final xcconfig = File(
          'example/test_app/macos/Runner/Configs/AppInfo.xcconfig',
        ).readAsStringSync();

        final match = RegExp(
          r'^\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.+)$',
          multiLine: true,
        ).firstMatch(xcconfig);

        expect(match, isNotNull);
        expect(match!.group(1)!.trim(), equals('dev.andrzejchm.fdb.testApp'));
      });
    });
  });
}
