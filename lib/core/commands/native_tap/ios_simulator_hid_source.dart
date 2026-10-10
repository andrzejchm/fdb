/// Swift source of the iOS simulator HID helper used by `fdb native-tap`.
///
/// fdb compiles this once with `xcrun swiftc` and caches the binary (see
/// `ios_simulator_hid.dart`). The helper injects touches through SimulatorKit's
/// legacy Indigo HID client, so taps reach SpringBoard system dialogs too.
///
/// The cache key is a hash of this string plus the compiler flags: any change
/// here, even whitespace, produces a new binary on the next run.
///
/// Coordinates are in the current interface orientation; the helper reads it
/// from the simulator and rotates the point into the portrait frame the HID
/// stack expects.
///
/// Exit codes: 0 tapped, 1 failure, 2 usage error, 3 coordinates outside the
/// screen, 4 touch partially delivered, 5 interface orientation unknown.
const iosSimulatorHidSource = r'''// fdb iOS simulator HID helper.
//
// Injects touches into a booted iOS simulator through SimulatorKit's legacy
// Indigo HID client, the same path Simulator.app and idb use. The touch goes
// through the simulator's HID stack, so it reaches every process on screen,
// including SpringBoard (permission prompts, "Open in <App>?", paste prompt).
//
// Usage: <binary> tap <developer-dir> <udid> <x> <y>
//   x, y are in points in the current interface orientation, the same frame
//   screenshots and `fdb tap` use.
// Exit codes: 0 tapped, 1 failure (message on stderr), 2 usage error,
//   3 coordinates outside the screen, 4 touch partially delivered (the touch
//   down may have reached the simulator but the touch up did not),
//   5 interface orientation unknown (nothing sent).
//
// The message layout mirrors facebook/idb (FBSimulatorIndigoHID). A single
// multi-touch message straight from IndigoHIDMessageForMouseNSEvent is
// silently ignored, so the touch is copied into a two-payload single-touch
// envelope.

import CoreGraphics
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write("ERROR: \(message)\n".data(using: .utf8)!)
  exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 6, arguments[1] == "tap" else {
  fail("usage: \(arguments.first ?? "helper") tap <developer-dir> <udid> <x> <y>", code: 2)
}
let developerDir = arguments[2]
let udid = arguments[3].uppercased()
guard let x = Double(arguments[4]), let y = Double(arguments[5]) else {
  fail("invalid coordinates \(arguments[4]),\(arguments[5])", code: 2)
}

guard dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW) != nil else {
  fail("could not load CoreSimulator.framework")
}
// Xcode 26 and earlier ship SimulatorKit under Developer/Library/PrivateFrameworks,
// Xcode 27 moved it to Contents/SharedFrameworks.
let simulatorKitPaths = [
  "\(developerDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
  "\(developerDir)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit",
]
guard let simulatorKit = simulatorKitPaths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first else {
  fail("could not load SimulatorKit.framework from \(developerDir)")
}

let runtime = dlopen(nil, RTLD_NOW)
guard let msgSend = dlsym(runtime, "objc_msgSend") else { fail("objc_msgSend not found") }
typealias MsgSendStringError = @convention(c) (AnyObject, Selector, NSString, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias MsgSendError = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias MsgSendObjectError = @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias MsgSendHid = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer, Bool, AnyObject?, AnyObject?) -> Void
let sendStringError = unsafeBitCast(msgSend, to: MsgSendStringError.self)
let sendError = unsafeBitCast(msgSend, to: MsgSendError.self)
let sendObjectError = unsafeBitCast(msgSend, to: MsgSendObjectError.self)
let sendHid = unsafeBitCast(msgSend, to: MsgSendHid.self)

typealias MouseMessageFn = @convention(c) (
  UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<CGPoint>?, Int32, UInt, Bool
) -> UnsafeMutableRawPointer
guard let mouseMessagePointer = dlsym(simulatorKit, "IndigoHIDMessageForMouseNSEvent") else {
  fail("IndigoHIDMessageForMouseNSEvent not found in SimulatorKit")
}
let mouseMessage = unsafeBitCast(mouseMessagePointer, to: MouseMessageFn.self)

var error: NSError?
guard let contextClass = NSClassFromString("SimServiceContext"),
  let context = sendStringError(
    contextClass, NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"), developerDir as NSString, &error
  ) as? NSObject,
  let deviceSet = sendError(context, NSSelectorFromString("defaultDeviceSetWithError:"), &error) as? NSObject,
  let devices = deviceSet.value(forKey: "devices") as? [NSObject]
else {
  fail("CoreSimulator init failed: \(error?.localizedDescription ?? "unknown error")")
}

guard let device = devices.first(where: { ($0.value(forKey: "UDID") as? NSUUID)?.uuidString == udid }) else {
  fail("simulator \(udid) not found")
}
guard (device.value(forKey: "state") as? Int) == 3 else {
  fail("simulator \(udid) is not booted")
}

guard let deviceType = device.value(forKey: "deviceType") as? NSObject,
  let screenSize = (deviceType.value(forKey: "mainScreenSize") as? NSValue)?.sizeValue,
  let screenScale = (deviceType.value(forKey: "mainScreenScale") as? NSNumber)?.doubleValue,
  screenSize.width > 0, screenSize.height > 0, screenScale > 0
else {
  fail("could not read the simulator screen size")
}
// Portrait size of the screen in points. The HID touch is a ratio of this
// portrait frame whatever way the simulator is rotated.
let widthPoints = Double(screenSize.width) / screenScale
let heightPoints = Double(screenSize.height) / screenScale

// Interface orientation of the main screen, as the guest reports it to the
// host (the same value Simulator.app and `simctl io screenshot` rotate by).
// It follows what is on screen: an app or SpringBoard that does not rotate
// keeps reporting portrait even when the device is turned.
// Values: 1 portrait, 2 portraitUpsideDown, 3 landscapeRight, 4 landscapeLeft
// (devicectl naming). Returns nil when it cannot be read.
typealias MsgSendUInt32 = @convention(c) (AnyObject, Selector) -> UInt32
let sendUInt32 = unsafeBitCast(msgSend, to: MsgSendUInt32.self)

func mainScreenOrientation() -> UInt32? {
  guard let io = device.perform(NSSelectorFromString("io"))?.takeUnretainedValue() as? NSObject,
    let ports = io.value(forKey: "ioPorts") as? [NSObject]
  else { return nil }
  var fallback: UInt32?
  for port in ports {
    guard port.responds(to: NSSelectorFromString("descriptor")),
      let descriptor = port.perform(NSSelectorFromString("descriptor"))?.takeUnretainedValue() as? NSObject,
      descriptor.responds(to: NSSelectorFromString("screenProperties")),
      let properties = descriptor.perform(NSSelectorFromString("screenProperties"))?.takeUnretainedValue()
        as? NSObject,
      properties.responds(to: NSSelectorFromString("uiOrientation"))
    else { continue }
    let orientation = sendUInt32(properties, NSSelectorFromString("uiOrientation"))
    // The properties are a remote proxy without KVC, so call the getters.
    if properties.responds(to: NSSelectorFromString("uniqueId")),
      (properties.perform(NSSelectorFromString("uniqueId"))?.takeUnretainedValue() as? String) == "PurpleMain"
    {
      return orientation
    }
    if properties.responds(to: NSSelectorFromString("screenID")),
      sendUInt32(properties, NSSelectorFromString("screenID")) == 1
    {
      fallback = orientation
    }
  }
  return fallback
}

let orientationNames: [UInt32: String] = [
  1: "portrait", 2: "portraitUpsideDown", 3: "landscapeRight", 4: "landscapeLeft",
]
// No orientation API at all (older CoreSimulator): nothing was sent, so this
// is a plain failure and fdb falls back to the in-process tap, whose
// coordinates are right in any orientation.
guard let orientation = mainScreenOrientation() else {
  fail("could not read the simulator interface orientation")
}
// A value we do not know how to map: refuse rather than tap a wrong spot.
guard let orientationName = orientationNames[orientation] else {
  fail(
    "native-tap can't tell which way the simulator is rotated (interface orientation \(orientation)); "
      + "rotate it to portrait and try again",
    code: 5
  )
}

// x, y are in the rotated frame (what screenshots and `fdb tap` use); its
// size swaps width and height in landscape.
let landscape = orientation == 3 || orientation == 4
let frameWidth = landscape ? heightPoints : widthPoints
let frameHeight = landscape ? widthPoints : heightPoints
guard x >= 0, y >= 0, x <= frameWidth, y <= frameHeight else {
  fail(
    "coordinates \(x),\(y) are outside the screen (\(frameWidth)x\(frameHeight) points, \(orientationName))",
    code: 3
  )
}

// Rotate the point into the portrait frame. Keep in sync with
// `iosSimulatorPortraitPoint` in ios_simulator_hid.dart (unit tested there).
let portraitX: Double
let portraitY: Double
switch orientation {
case 2:
  portraitX = widthPoints - x
  portraitY = heightPoints - y
case 3:
  portraitX = y
  portraitY = heightPoints - x
case 4:
  portraitX = widthPoints - y
  portraitY = x
default:
  portraitX = x
  portraitY = y
}

guard let hidClass = NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient") as AnyObject?,
  let hidAllocated = hidClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
  let hid = sendObjectError(hidAllocated, NSSelectorFromString("initWithDevice:error:"), device, &error)
else {
  fail("could not create the HID client: \(error?.localizedDescription ?? "unknown error")")
}

// Indigo message layout (offsets in bytes):
//   0x18 innerSize, 0x1c eventType, 0x20 payload (0x90 bytes):
//   payload+0x00 field1, +0x04 timestamp, +0x10 touch event (xRatio at +0x1c, yRatio at +0x24).
let messageSize = 0x140
let payloadOffset = 0x20
let payloadSize = 0x90
let touchOffset = 0x30
let touchSize = 0x80
let secondPayloadOffset = payloadOffset + payloadSize
let touchTarget: Int32 = 0x32
let eventTypeTouch: UInt8 = 0x02

let ratio = CGPoint(x: portraitX / widthPoints, y: portraitY / heightPoints)

func touchMessage(down: Bool) -> UnsafeMutableRawPointer {
  var point = ratio
  // NSEventType is NSUInteger: 1 = leftMouseDown, 2 = leftMouseUp.
  let source = mouseMessage(&point, nil, touchTarget, down ? UInt(1) : UInt(2), false)
  source.storeBytes(of: Double(ratio.x), toByteOffset: 0x3c, as: Double.self)
  source.storeBytes(of: Double(ratio.y), toByteOffset: 0x44, as: Double.self)

  let message = calloc(1, messageSize)!
  message.storeBytes(of: UInt32(payloadSize), toByteOffset: 0x18, as: UInt32.self)
  message.storeBytes(of: eventTypeTouch, toByteOffset: 0x1c, as: UInt8.self)
  message.storeBytes(of: UInt32(0x0b), toByteOffset: payloadOffset, as: UInt32.self)
  var timestamp = mach_absolute_time()
  memcpy(message + payloadOffset + 0x04, &timestamp, MemoryLayout<UInt64>.size)
  memcpy(message + touchOffset, source + touchOffset, touchSize)
  memcpy(message + secondPayloadOffset, message + payloadOffset, payloadSize)
  message.storeBytes(of: UInt32(1), toByteOffset: secondPayloadOffset + 0x10, as: UInt32.self)
  message.storeBytes(of: UInt32(2), toByteOffset: secondPayloadOffset + 0x14, as: UInt32.self)
  free(source)
  return message
}

let completionQueue = DispatchQueue(label: "fdb.ios-simulator-hid")

enum SendOutcome {
  case sent
  case failed(String)
  case timedOut
}

func send(_ message: UnsafeMutableRawPointer) -> SendOutcome {
  let done = DispatchSemaphore(value: 0)
  var sendFailure: NSError?
  let completion: @convention(block) (NSError?) -> Void = { error in
    sendFailure = error
    done.signal()
  }
  sendHid(
    hid,
    NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:"),
    message,
    true,
    completionQueue,
    completion as AnyObject
  )
  if done.wait(timeout: .now() + 5) == .timedOut {
    return .timedOut
  }
  if let sendFailure {
    return .failed(sendFailure.localizedDescription)
  }
  return .sent
}

// A touch down that went out without its touch up leaves a finger stuck on
// the screen, so the up is retried once and a failure after the down is
// reported with its own exit code (callers must not retry the tap elsewhere).
func sendTouchUp(afterDownProblem downProblem: String?) {
  var lastProblem = ""
  for _ in 0..<2 {
    switch send(touchMessage(down: false)) {
    case .sent:
      if let downProblem {
        fail("touch partially delivered: \(downProblem)", code: 4)
      }
      return
    case .failed(let message):
      lastProblem = "sending the touch up failed: \(message)"
    case .timedOut:
      lastProblem = "timed out sending the touch up to the simulator"
    }
  }
  fail("touch partially delivered: \(downProblem ?? lastProblem)", code: 4)
}

switch send(touchMessage(down: true)) {
case .sent:
  Thread.sleep(forTimeInterval: 0.05)
  sendTouchUp(afterDownProblem: nil)
case .failed(let message):
  fail("sending the touch failed: \(message)")
case .timedOut:
  // The down may still have been delivered; release it before reporting.
  sendTouchUp(afterDownProblem: "timed out sending the touch down to the simulator")
}
print("TAPPED x=\(x) y=\(y) screen=\(frameWidth)x\(frameHeight) orientation=\(orientationName)")
''';
