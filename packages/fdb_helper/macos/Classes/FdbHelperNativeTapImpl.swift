import Cocoa
import FlutterMacOS

/// Injects a synthetic in-process mouse click at the given Flutter logical coordinates.
///
/// Flutter logical coordinates have their origin at the top-left of the content view.
/// NSEvent uses AppKit coordinates with the origin at the bottom-left of the content view,
/// so we flip the y-axis before constructing the event.
///
/// NSApplication.shared.sendEvent() routes through the full AppKit responder chain,
/// reaching native NSViews (WebViews, platform views, native dialogs presented
/// within the app process) that Flutter's GestureBinding cannot reach.
class FdbHelperNativeTapImpl: NSObject, NativeTapApi {
  func nativeTap(x: Double, y: Double) throws {
    guard let window = NSApplication.shared.keyWindow
      ?? NSApplication.shared.windows.first(where: { $0.isVisible })
    else {
      throw PigeonError(code: "NO_WINDOW", message: "No NSWindow found", details: nil)
    }

    // Flutter logical coords: origin top-left.
    // AppKit window coords: origin bottom-left of contentView.
    let contentHeight = window.contentView?.bounds.height ?? window.frame.height
    let windowPoint = CGPoint(x: x, y: contentHeight - y)

    let ts = ProcessInfo.processInfo.systemUptime

    guard let down = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: [],
      timestamp: ts,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1.0
    ) else {
      throw PigeonError(code: "EVENT_FAILED", message: "Could not create NSEvent mouseDown", details: nil)
    }

    guard let up = NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: windowPoint,
      modifierFlags: [],
      timestamp: ts + 0.05,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 0.0
    ) else {
      throw PigeonError(code: "EVENT_FAILED", message: "Could not create NSEvent mouseUp", details: nil)
    }

    NSApplication.shared.sendEvent(down)
    Thread.sleep(forTimeInterval: 0.05)
    NSApplication.shared.sendEvent(up)
  }
}
