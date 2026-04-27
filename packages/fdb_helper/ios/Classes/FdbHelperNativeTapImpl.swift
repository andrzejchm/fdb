import Flutter
import UIKit

/// Injects a synthetic in-process tap at the given Flutter logical coordinates.
///
/// Uses UIKit private APIs to construct a UITouch and dispatch it through
/// UIApplication.sendEvent(), which reaches the full UIWindow hierarchy —
/// including UIAlertControllers, WKWebViews, and platform views that sit
/// outside Flutter's GestureBinding.
///
/// Private API usage is intentional: fdb_helper is a dev-only debug tool
/// and is never included in App Store / release builds.
class FdbHelperNativeTapImpl: NSObject, NativeTapApi {
  func nativeTap(x: Double, y: Double) throws {
    // UIKit APIs must run on the main thread.
    // If already on main (e.g. platform channel dispatch), run directly.
    // Otherwise dispatch sync to main — this is safe because Pigeon platform
    // channel calls in Flutter arrive on the platform thread (which IS the
    // main thread on iOS). The check guards against edge cases.
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
    let point = CGPoint(x: x, y: y)

    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
      ?? UIApplication.shared.windows.first
    else {
      throw PigeonError(code: "NO_WINDOW", message: "No UIWindow found", details: nil)
    }

    // Allocate a UITouch via its private initializer using the ObjC runtime.
    // The selector `initAtPoint:relativeToWindow:` is used by EarlGrey and KIF.
    let touchSel = NSSelectorFromString("initAtPoint:relativeToWindow:")
    guard let touchClass = NSClassFromString("UITouch") else {
      throw PigeonError(code: "ALLOC_FAILED", message: "Could not find UITouch class", details: nil)
    }

    let rawTouch = touchClass.alloc() as AnyObject

    let touch: UITouch
    if rawTouch.responds(to: touchSel) {
      let pointValue = NSValue(cgPoint: point)
      _ = rawTouch.perform(touchSel, with: pointValue, with: window)
      guard let uiTouch = rawTouch as? UITouch else {
        throw PigeonError(code: "CAST_FAILED", message: "Could not cast to UITouch", details: nil)
      }
      touch = uiTouch
    } else {
      throw PigeonError(
        code: "INIT_FAILED",
        message: "UITouch does not respond to initAtPoint:relativeToWindow:",
        details: nil
      )
    }

    let ts = ProcessInfo.processInfo.systemUptime
    setTouchProperty(touch, sel: "setTimestamp:", value: NSNumber(value: ts))
    setTouchProperty(touch, sel: "setWindow:", value: window)

    let hitView = window.hitTest(point, with: nil) ?? window
    setTouchProperty(touch, sel: "setView:", value: hitView)

    let locationSel = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
    let pointValue = NSValue(cgPoint: point)
    if touch.responds(to: locationSel) {
      touch.perform(locationSel, with: pointValue, with: NSNumber(value: true))
    }

    setTouchProperty(touch, sel: "setTapCount:", value: NSNumber(value: 1))
    setTouchProperty(touch, sel: "setIsTap:", value: NSNumber(value: true))

    let eventSel = NSSelectorFromString("_touchesEvent")
    guard UIApplication.shared.responds(to: eventSel),
      let event = UIApplication.shared.perform(eventSel)?.takeUnretainedValue() as? UIEvent
    else {
      throw PigeonError(code: "NO_EVENT", message: "Could not get _touchesEvent", details: nil)
    }

    let addTouchSel = NSSelectorFromString("_addTouch:forDelayedDelivery:")
    let clearSel = NSSelectorFromString("_clearTouches")

    // Began
    setTouchProperty(touch, sel: "setPhase:", value: NSNumber(value: UITouch.Phase.began.rawValue))
    if event.responds(to: addTouchSel) {
      event.perform(addTouchSel, with: touch, with: NSNumber(value: false))
    }
    UIApplication.shared.sendEvent(event)

    // Ended
    Thread.sleep(forTimeInterval: 0.05)
    setTouchProperty(touch, sel: "setPhase:", value: NSNumber(value: UITouch.Phase.ended.rawValue))
    if touch.responds(to: locationSel) {
      touch.perform(locationSel, with: pointValue, with: NSNumber(value: false))
    }
    UIApplication.shared.sendEvent(event)

    // Clear
    if event.responds(to: clearSel) {
      event.perform(clearSel)
    }
  }

  private func setTouchProperty(_ touch: UITouch, sel selStr: String, value: AnyObject) {
    let sel = NSSelectorFromString(selStr)
    if touch.responds(to: sel) {
      touch.perform(sel, with: value)
    }
  }
}
