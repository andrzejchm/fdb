import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:test/test.dart';

void main() {
  group('fnv1a64Hex', () {
    test('matches the reference vectors', () {
      expect(fnv1a64Hex(const []), 'cbf29ce484222325');
      expect(fnv1a64Hex(utf8.encode('a')), 'af63dc4c8601ec8c');
    });

    test('is stable for the same input and differs for different input', () {
      expect(fnv1a64Hex(utf8.encode('fdb')), fnv1a64Hex(utf8.encode('fdb')));
      expect(fnv1a64Hex(utf8.encode('fdb')), isNot(fnv1a64Hex(utf8.encode('fdc'))));
    });
  });

  group('cache location', () {
    test('FDB_CACHE_DIR wins over HOME', () {
      expect(
        iosSimulatorHidCacheDir(environment: {'FDB_CACHE_DIR': '/tmp/fdb-cache', 'HOME': '/Users/me'}),
        '/tmp/fdb-cache',
      );
    });

    test('defaults to HOME/Library/Caches/fdb', () {
      expect(iosSimulatorHidCacheDir(environment: {'HOME': '/Users/me'}), '/Users/me/Library/Caches/fdb');
    });

    test('is null without FDB_CACHE_DIR and HOME', () {
      expect(iosSimulatorHidCacheDir(environment: {}), isNull);
    });

    test('binary path is keyed by the compiler flags and the source', () {
      final hash = fnv1a64Hex(utf8.encode('-swift-version 5 -O\n$iosSimulatorHidSource'));
      expect(iosSimulatorHidBinaryPath('/cache'), '/cache/ios-simulator-hid-$hash');
      expect(iosSimulatorHidBinaryPath('/cache', source: 'other'), isNot(iosSimulatorHidBinaryPath('/cache')));
      expect(iosSimulatorHidBinaryPath('/cache', flags: ['-O']), isNot(iosSimulatorHidBinaryPath('/cache')));
    });
  });

  group('extractHidErrorMessage', () {
    test('returns the last ERROR line and ignores other stderr noise', () {
      const stderr = 'objc[123]: Class SimFoo is implemented in both A and B. One of the two will be used.\n'
          'ERROR: first\n'
          'objc[123]: Class SimBar is implemented in both A and B.\n'
          'ERROR: touch partially delivered: timed out sending the touch up to the simulator\n'
          '\n';
      expect(
        extractHidErrorMessage(stderr),
        'touch partially delivered: timed out sending the touch up to the simulator',
      );
    });

    test('is null without an ERROR line', () {
      expect(extractHidErrorMessage('objc[1]: noise\n'), isNull);
      expect(extractHidErrorMessage(''), isNull);
    });
  });

  group('orientation', () {
    // iPhone 17 Pro: 402x874 points in portrait.
    const w = 402.0;
    const h = 874.0;

    ({double x, double y}) portrait(IosSimulatorOrientation o, double x, double y) =>
        iosSimulatorPortraitPoint(o, x: x, y: y, portraitWidth: w, portraitHeight: h);

    test('maps CoreSimulator values and refuses unknown ones', () {
      expect(IosSimulatorOrientation.fromRawValue(1), IosSimulatorOrientation.portrait);
      expect(IosSimulatorOrientation.fromRawValue(2), IosSimulatorOrientation.portraitUpsideDown);
      expect(IosSimulatorOrientation.fromRawValue(3), IosSimulatorOrientation.landscapeRight);
      expect(IosSimulatorOrientation.fromRawValue(4), IosSimulatorOrientation.landscapeLeft);
      expect(IosSimulatorOrientation.fromRawValue(0), isNull);
      expect(IosSimulatorOrientation.fromRawValue(5), isNull);
    });

    test('portrait passes the point through', () {
      expect(portrait(IosSimulatorOrientation.portrait, 358, 796), (x: 358.0, y: 796.0));
    });

    test('portraitUpsideDown mirrors both axes', () {
      expect(portrait(IosSimulatorOrientation.portraitUpsideDown, 358, 796), (x: 44.0, y: 78.0));
      expect(portrait(IosSimulatorOrientation.portraitUpsideDown, 0, 0), (x: w, y: h));
    });

    test('landscapeLeft maps (x, y) to (W - y, x)', () {
      // FAB measured on device at 768,338 in the 874x402 landscape frame.
      expect(portrait(IosSimulatorOrientation.landscapeLeft, 768, 338), (x: 64.0, y: 768.0));
      expect(portrait(IosSimulatorOrientation.landscapeLeft, 0, 0), (x: w, y: 0.0));
      expect(portrait(IosSimulatorOrientation.landscapeLeft, h, w), (x: 0.0, y: h));
    });

    test('landscapeRight maps (x, y) to (y, H - x)', () {
      expect(portrait(IosSimulatorOrientation.landscapeRight, 768, 338), (x: 338.0, y: 106.0));
      expect(portrait(IosSimulatorOrientation.landscapeRight, 0, 0), (x: 0.0, y: h));
      expect(portrait(IosSimulatorOrientation.landscapeRight, h, w), (x: w, y: 0.0));
    });

    test('every orientation maps the frame corners onto the portrait screen', () {
      for (final o in IosSimulatorOrientation.values) {
        final size = iosSimulatorOrientedSize(o, portraitWidth: w, portraitHeight: h);
        for (final corner in [(0.0, 0.0), (size.width, 0.0), (0.0, size.height), (size.width, size.height)]) {
          final p = portrait(o, corner.$1, corner.$2);
          expect(p.x, inInclusiveRange(0, w), reason: '$o $corner');
          expect(p.y, inInclusiveRange(0, h), reason: '$o $corner');
        }
      }
    });

    test('oriented size swaps width and height in landscape only', () {
      for (final o in IosSimulatorOrientation.values) {
        final size = iosSimulatorOrientedSize(o, portraitWidth: w, portraitHeight: h);
        expect(size, o.isLandscape ? (width: h, height: w) : (width: w, height: h), reason: '$o');
      }
    });

    test('bounds check uses the oriented size', () {
      bool inBounds(IosSimulatorOrientation o, double x, double y) =>
          iosSimulatorPointInBounds(o, x: x, y: y, portraitWidth: w, portraitHeight: h);

      // x beyond the portrait width is fine in landscape...
      expect(inBounds(IosSimulatorOrientation.landscapeLeft, 768, 338), isTrue);
      expect(inBounds(IosSimulatorOrientation.landscapeRight, 874, 402), isTrue);
      // ...but not in portrait.
      expect(inBounds(IosSimulatorOrientation.portrait, 768, 338), isFalse);
      expect(inBounds(IosSimulatorOrientation.portraitUpsideDown, 768, 338), isFalse);
      // y beyond the landscape height is out in landscape.
      expect(inBounds(IosSimulatorOrientation.landscapeLeft, 30, 500), isFalse);
      expect(inBounds(IosSimulatorOrientation.landscapeRight, 875, 30), isFalse);
      expect(inBounds(IosSimulatorOrientation.portrait, 30, 500), isTrue);
      for (final o in IosSimulatorOrientation.values) {
        expect(inBounds(o, -1, 0), isFalse, reason: '$o');
        expect(inBounds(o, 0, -1), isFalse, reason: '$o');
        expect(inBounds(o, 0, 0), isTrue, reason: '$o');
      }
    });

    test('Swift helper uses the same orientation values and formulas', () {
      expect(iosSimulatorHidSource, contains('uiOrientation'));
      expect(
        iosSimulatorHidSource,
        contains('1: "portrait", 2: "portraitUpsideDown", 3: "landscapeRight", 4: "landscapeLeft"'),
      );
      expect(iosSimulatorHidSource, contains('let landscape = orientation == 3 || orientation == 4'));
      expect(iosSimulatorHidSource, contains('let frameWidth = landscape ? heightPoints : widthPoints'));
      expect(iosSimulatorHidSource, contains('let frameHeight = landscape ? widthPoints : heightPoints'));
      expect(iosSimulatorHidSource, contains('x <= frameWidth, y <= frameHeight'));
      expect(
        iosSimulatorHidSource.replaceAll(RegExp(r'\s+'), ' '),
        allOf(
          contains('case 2: portraitX = widthPoints - x portraitY = heightPoints - y'),
          contains('case 3: portraitX = y portraitY = heightPoints - x'),
          contains('case 4: portraitX = widthPoints - y portraitY = x'),
          contains('case 1: portraitX = x portraitY = y'),
          contains('default: // Unreachable'),
        ),
      );
      expect(iosSimulatorHidSource, contains('CGPoint(x: portraitX / widthPoints, y: portraitY / heightPoints)'));
    });
  });

  test('source keeps the two-payload Indigo envelope and Xcode 27 lookup', () {
    expect(iosSimulatorHidSource, contains('SimDeviceLegacyHIDClient'));
    expect(iosSimulatorHidSource, contains('UInt32(0x0b)'));
    expect(iosSimulatorHidSource, contains('secondPayloadOffset'));
    expect(iosSimulatorHidSource, contains('SharedFrameworks'));
    expect(iosSimulatorHidSource, contains('outside the screen'));
    expect(iosSimulatorHidSource, contains('code: 3'));
    expect(iosSimulatorHidSource, contains('code: 4'));
    expect(iosSimulatorHidSource, contains('code: 5'));
    expect(iosSimulatorHidSource, contains('AutoreleasingUnsafeMutablePointer<NSError?>?'));
  });

  group('iosSimulatorHidTap with a fake runner', () {
    late Directory cacheDir;
    late _FakeRunner runner;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('fdb-hid-test-');
      runner = _FakeRunner();
    });

    tearDown(() => cacheDir.delete(recursive: true));

    Future<IosSimulatorHidResult> tap() => iosSimulatorHidTap(
          udid: 'UDID',
          x: 201,
          y: 30,
          environment: {'DEVELOPER_DIR': '/dev/dir'},
          runner: runner.call,
          cacheDir: cacheDir.path,
        );

    test('is unavailable when xcrun is missing', () async {
      runner.xcrunMissing = true;

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidUnavailable>().having((r) => r.reason, 'reason', startsWith('xcrun not available')),
      );
      expect(File(iosSimulatorHidBinaryPath(cacheDir.path)).existsSync(), isFalse);
    });

    test('is unavailable with the stderr tail when swiftc fails', () async {
      runner.compileExitCode = 1;
      runner.compileStderr = 'line1\nerror: boom\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidUnavailable>()
            .having((r) => r.reason, 'reason', 'swiftc failed (exit 1): line1; error: boom'),
      );
      expect(cacheDir.listSync(), isEmpty, reason: 'no partial binary is left in the cache');
    });

    test('compiles once, caches the binary and passes the tap arguments', () async {
      expect(await tap(), isA<IosSimulatorHidTapped>());
      expect(await tap(), isA<IosSimulatorHidTapped>());

      final binary = iosSimulatorHidBinaryPath(cacheDir.path);
      expect(File(binary).existsSync(), isTrue);
      final compiles = runner.calls.where((c) => c.first == 'xcrun').toList();
      expect(compiles, hasLength(1));
      expect(compiles.single.sublist(1, 5), ['swiftc', '-swift-version', '5', '-O']);
      expect(runner.calls.last, [binary, 'tap', '/dev/dir', 'UDID', '201.0', '30.0']);
    });

    test('maps exit code 3 to out-of-bounds without the ERROR prefix', () async {
      runner.tapExitCode = 3;
      runner.tapStderr = 'ERROR: coordinates 999.0,30.0 are outside the screen (402.0x874.0 points, portrait)\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidOutOfBounds>().having(
          (r) => r.message,
          'message',
          'coordinates 999.0,30.0 are outside the screen (402.0x874.0 points, portrait)',
        ),
      );
    });

    test('maps exit code 4 to failed using only the ERROR line', () async {
      runner.tapExitCode = 4;
      runner.tapStderr = 'objc[42]: Class SimDevice is implemented in both A and B.\n'
          'ERROR: touch partially delivered: sending the touch up failed: boom\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidFailed>().having(
          (r) => r.message,
          'message',
          'touch partially delivered: sending the touch up failed: boom',
        ),
      );
    });

    test('maps exit code 5 to orientation unknown, without a fallback', () async {
      runner.tapExitCode = 5;
      runner.tapStderr = 'objc[42]: noise\n'
          "ERROR: native-tap can't tell which way the simulator is rotated (interface orientation 0); "
          'wait a moment and try again, or rotate it to portrait\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidOrientationUnknown>().having(
          (r) => r.message,
          'message',
          "native-tap can't tell which way the simulator is rotated (interface orientation 0); "
              'wait a moment and try again, or rotate it to portrait',
        ),
      );
      expect(runner.calls.where((c) => c[1] == 'tap'), hasLength(1));
    });

    test('maps out-of-bounds using only the ERROR line', () async {
      runner.tapExitCode = 3;
      runner.tapStderr = 'objc[42]: noise\nERROR: coordinates 1.0,9999.0 are outside the screen\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidOutOfBounds>()
            .having((r) => r.message, 'message', 'coordinates 1.0,9999.0 are outside the screen'),
      );
    });

    test('rebuilds and retries once when the cached binary cannot start', () async {
      runner.tapQueue.add(const ProcessException('helper', [], 'Exec format error', 8));

      final result = await tap();

      expect(result, isA<IosSimulatorHidTapped>());
      expect(runner.calls.where((c) => c.first == 'xcrun'), hasLength(2));
      expect(runner.calls.where((c) => c[1] == 'tap'), hasLength(2));
    });

    test('rebuilds and retries once when the helper dies from a signal without output', () async {
      runner.tapQueue.add((exitCode: -11, stdout: '', stderr: ''));

      final result = await tap();

      expect(result, isA<IosSimulatorHidTapped>());
      expect(runner.calls.where((c) => c.first == 'xcrun'), hasLength(2));
    });

    test('is unavailable when the rebuilt binary is still broken', () async {
      runner.tapQueue.addAll([
        const ProcessException('helper', [], 'Exec format error', 8),
        (exitCode: -9, stdout: '', stderr: ''),
      ]);

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidUnavailable>().having((r) => r.reason, 'reason', startsWith('helper failed after rebuild')),
      );
      expect(runner.calls.where((c) => c[1] == 'tap'), hasLength(2), reason: 'retries only once');
    });

    test('removes stale temp binaries but keeps recent ones', () async {
      final stale = File('${cacheDir.path}/ios-simulator-hid-abc.1.1.tmp')..writeAsStringSync('x');
      stale.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 11)));
      final fresh = File('${cacheDir.path}/ios-simulator-hid-abc.2.2.tmp')..writeAsStringSync('x');
      final unrelated = File('${cacheDir.path}/other.tmp')..writeAsStringSync('x');
      unrelated.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));

      await tap();

      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(unrelated.existsSync(), isTrue);
    });

    test('maps other failures to unavailable', () async {
      runner.tapExitCode = 1;
      runner.tapStderr = 'ERROR: simulator UDID is not booted\n';

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidUnavailable>().having((r) => r.reason, 'reason', 'simulator UDID is not booted'),
      );
    });

    test('maps a helper timeout to failed, not unavailable (the down may have gone out)', () async {
      runner.tapTimesOut = true;

      final result = await tap();

      expect(
        result,
        isA<IosSimulatorHidFailed>().having((r) => r.message, 'message', contains('partially delivered')),
      );
      expect(runner.calls.where((c) => c[1] == 'tap'), hasLength(1), reason: 'no retry after a timeout');
    });

    test('uses xcode-select -p when DEVELOPER_DIR is unset', () async {
      runner.xcodeSelectPath = '/Applications/Xcode.app/Contents/Developer\n';

      final result = await iosSimulatorHidTap(
        udid: 'UDID',
        x: 1,
        y: 2,
        environment: {},
        runner: runner.call,
        cacheDir: cacheDir.path,
      );

      expect(result, isA<IosSimulatorHidTapped>());
      expect(runner.calls.last.sublist(1, 3), ['tap', '/Applications/Xcode.app/Contents/Developer']);
    });
  });

  group('runHidProcess', () {
    test('returns exit code and output', () async {
      final output = await runHidProcess('sh', ['-c', 'echo out; echo err >&2; exit 3'], const Duration(seconds: 10));

      expect(output, (exitCode: 3, stdout: 'out\n', stderr: 'err\n'));
    });

    test('kills the process and throws on timeout', () async {
      final stopwatch = Stopwatch()..start();

      await expectLater(
        runHidProcess('sleep', ['5'], const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  }, skip: Platform.isWindows ? 'needs sh and sleep' : false);

  test(
    'compiles the real helper and runs it against an unknown simulator',
    () async {
      final cacheDir = await Directory.systemTemp.createTemp('fdb-hid-it-');
      addTearDown(() => cacheDir.delete(recursive: true));

      final result = await iosSimulatorHidTap(
        udid: '00000000-0000-0000-0000-000000000000',
        x: 1,
        y: 1,
        cacheDir: cacheDir.path,
      );

      expect(File(iosSimulatorHidBinaryPath(cacheDir.path)).existsSync(), isTrue);
      expect(result, isA<IosSimulatorHidUnavailable>().having((r) => r.reason, 'reason', contains('not found')));
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: _hasSimulatorToolchain() ? false : 'requires macOS with xcrun swiftc, simctl and SimulatorKit',
  );
}

bool _hasSimulatorToolchain() {
  if (!Platform.isMacOS) return false;
  try {
    if (Process.runSync('xcrun', ['--find', 'swiftc']).exitCode != 0) return false;
    if (Process.runSync('xcrun', ['simctl', 'help']).exitCode != 0) return false;
    final developerDir =
        Platform.environment['DEVELOPER_DIR'] ?? (Process.runSync('xcode-select', ['-p']).stdout as String).trim();
    return Directory('$developerDir/Library/PrivateFrameworks/SimulatorKit.framework').existsSync() ||
        Directory('$developerDir/../SharedFrameworks/SimulatorKit.framework').existsSync();
  } catch (_) {
    return false;
  }
}

class _FakeRunner {
  final calls = <List<String>>[];
  bool xcrunMissing = false;
  int compileExitCode = 0;
  String compileStderr = '';
  String xcodeSelectPath = '/xcode/dev';
  int tapExitCode = 0;
  String tapStderr = '';
  bool tapTimesOut = false;

  /// Consumed first by helper runs: a [ProcessException] is thrown, a
  /// [HidProcessOutput] is returned.
  final tapQueue = <Object>[];

  Future<HidProcessOutput> call(String executable, List<String> arguments, Duration timeout) async {
    calls.add([executable, ...arguments]);
    switch (executable) {
      case 'xcrun':
        if (xcrunMissing) throw const ProcessException('xcrun', [], 'No such file or directory', 2);
        if (compileExitCode == 0) await File(arguments.last).writeAsString('binary');
        return (exitCode: compileExitCode, stdout: '', stderr: compileStderr);
      case 'xcode-select':
        return (exitCode: 0, stdout: xcodeSelectPath, stderr: '');
      default:
        if (tapQueue.isNotEmpty) {
          final next = tapQueue.removeAt(0);
          if (next is ProcessException) throw next;
          return next as HidProcessOutput;
        }
        if (tapTimesOut) throw TimeoutException('tap', timeout);
        return (exitCode: tapExitCode, stdout: tapExitCode == 0 ? 'TAPPED' : '', stderr: tapStderr);
    }
  }
}
