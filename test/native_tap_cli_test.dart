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
  });
}

({int exitCode, String stdout, String stderr}) _capture(int Function() body) {
  final out = _CapturingStdout();
  final err = _CapturingStdout();
  final exitCode = IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
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
