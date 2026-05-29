import 'package:fdb/core/commands/attach/attach.dart';
import 'package:fdb/core/commands/attach/vm_uri_discovery.dart';
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

  group('extractVmUriFromLog', () {
    test('extracts fdb_helper [FDB_VM_URI] marker (highest priority)', () {
      const log = '''
Some irrelevant line
flutter: [FDB_VM_URI] http://127.0.0.1:56789/AbCdEf==/
Another line
''';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:56789/AbCdEf==/');
    });

    test('extracts Flutter 3.x VM service line', () {
      const log = '''
Launching lib/main.dart on iPhone in debug mode...
The Dart VM service is listening on ws://127.0.0.1:12345/token=/
''';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:12345/token=/');
    });

    test('extracts Flutter daemon available-at format', () {
      const log = '''
A Dart VM Service on sdk gphone64 arm64 is available at: http://127.0.0.1:44321/xYz=/
''';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:44321/xYz=/');
    });

    test('extracts legacy Observatory format', () {
      const log = 'Observatory listening on http://127.0.0.1:9100/abc=/';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:9100/abc=/');
    });

    test('prefers [FDB_VM_URI] over Flutter engine line', () {
      const log = '''
The Dart VM service is listening on ws://127.0.0.1:11111/old=/
flutter: [FDB_VM_URI] http://127.0.0.1:22222/new==/
''';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:22222/new==/');
    });

    test('returns null for empty or unrelated log output', () {
      expect(extractVmUriFromLog(''), isNull);
      expect(extractVmUriFromLog('Nothing useful here\nJust regular app output\n'), isNull);
    });

    test('strips trailing /ws suffix', () {
      const log = 'flutter: [FDB_VM_URI] http://127.0.0.1:9999/tok=/ws';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:9999/tok=/');
    });

    test('normalises ws:// to http://', () {
      const log = 'The Dart VM service is listening on ws://127.0.0.1:8888/tok=/';
      expect(extractVmUriFromLog(log), 'http://127.0.0.1:8888/tok=/');
    });
  });
}
