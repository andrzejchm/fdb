import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

int _nextPointerId = 1;
const int _kDeviceId = 1;
const Duration _kDelay = Duration(milliseconds: 10);

/// Dispatches a synthetic tap at [globalPosition].
///
/// Sends the full Add → Down → (delay) → Up → Remove sequence required for
/// web platform compatibility.
Future<void> dispatchTap(Offset globalPosition) async {
  final pointerId = _nextPointerId++;

  // Batch 1: Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(position: globalPosition, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
        pointer: pointerId, position: globalPosition, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);

  // Batch 2: Up + Remove
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
        pointer: pointerId, position: globalPosition, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}

/// Dispatches a synthetic long-press at [globalPosition].
///
/// Holds PointerDown for [duration] before releasing, which is long enough
/// for Flutter's [LongPressGestureRecognizer] to fire (default 500 ms).
Future<void> dispatchLongPress(
  Offset globalPosition, {
  Duration duration = const Duration(milliseconds: 500),
}) async {
  final pointerId = _nextPointerId++;

  // Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(position: globalPosition, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
        pointer: pointerId, position: globalPosition, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(duration);

  // Up + Remove
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
        pointer: pointerId, position: globalPosition, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
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

  // Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(position: start, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: pointerId, position: start, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);

  // Move steps
  for (int i = 1; i <= stepCount; i++) {
    final position = start + stepDelta * i.toDouble();
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
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
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: pointerId, position: end, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(position: end, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}
