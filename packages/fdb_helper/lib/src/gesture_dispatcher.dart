import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'native_tap.g.dart';

int _nextPointerId = 1;
const int _kDeviceId = 1;
const Duration _kDelay = Duration(milliseconds: 10);
const Duration _kDoubleTapGap = Duration(milliseconds: 100);
const Duration _kDoubleTapHold = Duration(milliseconds: 50);

// Process-relative monotonic clock — produces timestamps in the same epoch
// range as Flutter's frame timestamps (process uptime), which is required for
// the pointer resampler and VelocityTracker to work correctly.
// Using DateTime.now().millisecondsSinceEpoch would produce ~56-year offsets.
final Stopwatch _clock = Stopwatch()..start();

PointerDeviceKind _tapPointerKind() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => PointerDeviceKind.mouse,
    _ => PointerDeviceKind.touch,
  };
}

int _tapButtons(PointerDeviceKind kind) {
  return kind == PointerDeviceKind.mouse ? kPrimaryMouseButton : kPrimaryButton;
}

/// Result of [dispatchNativeTap], indicating which path actually delivered
/// the tap. Callers can surface this to the user so they know whether
/// native overlays (UIAlertController, AlertDialog, WebView) were reachable.
enum NativeTapResult {
  /// The native in-process injection path delivered the tap.
  /// Native overlays were reachable.
  native,

  /// The platform has no native tap implementation (web, Linux, Windows,
  /// tests). Tap was dispatched via Flutter's GestureBinding. Native
  /// overlays are unreachable from those platforms by design.
  unsupportedPlatform,

  /// Native injection failed on a platform that nominally supports it.
  /// Tap was dispatched via Flutter's GestureBinding so Flutter widgets
  /// still work, but native overlays did NOT receive the tap. The cause
  /// is logged via [debugPrint].
  nativeFailedFallback,
}

/// Dispatches a native in-process tap at [globalPosition] via the platform
/// channel, bypassing Flutter's [GestureBinding].
///
/// Routes through the platform's own input dispatch:
///   iOS     — UIApplication.sendEvent() with synthetic UITouch
///   macOS   — NSApplication.sendEvent() with synthetic NSEvent
///   Android — Activity.dispatchTouchEvent() with synthetic MotionEvent
///
/// This reaches native views overlaid on the Flutter surface
/// (UIAlertController, WKWebView, platform views, AlertDialog) that
/// [dispatchTap] cannot reach.
///
/// Returns [NativeTapResult] indicating which path actually delivered the tap.
/// Falls back to [dispatchTap] (Flutter's [GestureBinding]) on:
///   - Platforms without a native impl: web, Linux, Windows. The
///     `fdb_helper` plugin only declares iOS, Android, and macOS in its
///     `pubspec.yaml`, so other platforms cannot have a NativeTapApi
///     implementation registered. Native overlays do not exist on web/Linux/
///     Windows in a way that Flutter doesn't already handle, so this is
///     correct by design — but it does mean callers should treat the
///     [NativeTapResult.unsupportedPlatform] result as an informational
///     signal, not an error.
///   - Native injection failures on a supported platform (e.g. iOS private
///     API drift): debugPrint a warning and return
///     [NativeTapResult.nativeFailedFallback] so callers can surface this
///     to users. Flutter widgets still work via the fallback; native
///     overlays do NOT.
Future<NativeTapResult> dispatchNativeTap(Offset globalPosition) async {
  final platform = defaultTargetPlatform;
  final hasNativeImpl =
      platform == TargetPlatform.iOS || platform == TargetPlatform.android || platform == TargetPlatform.macOS;
  if (!hasNativeImpl || kIsWeb) {
    await dispatchTap(globalPosition);
    return NativeTapResult.unsupportedPlatform;
  }

  try {
    await NativeTapApi().nativeTap(globalPosition.dx, globalPosition.dy);
    return NativeTapResult.native;
  } catch (e) {
    debugPrint(
      '[fdb_helper] native tap failed on $platform, falling back to '
      'GestureBinding (native overlays will NOT receive this tap): $e',
    );
    await dispatchTap(globalPosition);
    return NativeTapResult.nativeFailedFallback;
  }
}

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
  final kind = _tapPointerKind();
  final buttons = _tapButtons(kind);

  // Batch 1: Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(
      timeStamp: timeStamp,
      position: globalPosition,
      device: _kDeviceId,
      kind: kind,
    ),
  );
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      timeStamp: timeStamp,
      pointer: pointerId,
      position: globalPosition,
      device: _kDeviceId,
      kind: kind,
      buttons: buttons,
    ),
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
      device: _kDeviceId,
      kind: kind,
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(
      timeStamp: timeStamp,
      position: globalPosition,
      device: _kDeviceId,
      kind: kind,
    ),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}

