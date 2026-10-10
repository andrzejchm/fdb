import 'dart:io';

import 'package:fdb/cli/adapters/native_tap_cli.dart';
import 'package:fdb/core/commands/native_tap/native_tap.dart';
import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:test/test.dart';

void main() {
  group('native-tap CLI iOS simulator output', () {
    test('HID success prints the token without a warning', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapIosSimulator(x: 201, y: 30)));

      expect(out.exitCode, 0);
      expect(out.stdout, 'NATIVE_TAPPED=ios-simulator X=201 Y=30\n');
      expect(out.stderr, isEmpty);
    });

    test('fallback warns with the reason, then prints the tap and native tokens', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapIosSimulatorFallback(
            x: 201,
            y: 30,
            reason: 'xcrun not available',
            tapResult: TapSuccess(widgetType: 'Text', x: 201.0, y: 30.0),
          ),
        ),
      );

      expect(out.exitCode, 0);
      expect(
        out.stderr,
        'WARNING: iOS simulator HID tap unavailable (xcrun not available); fell back to in-process tap '
        '(UIApplication.sendEvent), which cannot reach SpringBoard system dialogs.\n',
      );
      expect(out.stdout, 'TAPPED=Text X=201.0 Y=30.0\nNATIVE_TAPPED=ios-simulator X=201 Y=30\n');
    });

    test('fallback returns the tap error without the native token', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapIosSimulatorFallback(x: 1, y: 2, reason: 'r', tapResult: TapRelayedError('boom')),
        ),
      );

      expect(out.exitCode, 1);
      expect(out.stderr, endsWith('ERROR: boom\n'));
      expect(out.stdout, isEmpty);
    });

    test('out of bounds is an ERROR', () {
      final out = _capture(
        () => formatNativeTapResult(
            const NativeTapIosSimulatorOutOfBounds('coordinates 999.0,30.0 are outside the screen')),
      );

      expect(out.exitCode, 1);
      expect(out.stderr, 'ERROR: coordinates 999.0,30.0 are outside the screen\n');
      expect(out.stdout, isEmpty);
    });

    test('unknown orientation is an ERROR', () {
      const message = "native-tap can't tell which way the simulator is rotated (interface orientation 0); "
          'wait a moment and try again, or rotate it to portrait';
      final out = _capture(() => formatNativeTapResult(const NativeTapIosSimulatorOrientationUnknown(message)));

      expect(out.exitCode, 1);
      expect(out.stderr, 'ERROR: $message\n');
      expect(out.stdout, isEmpty);
    });

    test('partial delivery is an ERROR', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapIosSimulatorFailed('touch partially delivered: boom')),
      );

      expect(out.exitCode, 1);
      expect(out.stderr, 'ERROR: touch partially delivered: boom\n');
      expect(out.stdout, isEmpty);
    });

    test('--text tap appends the matched label, escaped', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapIosSimulator(x: 275, y: 474, text: 'Open in “Test App” \\ "now"')),
      );

      expect(out.exitCode, 0);
      expect(out.stdout, 'NATIVE_TAPPED=ios-simulator X=275 Y=474 TEXT="Open in “Test App” \\\\ \\"now\\""\n');
      expect(out.stderr, isEmpty);
    });

    test('--text without the accessibility API is an ERROR with the reason', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapIosSimulatorAccessibilityUnavailable('this CoreSimulator has no accessibility request API'),
        ),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: native-tap --text needs the iOS simulator accessibility API, which is not available '
        '(this CoreSimulator has no accessibility request API). Tap by coordinates with --at x,y instead.\n',
      );
      expect(out.stdout, isEmpty);
    });
  });

  group('native-tap CLI iOS simulator --text errors', () {
    test('tree unreadable until the deadline', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapIosSimulatorTreeUnreadable('reading the accessibility tree timed out after 10s'),
        ),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: native-tap --text could not read the iOS simulator accessibility tree '
        '(reading the accessibility tree timed out after 10s).\n',
      );
    });

    test('tap unavailable after a match', () {
      final out = _capture(
        () => formatNativeTapResult(
            const NativeTapIosSimulatorTapUnavailable('no simulator UDID recorded for this session')),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: native-tap --text could not tap on the iOS simulator (no simulator UDID recorded for this session).\n',
      );
    });

    test('labels without mappable frames', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapIosSimulatorFramesUnmapped(query: 'Allow', orientation: 'landscapeLeft', labels: ['Allow']),
        ),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: native-tap --text could not place the native elements on the iOS simulator screen (landscapeLeft), '
        'so "Allow" can\'t be tapped by label. Rotate the simulator to portrait, or tap with --at x,y. '
        'Labels: "Allow"\n',
      );
    });

    test('macOS with --text suggests fdb tap --text', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapMacosUnsupported(x: null, y: null)));

      expect(out.stderr, contains('Use `fdb tap --text <label>` instead'));
    });

    test('macOS with coordinates suggests fdb tap --at', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapMacosUnsupported(x: 1, y: 2)));

      expect(out.stderr, contains('Use `fdb tap --at 1.0,2.0` instead'));
    });
  });

  group('native-tap CLI Android output', () {
    test('coordinate tap keeps the original token', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapAndroid(x: 1275, y: 2974)));

      expect(out.exitCode, 0);
      expect(out.stdout, 'NATIVE_TAPPED=android X=1275 Y=2974\n');
      expect(out.stderr, isEmpty);
    });

    test('--text tap appends the matched label', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapAndroid(x: 720, y: 2452, text: 'While using the app')),
      );

      expect(out.exitCode, 0);
      expect(out.stdout, 'NATIVE_TAPPED=android X=720 Y=2452 TEXT="While using the app"\n');
    });

    test('TEXT escapes backslashes and quotes', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapAndroid(x: 1, y: 2, text: r'Say "hi" \ bye')));

      expect(out.stdout, 'NATIVE_TAPPED=android X=1 Y=2 TEXT="Say \\"hi\\" \\\\ bye"\n');
    });

    test('no match lists the visible labels', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapNoMatch(query: 'Allow', visibleLabels: ['Only this time', 'Deny'])),
      );

      expect(out.exitCode, 1);
      expect(out.stderr, 'ERROR: No native element matching "Allow". Visible labels: "Only this time", "Deny"\n');
      expect(out.stdout, isEmpty);
    });

    test('no match caps the label list', () {
      final labels = [for (var i = 0; i < 25; i++) 'L$i'];
      final out = _capture(() => formatNativeTapResult(NativeTapNoMatch(query: 'x', visibleLabels: labels)));

      expect(out.stderr, contains('"L19", ... (5 more)\n'));
      expect(out.stderr, isNot(contains('"L20"')));
    });

    test('no match on an empty screen', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapNoMatch(query: 'x', visibleLabels: [])));

      expect(out.stderr, 'ERROR: No native element matching "x". Visible labels: none\n');
    });

    test('ambiguous matches list candidates and the --index hint', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapAmbiguous(
            query: 'ok',
            candidates: [(label: 'OK', x: 270, y: 650), (label: 'ok', x: 810, y: 650)],
          ),
        ),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: Found 2 native elements matching "ok". Use --index to specify which one (0-based):\n'
        '  [0] "OK" at 270,650\n'
        '  [1] "ok" at 810,650\n',
      );
    });

    test('index out of range', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapIndexOutOfRange(query: 'ok', index: 2, count: 1)),
      );

      expect(out.stderr, 'ERROR: --index 2 is out of range: found 1 native element matching "ok" (0-based).\n');
    });

    test('dump failure with the idle-state hint', () {
      final out = _capture(
        () => formatNativeTapResult(const NativeTapUiDumpFailed('ERROR: could not get idle state.')),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: Could not read the Android UI hierarchy (uiautomator dump): ERROR: could not get idle state.\n'
        '  uiautomator needs the screen to stop animating. Retry, or tap by coordinates with --at x,y.\n',
      );
    });

    test('blocked injection names the OEM settings', () {
      final out = _capture(
        () => formatNativeTapResult(
          const NativeTapInputInjectionBlocked(
            'java.lang.SecurityException: Injecting input events requires INJECT_EVENTS\n\tat android.os.Parcel',
          ),
        ),
      );

      expect(out.exitCode, 1);
      expect(
        out.stderr,
        'ERROR: Android blocked input injection (INJECT_EVENTS). Enable it in Developer options: '
        'Xiaomi/HyperOS "USB debugging (Security settings)", OPPO/OnePlus/Realme "Disable permission monitoring".\n'
        '  adb said: java.lang.SecurityException: Injecting input events requires INJECT_EVENTS\n',
      );
    });

    test('device pixel ratio unavailable', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapDevicePixelRatioUnavailable('why')));

      expect(out.stderr, 'ERROR: Could not determine the device pixel ratio for --logical: why\n');
    });

    test('physical iOS with --text keeps the advice generic', () {
      final out = _capture(() => formatNativeTapResult(const NativeTapPhysicalIosUnsupported(x: null, y: null)));

      expect(out.stderr, contains('Use `fdb tap --at x,y` instead'));
    });
  });

  group('native-tap CLI flag validation', () {
    Future<void> expectError(List<String> args, String error) async {
      final out = await _captureAsync(() => runNativeTapCli(args));
      expect(out.exitCode, 1, reason: 'args: $args');
      expect(out.stderr, startsWith('ERROR: $error'), reason: 'args: $args');
      expect(out.stdout, isEmpty);
    }

    test('--text with --at', () => expectError(['--text', 'Allow', '--at', '1,2'], '--text cannot be combined'));

    test('--text with --x/--y', () => expectError(['--text', 'Allow', '--x', '1'], '--text cannot be combined'));

    test('--text with --logical', () => expectError(['--text', 'Allow', '--logical'], '--logical only applies'));

    test('empty --text', () => expectError(['--text', '  '], '--text must not be empty'));

    test('--index without --text', () => expectError(['--at', '1,2', '--index', '0'], '--index only applies'));

    test('invalid --index', () => expectError(['--text', 'a', '--index', '-1'], 'Invalid value for --index: -1'));

    test('invalid --timeout', () => expectError(['--text', 'a', '--timeout', 'soon'], 'Invalid value for --timeout'));

    test('no target', () => expectError([], 'No coordinates provided'));

    test('--timeout without --text', () => expectError(['--at', '1,2', '--timeout', '3'], '--timeout only applies'));

    test('non-finite --at', () => expectError(['--at', 'NaN,2'], 'Coordinates must be finite numbers.'));

    test('infinite --x', () => expectError(['--x', 'Infinity', '--y', '2'], 'Coordinates must be finite numbers.'));
  });
}

({int exitCode, String stdout, String stderr}) _capture(int Function() body) {
  final out = _CapturingStdout();
  final err = _CapturingStdout();
  final exitCode = IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
  return (exitCode: exitCode, stdout: out.buffer.toString(), stderr: err.buffer.toString());
}

Future<({int exitCode, String stdout, String stderr})> _captureAsync(Future<int> Function() body) async {
  final out = _CapturingStdout();
  final err = _CapturingStdout();
  final exitCode = await IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
  return (exitCode: exitCode, stdout: out.buffer.toString(), stderr: err.buffer.toString());
}

class _CapturingStdout implements Stdout {
  final buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
