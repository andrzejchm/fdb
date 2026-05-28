import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/native_tap.g.dart',
    swiftOut: 'ios/Classes/NativeTap.g.swift',
    kotlinOut: 'android/src/main/kotlin/io/fdb/fdb_helper/NativeTap.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.fdb.fdb_helper'),
  ),
)
@HostApi()
abstract class NativeTapApi {
  void nativeTap(double x, double y);

  /// Performs a long-press at ([x], [y]) for [durationMs] milliseconds.
  ///
  /// The implementation must hold the touch/pointer DOWN for at least
  /// [durationMs] before sending the UP event. The exact mechanism is
  /// platform-specific:
  ///   iOS  — UITouchPhaseStationary pulses at 10ms intervals between Began and Ended
  ///   Android — MotionEvent timestamps advanced by [durationMs]
  ///   macOS  — NSEvent delay between leftMouseDown and leftMouseUp
  void nativeLongPress(double x, double y, int durationMs);
}
