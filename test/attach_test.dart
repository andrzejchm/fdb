import 'package:fdb/core/commands/attach/attach.dart';
import 'package:test/test.dart';

void main() {
  group('attach helpers', () {
    test('buildAttachControllerArgs selects attach mode and discovery flags', () {
      expect(
        buildAttachControllerArgs(
          ['controller.dart'],
          sessionDir: '/tmp/.fdb',
          project: '/tmp/project',
          device: 'ios-sim',
          flutter: '/opt/flutter/bin/flutter',
          target: 'lib/main_staging.dart',
          appId: 'com.example.app',
          debugUrl: 'http://127.0.0.1:12345/abc=/',
          verbose: true,
        ),
        [
          'controller.dart',
          '--mode',
          'attach',
          '--session-dir',
          '/tmp/.fdb',
          '--project',
          '/tmp/project',
          '--device',
          'ios-sim',
          '--flutter',
          '/opt/flutter/bin/flutter',
          '--target',
          'lib/main_staging.dart',
          '--app-id',
          'com.example.app',
          '--debug-url',
          'http://127.0.0.1:12345/abc=/',
          '--verbose',
        ],
      );
    });

    test('normalizeAttachDebugUrl accepts VM service websocket URIs', () {
      expect(
        normalizeAttachDebugUrl('ws://127.0.0.1:12345/abc=/ws'),
        'http://127.0.0.1:12345/abc=/',
      );
      expect(
        normalizeAttachDebugUrl('wss://example.com/abc=/ws/'),
        'https://example.com/abc=/',
      );
      expect(
        normalizeAttachDebugUrl('http://127.0.0.1:12345/abc=/'),
        'http://127.0.0.1:12345/abc=/',
      );
    });
  });
}
