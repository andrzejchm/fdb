import Flutter
import UIKit

#if FDB_HELPER_NATIVE_TAP_REAL

/// Injects a synthetic in-process tap or long-press at the given Flutter logical
/// coordinates by delegating to the ObjC implementation in
/// `FdbHelperNativeTap.m`. The ObjC layer mirrors KIF v3.12.2's tap/long-press
/// injection (the only iOS 26-compatible in-process approach as of mid-2026 —
/// see KIF PR #1334 for the per-phase UIEvent fix).
///
/// The implementation lives in ObjC because the surrounding code uses
/// many private UIKit / IOKit APIs whose C signatures (struct-by-value,
/// 17-argument digitizer event creation, runtime ivar manipulation)
/// cannot be expressed cleanly through Swift's `@convention(c)` + dlsym
/// path.
class FdbHelperNativeTapImpl: NSObject, NativeTapApi {
  func nativeTap(x: Double, y: Double) throws {
    if Thread.isMainThread {
      try _doTap(x: x, y: y)
    } else {
      var tapError: Error?
      DispatchQueue.main.sync {
        do {
          try self._doTap(x: x, y: y)
        } catch {
          tapError = error
        }
      }
      if let err = tapError { throw err }
    }
  }

  func nativeLongPress(x: Double, y: Double, durationMs: Int64) throws {
    if Thread.isMainThread {
      try _doLongPress(x: x, y: y, durationMs: durationMs)
    } else {
      var tapError: Error?
      DispatchQueue.main.sync {
        do {
          try self._doLongPress(x: x, y: y, durationMs: durationMs)
        } catch {
          tapError = error
        }
      }
      if let err = tapError { throw err }
    }
  }

  private func _doTap(x: Double, y: Double) throws {
    var nsError: NSError?
    let success = FdbHelperNativeTapAtPoint(CGPoint(x: x, y: y), &nsError)
    if !success {
      throw PigeonError(
        code: "NATIVE_TAP_FAILED",
        message: nsError?.localizedDescription ?? "Native tap failed",
        details: nil
      )
    }
  }

  private func _doLongPress(x: Double, y: Double, durationMs: Int64) throws {
    var nsError: NSError?
    let durationSeconds = Double(durationMs) / 1000.0
    let success = FdbHelperNativeLongPressAtPoint(CGPoint(x: x, y: y), durationSeconds, &nsError)
    if !success {
      throw PigeonError(
        code: "NATIVE_LONG_PRESS_FAILED",
        message: nsError?.localizedDescription ?? "Native long-press failed",
        details: nil
      )
    }
  }
}

#else

/// Safe fallback compiled into release Apple builds.
class FdbHelperNativeTapImpl: NSObject, NativeTapApi {
  func nativeTap(x: Double, y: Double) throws {
    throw PigeonError(
      code: "UNAVAILABLE_IN_RELEASE",
      message: "Native tap is disabled in release builds of fdb_helper",
      details: nil,
    )
  }

  func nativeLongPress(x: Double, y: Double, durationMs: Int64) throws {
    throw PigeonError(
      code: "UNAVAILABLE_IN_RELEASE",
      message: "Native long-press is disabled in release builds of fdb_helper",
      details: nil,
    )
  }
}

#endif
