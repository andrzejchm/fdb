import 'package:fdb/core/commands/tap/tap.dart';
import 'package:fdb/src/controller/commands/fdb_describe.dart';
import 'package:fdb/src/controller/commands/fdb_tap.dart';
import 'package:test/test.dart';

void main() {
  test('a covered target is retried until --timeout, then its error is surfaced', () async {
    const covered = 'ElevatedButton is not hittable: it is covered by ModalBarrier at 200.0,410.0. '
        'Dismiss what covers it or use --index/another selector';
    final tap = _FakeTap(error: covered);
    final stopwatch = Stopwatch()..start();

    final result = await _tap(_input(key: 'submit', timeoutSeconds: 1), tap);

    expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', covered));
    expect(tap.calls.length, greaterThan(1));
    expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('a disabled target is retried until the app enables it, then tapped once', () async {
    final tap = _FakeTap(error: 'ElevatedButton is disabled', failures: 2);

    final result = await _tap(_input(key: 'send'), tap);

    expect(result, isA<TapSuccess>().having((s) => s.widgetType, 'widgetType', 'ElevatedButton'));
    expect(tap.calls.length, 3);
  });

  group('tap @N', () {
    final screen = [
      {'ref': 1, 'type': 'ElevatedButton', 'key': 'save', 'text': 'Save', 'x': 100.0, 'y': 200.0},
      {'ref': 2, 'type': 'TextButton', 'key': null, 'text': '\uE000 · Delete', 'x': 300.0, 'y': 200.0},
      {'ref': 3, 'type': 'ElevatedButton', 'key': null, 'text': 'Later', 'x': 0.0, 'y': 9999999.0, 'built': false},
    ];

    test('taps the described widget by its identity, not by raw coordinates', () async {
      final tap = _FakeTap();

      final result = await _tap(_input(ref: 2), tap, screen: screen);

      expect(tap.calls.single, {'isolateId': 'isolates/1', 'refType': 'TextButton', 'refX': '300.0', 'refY': '200.0'});
      expect(
        result,
        isA<TapSuccess>().having((s) => (s.widgetType, s.text), 'type, text', ('TextButton', 'Delete')),
      );
    });

    test('with --expect-text matching a part of the entry text taps it', () async {
      final tap = _FakeTap();

      final result = await _tap(_input(ref: 2, expectText: 'Delete', expectType: 'TextButton'), tap, screen: screen);

      expect(result, isA<TapSuccess>());
    });

    test('whose entry no longer has the expected text or type fails and taps nothing', () async {
      for (final input in [_input(ref: 1, expectText: 'Delete'), _input(ref: 1, expectType: 'TextButton')]) {
        final tap = _FakeTap();

        final result = await _tap(input, tap, screen: screen);

        expect(result, isA<TapRefMismatch>().having((m) => (m.type, m.text), 'actual', ('ElevatedButton', 'Save')));
        expect(tap.calls, isEmpty);
      }
    });

    test('on an entry that is not built on screen fails and taps nothing', () async {
      final tap = _FakeTap();

      final result = await _tap(_input(ref: 3), tap, screen: screen);

      expect(result, isA<TapRefOffScreen>());
      expect(tap.calls, isEmpty);
    });

    test('identity reaches ext.fdb.tap through the controller process', () {
      const request = FdbTapCommandRequest(
        token: 't',
        isolateId: 'isolates/1',
        refType: 'ElevatedButton',
        refKey: 'save',
        refX: '100.0',
        refY: '200.0',
      );

      final params = FdbTapCommandRequest.fromJson(request.toJson()).toVmParams();

      expect(params, {
        'isolateId': 'isolates/1',
        'refType': 'ElevatedButton',
        'refKey': 'save',
        'refX': '100.0',
        'refY': '200.0',
      });
    });

    test('to a disabled widget is retried until --timeout, then fails with "is disabled"', () async {
      final tap = _FakeTap(error: 'ElevatedButton is disabled');

      final result = await _tap(_input(ref: 1, timeoutSeconds: 1), tap, screen: screen);

      expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', 'ElevatedButton is disabled'));
      expect(tap.calls.length, greaterThan(1));
    });

    test('whose widget moved before the tap fails without retrying', () async {
      final tap = _FakeTap(error: 'No hittable element found for matcher');

      final result = await _tap(_input(ref: 1), tap, screen: screen);

      expect(result, isA<TapRefMoved>());
      expect(tap.calls.length, 1);
    });
  });
}

TapInput _input({
  String? key,
  int? ref,
  String? expectText,
  String? expectType,
  int timeoutSeconds = 5,
}) =>
    (
      text: null,
      key: key,
      type: null,
      index: null,
      x: null,
      y: null,
      usedAt: false,
      describeRef: ref,
      expectText: expectText,
      expectType: expectType,
      timeoutSeconds: timeoutSeconds,
    );

Future<TapResult> _tap(TapInput input, _FakeTap tap, {List<Map<String, Object?>> screen = const []}) => tapWidget(
      input,
      checkFdbHelperFn: () async => 'isolates/1',
      fdbTapFn: tap.call,
      fdbDescribeFn: (_) async => FdbDescribeCommandResponse(
        error: null,
        snapshot: {'interactive': screen},
        unexpected: null,
      ),
    );

/// Records ext.fdb.tap params. Fails with [error] (when set) for the first
/// [failures] calls, then succeeds.
class _FakeTap {
  _FakeTap({this.error, this.failures = 1 << 30});

  final String? error;
  final int failures;
  final calls = <Map<String, dynamic>>[];

  Future<FdbTapCommandResponse> call(Map<String, dynamic> params) async {
    calls.add(params);
    final error = calls.length <= failures ? this.error : null;
    return FdbTapCommandResponse(
      status: error == null ? 'Success' : null,
      error: error,
      unexpected: null,
      widgetType: 'ElevatedButton',
      x: null,
      y: null,
      warning: null,
    );
  }
}
