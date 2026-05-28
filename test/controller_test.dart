import 'package:fdb/src/controller/controller.dart';
import 'package:test/test.dart';

void main() {
  group('controller launch args', () {
    test('keeps commas inside dart-define values', () {
      final results = buildControllerArgParser().parse([
        '--session-dir',
        '/tmp/.fdb',
        '--project',
        '/tmp/project',
        '--device',
        'macos',
        '--flutter',
        'flutter',
        '--dart-define',
        'API_BASE_URL=https://example.com/v1,canary',
        '--dart-define-from-file',
        'config/dev,canary.json',
      ]);

      expect(
        results['dart-define'],
        ['API_BASE_URL=https://example.com/v1,canary'],
      );
      expect(
        results['dart-define-from-file'],
        ['config/dev,canary.json'],
      );
    });

    test('passes defines through to flutter run arguments', () {
      expect(
        buildFlutterRunArgs(
          device: 'macos',
          flavor: 'staging',
          target: 'lib/main_staging.dart',
          dartDefines: ['API_BASE_URL=https://example.com/v1,canary'],
          dartDefineFromFiles: ['config/dev,canary.json'],
          verbose: true,
        ),
        containsAllInOrder([
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
          '--dart-define=API_BASE_URL=https://example.com/v1,canary',
          '--dart-define-from-file=config/dev,canary.json',
          '--verbose',
        ]),
      );
    });

    test('builds flutter attach arguments with discovery fallbacks', () {
      expect(
        buildFlutterAttachArgs(
          device: 'ios-sim',
          target: 'lib/main_staging.dart',
          appId: 'com.example.app',
          debugUrl: 'http://127.0.0.1:12345/abc=/',
          verbose: true,
        ),
        containsAllInOrder([
          'attach',
          '--machine',
          '-d',
          'ios-sim',
          '--pid-file',
          '--target',
          'lib/main_staging.dart',
          '--app-id',
          'com.example.app',
          '--debug-url',
          'http://127.0.0.1:12345/abc=/',
          '--verbose',
        ]),
      );
    });
  });
}
