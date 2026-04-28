import Flutter
import UIKit

/// Injects a synthetic in-process tap at the given Flutter logical
/// coordinates by delegating to the ObjC implementation in
/// `FdbHelperNativeTap.m`. The ObjC layer mirrors KIF v3.12.2's tap
/// injection (the only iOS 26-compatible in-process approach as of
/// mid-2026 — see KIF PR #1334 for the per-phase UIEvent fix).
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
}
