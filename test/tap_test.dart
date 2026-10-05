import 'package:fdb/core/commands/tap/tap.dart';
import 'package:fdb/src/controller/commands/fdb_tap.dart';
import 'package:test/test.dart';

void main() {
  test('a covered target is retried until --timeout, then its error is surfaced', () async {
    const covered = 'ElevatedButton is not hittable: it is covered by ModalBarrier at 200.0,410.0. '
        'Dismiss what covers it or use --index/another selector';
    var calls = 0;
    final stopwatch = Stopwatch()..start();

    final result = await tapWidget(
      (
        text: null,
        key: 'submit',
        type: null,
        index: null,
        x: null,
        y: null,
        usedAt: false,
        describeRef: null,
        timeoutSeconds: 1,
      ),
      checkFdbHelperFn: () async => 'isolates/1',
      fdbTapFn: (_) async {
        calls++;
        return const FdbTapCommandResponse(
          status: null,
          error: covered,
          unexpected: null,
          widgetType: null,
          x: null,
          y: null,
          warning: null,
        );
      },
    );

    expect(result, isA<TapRelayedError>().having((e) => e.message, 'message', covered));
    expect(calls, greaterThan(1));
    expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
  });
}