/// Dispatches a native in-process long-press at [globalPosition] for
/// [holdDuration] via the platform channel, bypassing Flutter's
/// [GestureBinding].
///
/// Routes through the platform's own input dispatch, holding the touch/pointer
/// down for [holdDuration] before releasing:
///   iOS     — UITouchPhaseStationary pulses at 10 ms intervals between Began and Ended
///   macOS   — NSEvent delay between leftMouseDown and leftMouseUp
///   Android — MotionEvent DOWN held for [holdDuration], then UP
///
/// This reaches native views overlaid on the Flutter surface
/// (UIAlertController, WKWebView, platform views, AlertDialog) that
/// [dispatchTap] cannot reach.
///
/// Returns [NativeTapResult] indicating which path actually delivered the
/// long-press. Falls back to [dispatchTap] with [holdDuration] on:
///   - Platforms without a native impl: web, Linux, Windows.
///   - Native injection failures on a supported platform.
Future<NativeTapResult> dispatchNativeLongPress(
  Offset globalPosition, {
  Duration holdDuration = const Duration(milliseconds: 500),
}) async {
  final platform = defaultTargetPlatform;
  final hasNativeImpl =
      platform == TargetPlatform.iOS || platform == TargetPlatform.android || platform == TargetPlatform.macOS;
  if (!hasNativeImpl || kIsWeb) {
    await dispatchTap(globalPosition, holdDuration: holdDuration);
    return NativeTapResult.unsupportedPlatform;
  }

  try {
    await NativeTapApi().nativeLongPress(
      globalPosition.dx,
      globalPosition.dy,
      holdDuration.inMilliseconds,
    );
    return NativeTapResult.native;
  } catch (e) {
    debugPrint(
      '[fdb_helper] native long-press failed on $platform, falling back to '
      'GestureBinding (native overlays will NOT receive this long-press): $e',
    );
    await dispatchTap(globalPosition, holdDuration: holdDuration);
    return NativeTapResult.nativeFailedFallback;
  }
}

/// Dispatches two taps in quick succession at the same [globalPosition].
Future<void> dispatchDoubleTap(Offset globalPosition) async {
  if (_tapPointerKind() == PointerDeviceKind.mouse) {
    await _dispatchMouseDoubleTap(globalPosition);
    return;
  }

  await dispatchTap(globalPosition, holdDuration: _kDoubleTapHold);
  await Future<void>.delayed(_kDoubleTapGap);
  await dispatchTap(globalPosition, holdDuration: _kDoubleTapHold);
}

Future<void> _dispatchMouseDoubleTap(Offset globalPosition) async {
  final pointerId = _nextPointerId++;
  var timeStamp = _clock.elapsed;
  final buttons = _tapButtons(PointerDeviceKind.mouse);

  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(
      timeStamp: timeStamp,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
    ),
  );

  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      timeStamp: timeStamp,
      pointer: pointerId,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    ),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDoubleTapHold);

  timeStamp += _kDoubleTapHold;
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      timeStamp: timeStamp,
      pointer: pointerId,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
    ),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDoubleTapGap);

  timeStamp += _kDoubleTapGap;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      timeStamp: timeStamp,
      pointer: pointerId,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    ),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDoubleTapHold);

  timeStamp += _kDoubleTapHold;
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      timeStamp: timeStamp,
      pointer: pointerId,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(
      timeStamp: timeStamp,
      position: globalPosition,
      device: _kDeviceId,
      kind: PointerDeviceKind.mouse,
    ),
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
    PointerAddedEvent(timeStamp: timeStamp, position: start, device: _kDeviceId),
  );
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(timeStamp: timeStamp, pointer: pointerId, position: start, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);

  // Move steps
  for (var i = 1; i <= stepCount; i++) {
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
    PointerUpEvent(timeStamp: timeStamp, pointer: pointerId, position: end, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(timeStamp: timeStamp, position: end, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}

/// Dispatches a synthetic multi-point swipe gesture following [points] as a
/// single continuous pointer path.
///
/// Unlike [dispatchScroll], which drags between exactly two points, this
/// interpolates PointerMoveEvents across every consecutive pair in [points]
/// under one continuous pointer id and timestamp stream — producing a single
/// unbroken gesture (e.g. an L-shape or a curve approximated by a polyline)
/// instead of several disjoint drags.
///
/// Each segment is split into steps of at most [maxStepSize] pixels, using
/// the same step-count math as [dispatchScroll], so gesture recognizers see
/// a smooth path they can respond to.
Future<void> dispatchPath({
  required List<Offset> points,
  double maxStepSize = 40.0,
}) async {
  assert(points.length >= 2, 'dispatchPath requires at least 2 points');

  final pointerId = _nextPointerId++;
  var timeStamp = _clock.elapsed;
  final start = points.first;
  final end = points.last;

  // Add + Down
  GestureBinding.instance.handlePointerEvent(
    PointerAddedEvent(timeStamp: timeStamp, position: start, device: _kDeviceId),
  );
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(timeStamp: timeStamp, pointer: pointerId, position: start, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);

  // Move steps, per segment, continuing the same pointer id and clock.
  for (var segment = 0; segment < points.length - 1; segment++) {
    final segmentStart = points[segment];
    final segmentEnd = points[segment + 1];
    final delta = segmentEnd - segmentStart;
    final distance = delta.distance;
    final stepCount = (distance / maxStepSize).ceil().clamp(1, 1000);
    final stepDelta = delta / stepCount.toDouble();

    for (var i = 1; i <= stepCount; i++) {
      timeStamp += _kDelay;
      final position = segmentStart + stepDelta * i.toDouble();
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
  }

  // Up + Remove
  timeStamp += _kDelay;
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(timeStamp: timeStamp, pointer: pointerId, position: end, device: _kDeviceId),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerRemovedEvent(timeStamp: timeStamp, position: end, device: _kDeviceId),
  );
  WidgetsBinding.instance.scheduleFrame();
  await Future<void>.delayed(_kDelay);
}
