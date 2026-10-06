import 'package:fdb/core/commands/tap/tap.dart';
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
    test('sends the ref and no coordinates or selector', () async {
      final tap = _FakeTap(text: '\uE000 · Delete');

      final result = await _tap(_input(ref: 7, expectText: 'Delete'), tap);

      expect(tap.calls.single, {'isolateId': 'isolates/1', 'ref': '7', 'expectText': 'Delete'});
      expect(
          result, isA<TapSuccess>().having((s) => (s.widgetType, s.text), 'type, text', ('ElevatedButton', 'Delete')));
    });

    test('reaches ext.fdb.tap through the controller process', () {
      const request = FdbTapCommandRequest(token: 't', isolateId: 'isolates/1', ref: '7', expectType: 'TextButton');

      final params = FdbTapCommandRequest.fromJson(request.toJson()).toVmParams();

      expect(params, {'isolateId': 'isolates/1', 'ref': '7', 'expectType': 'TextButton'});
    });

    test('to a stale widget fails at once', () async {
      const stale = '@7 is stale: the widget was removed or rebuilt. Run fdb describe again.';
      final tap = _FakeTap(error: stale);

      final result = await _tap(_input(ref: 7), tap);

      expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', stale));
      expect(tap.calls.length, 1);
    });

    test('to a disabled widget is retried until --timeout, then fails with "is disabled"', () async {
      final tap = _FakeTap(error: 'ElevatedButton is disabled');

      final result = await _tap(_input(ref: 1, timeoutSeconds: 1), tap);

      expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', 'ElevatedButton is disabled'));
      expect(tap.calls.length, greaterThan(1));
    });

    test('with an fdb_helper that has no refs fails and says to update it', () async {
      final tap = _FakeTap(error: 'params must contain at least one of: key, text, type, or both x and y');

      final result = await _tap(_input(ref: 1), tap);

      expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', contains('too old for @N refs')));
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
      ref: ref,
      expectText: expectText,
      expectType: expectType,
      timeoutSeconds: timeoutSeconds,
    );

Future<TapResult> _tap(TapInput input, _FakeTap tap) => tapWidget(
      input,
      checkFdbHelperFn: () async => 'isolates/1',
      fdbTapFn: tap.call,
    );

/// Records ext.fdb.tap params. Fails with [error] (when set) for the first
/// [failures] calls, then succeeds, reporting [text] for the tapped widget.
class _FakeTap {
  _FakeTap({this.error, this.failures = 1 << 30, this.text});

  final String? error;
  final String? text;
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
      text: text,
    );
  }
}
