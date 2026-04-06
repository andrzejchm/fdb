import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

int _nextPointerId = 1;
const int _kDeviceId = 1;
const Duration _kDelay = Duration(milliseconds: 10);

// Process-relative monotonic clock — produces timestamps in the same epoch
// range as Flutter's frame timestamps (process uptime), which is required for
// the pointer resampler and VelocityTracker to work correctly.
// Using DateTime.now().millisecondsSinceEpoch would produce ~56-year offsets.
final Stopwatch _clock = Stopwatch()..start();

/// Dispatches a synthetic tap (or long-press) at [globalPosition].
///
/// Sends the full Add → Down → (holdDuration) → Up → Remove sequence required
/// for web platform compatibility. Pass a longer [holdDuration] (e.g. 500 ms)
/// to trigger long-press gesture recognizers.
Future<void> dispatchTap(
  Offset globalPosition, {
  Duration holdDuration = _kDelay,
}) async {
  final pointerId = _nextPointerId++;
  var timeStamp = _clock.elapsed;

  // Batch 1: Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(
        timeStamp: timeStamp, position: globalPosition, device: _kDeviceId),
  );
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
        timeStamp: timeStamp,
        pointer: pointerId,
        position: globalPosition,
        device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(holdDuration);
  timeStamp += holdDuration;

  // Batch 2: Up + Remove
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
        timeStamp: timeStamp,
        pointer: pointerId,
        position: globalPosition,
        device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(
        timeStamp: timeStamp, position: globalPosition, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}

/// Dispatches a synthetic swipe gesture from [start] to [end].
///
/// The gesture is split into steps of at most [maxStepSize] pixels to produce
/// a smooth scroll that scroll physics can respond to.
Future<void> dispatchScroll({
  required Offset start,
  required Offset end,
  double maxStepSize = 40.0,
}) async {
  final pointerId = _nextPointerId++;
  final delta = end - start;
  final distance = delta.distance;
  final stepCount = (distance / maxStepSize).ceil().clamp(1, 1000);
  final stepDelta = delta / stepCount.toDouble();
  var timeStamp = _clock.elapsed;

  // Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(
        timeStamp: timeStamp, position: start, device: _kDeviceId),
  );
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
        timeStamp: timeStamp,
        pointer: pointerId,
        position: start,
        device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);

  // Move steps
  for (int i = 1; i <= stepCount; i++) {
    timeStamp += _kDelay;
    final position = start + stepDelta * i.toDouble();
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        timeStamp: timeStamp,
        pointer: pointerId,
        position: position,
        delta: stepDelta,
        device: _kDeviceId,
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(_kDelay);
  }

  // Up + Remove
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
        timeStamp: timeStamp,
        pointer: pointerId,
        position: end,
        device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(
        timeStamp: timeStamp, position: end, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}
