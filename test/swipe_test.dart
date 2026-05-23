import 'package:fdb/core/commands/swipe/swipe.dart';
import 'package:fdb/src/controller/commands/fdb_swipe.dart';
import 'package:test/test.dart';

void main() {
  group('runSwipe', () {
    test('preserves lower-case direction in success result', () async {
      final result = await runSwipe(
        (
          direction: 'left',
          key: null,
          text: null,
          type: null,
          at: null,
          distance: 250,
        ),
        checkFdbHelperFn: () async => 'isolates/1',
        fdbSwipeFn: (_) async => const FdbSwipeCommandResponse(
          status: 'Success',
          error: null,
          unexpected: null,
          distance: 250,
        ),
      );

      expect(result, isA<SwipeSuccess>().having((success) => success.direction, 'direction', 'left'));
    });
  });
}
