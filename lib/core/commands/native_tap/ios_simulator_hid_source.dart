/// Swift source of the iOS simulator HID helper used by `fdb native-tap`.
///
/// fdb compiles this once with `xcrun swiftc` and caches the binary (see
/// `ios_simulator_hid.dart`). The helper injects touches through SimulatorKit's
/// legacy Indigo HID client, so taps reach SpringBoard system dialogs too.
/// Its `describe` subcommand reads the accessibility tree of whatever is in
/// front (an app, or SpringBoard while an alert is up) for `--text`.
///
/// The cache key is a hash of this string plus the compiler flags: any change
/// here, even whitespace, produces a new binary on the next run.
///
/// Coordinates are in the current interface orientation; the helper reads it
/// from the simulator and rotates the point into the portrait frame the HID
/// stack expects.
///
/// Exit codes: 0 tapped (or described), 1 failure, 2 usage error,
/// 3 coordinates outside the screen, 4 touch partially delivered,
/// 5 interface orientation unknown.
///
/// `describe` prints one JSON document on stdout, parsed by
/// `parseIosSimulatorAccessibility` in `ios_simulator_accessibility.dart`.
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
// Usage: <binary> describe <developer-dir> <udid>
//   Prints the accessibility elements of the frontmost application as JSON,
//   frames in points in the current interface orientation (see describe below).
// Exit codes: 0 tapped / described, 1 failure (message on stderr), 2 usage error,
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
let isTap = arguments.count == 6 && arguments[1] == "tap"
let isDescribe = arguments.count == 4 && arguments[1] == "describe"
guard isTap || isDescribe else {
  let name = arguments.first ?? "helper"
  fail("usage: \(name) tap <developer-dir> <udid> <x> <y> | \(name) describe <developer-dir> <udid>", code: 2)
}
let developerDir = arguments[2]
let udid = arguments[3].uppercased()
let x: Double
let y: Double
if isTap {
  guard let parsedX = Double(arguments[4]), let parsedY = Double(arguments[5]) else {
    fail("invalid coordinates \(arguments[4]),\(arguments[5])", code: 2)
  }
  x = parsedX
  y = parsedY
} else {
  x = 0
  y = 0
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
  // Check every selector first: messaging a missing one raises and aborts.
  guard device.responds(to: NSSelectorFromString("io")),
    let io = device.perform(NSSelectorFromString("io"))?.takeUnretainedValue() as? NSObject,
    io.responds(to: NSSelectorFromString("ioPorts")),
    let ports = io.perform(NSSelectorFromString("ioPorts"))?.takeUnretainedValue() as? [NSObject]
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
      + "wait a moment and try again, or rotate it to portrait",
    code: 5
  )
}

// x, y are in the rotated frame (what screenshots and `fdb tap` use); its
// size swaps width and height in landscape.
let landscape = orientation == 3 || orientation == 4
let frameWidth = landscape ? heightPoints : widthPoints
let frameHeight = landscape ? widthPoints : heightPoints

// MARK: describe

// Reads the accessibility tree of the frontmost application through the
// private AccessibilityPlatformTranslation framework, the way Simulator.app's
// accessibility support and facebook/idb's describe-all do. While a
// SpringBoard alert is up the frontmost application is SpringBoard, so the
// elements are the alert's.
//
// The AXPTranslator singleton asks a "bridge token delegate" for a callback;
// the callback forwards each AXPTranslatorRequest to
// -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]
// and blocks until the response arrives.
//
// Output, one JSON object with sorted keys:
//   {"orientation": "portrait", "screen": {"width": W, "height": H}, "complete": true,
//    "elements": [{"label", "role", "identifier"?, "value"?, "enabled",
//                  "pid", "depth", "frame": {"x", "y", "width", "height"} | null}]}
// Elements are in depth-first order, the application element first. Frames
// are in points in the current interface orientation (W x H), the frame the
// tap command takes. A frame is null when it could not be mapped there.
// "elements" is empty when there is no frontmost application yet.
// "complete" is false when an accessibility request timed out or the walk
// stopped at the element or depth cap, so elements may be missing.
//
// Only object, BOOL and integer returns go through objc_msgSend. Struct
// returns such as accessibilityFrame are read with KVC, which boxes them in
// NSValue: on x86_64 a CGRect return would need objc_msgSend_stret.

typealias SendAXRequestFn = @convention(c) (AnyObject, Selector, AnyObject, DispatchQueue, AnyObject) -> Void
typealias FrontmostFn = @convention(c) (AnyObject, Selector, UInt32, NSString) -> AnyObject?
typealias ObjectAtPointFn = @convention(c) (AnyObject, Selector, CGPoint, UInt32, NSString) -> AnyObject?
typealias ObjectToObjectFn = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
typealias ObjectGetterFn = @convention(c) (AnyObject, Selector) -> AnyObject?
typealias BoolGetterFn = @convention(c) (AnyObject, Selector) -> Bool
let sendAXRequest = unsafeBitCast(msgSend, to: SendAXRequestFn.self)
let frontmostFn = unsafeBitCast(msgSend, to: FrontmostFn.self)
let objectAtPointFn = unsafeBitCast(msgSend, to: ObjectAtPointFn.self)
let objectToObjectFn = unsafeBitCast(msgSend, to: ObjectToObjectFn.self)
let objectGetterFn = unsafeBitCast(msgSend, to: ObjectGetterFn.self)
let boolGetterFn = unsafeBitCast(msgSend, to: BoolGetterFn.self)

let sendAXSelector = NSSelectorFromString("sendAccessibilityRequestAsync:completionQueue:completionHandler:")
let frontmostSelector = NSSelectorFromString("frontmostApplicationWithDisplayId:bridgeDelegateToken:")
let objectAtPointSelector = NSSelectorFromString("objectAtPoint:displayId:bridgeDelegateToken:")
let macElementSelector = NSSelectorFromString("macPlatformElementFromTranslation:")
let setTokenSelector = NSSelectorFromString("setBridgeDelegateToken:")
// CoreSimulator delivers accessibility responses here. It must not be the
// thread the translator call is blocked on.
let accessibilityQueue = DispatchQueue(label: "fdb.ios-simulator-accessibility")
let bridgeToken = UUID().uuidString

/// Set when the tree read may be missing elements.
final class DescribeProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var incompleteValue = false
  var incomplete: Bool {
    lock.lock()
    defer { lock.unlock() }
    return incompleteValue
  }
  func markIncomplete() {
    lock.lock()
    incompleteValue = true
    lock.unlock()
  }
}
let describeProgress = DescribeProgress()

/// Calls the getter [name] on [object], or returns nil when it has none.
/// Every selector is checked first: messaging a missing one raises and aborts.
func getObject(_ object: AnyObject, _ name: String) -> AnyObject? {
  let selector = NSSelectorFromString(name)
  guard object.responds(to: selector) else { return nil }
  return objectGetterFn(object, selector)
}

final class TranslationDelegate: NSObject {
  let device: NSObject
  init(device: NSObject) { self.device = device }

  // Returns the block that turns one AXPTranslatorRequest into an
  // AXPTranslatorResponse. The translator calls it synchronously for every
  // attribute it reads.
  @objc(accessibilityTranslationDelegateBridgeCallbackWithToken:)
  func bridgeCallback(withToken token: NSString) -> Any {
    let device = self.device
    let callback: @convention(block) (AnyObject?) -> AnyObject? = { request in
      let emptyResponse: () -> AnyObject? = {
        guard let responseClass = NSClassFromString("AXPTranslatorResponse") else { return nil }
        return getObject(responseClass, "emptyResponse")
      }
      // After one timeout the tree is incomplete anyway; answer the rest
      // at once instead of waiting 5 s for each.
      guard let request, !describeProgress.incomplete else { return emptyResponse() }
      let done = DispatchSemaphore(value: 0)
      var response: AnyObject?
      let completion: @convention(block) (AnyObject?) -> Void = { inner in
        response = inner
        done.signal()
      }
      sendAXRequest(device, sendAXSelector, request, accessibilityQueue, completion as AnyObject)
      if done.wait(timeout: .now() + 5) == .timedOut {
        describeProgress.markIncomplete()
        return emptyResponse()
      }
      return response ?? emptyResponse()
    }
    return callback as AnyObject
  }

  // Simulator.app converts to window coordinates here; keep the guest's points.
  @objc(accessibilityTranslationConvertPlatformFrameToSystem:withToken:)
  func convertFrame(_ rect: CGRect, withToken token: NSString) -> CGRect { rect }

  @objc(accessibilityTranslationRootParentWithToken:)
  func rootParent(withToken token: NSString) -> Any? { nil }
}

struct AccessibilityElement {
  var depth: Int
  var label: String?
  var role: String?
  var value: String?
  var identifier: String?
  var enabled: Bool
  var pid: Int32
  var rawFrame: CGRect
}

func setBridgeToken(_ object: AnyObject) {
  guard let translation = getObject(object, "translation"), translation.responds(to: setTokenSelector) else { return }
  _ = translation.perform(setTokenSelector, with: bridgeToken as NSString)
}

func accessibilityString(_ element: AnyObject, _ name: String) -> String? {
  guard let value = getObject(element, name) else { return nil }
  if let string = value as? String { return string }
  if let attributed = value as? NSAttributedString { return attributed.string }
  if let number = value as? NSNumber { return number.stringValue }
  return nil
}

func ownerPid(_ element: AnyObject) -> Int32 {
  guard let translation = getObject(element, "translation") as? NSObject,
    translation.responds(to: NSSelectorFromString("pid")),
    let pid = translation.value(forKey: "pid") as? NSNumber
  else { return 0 }
  return pid.int32Value
}

func accessibilityFrame(_ element: AnyObject) -> CGRect {
  guard element.responds(to: NSSelectorFromString("accessibilityFrame")),
    let object = element as? NSObject,
    let value = object.value(forKey: "accessibilityFrame") as? NSValue
  else { return .zero }
  return value.rectValue
}

func readElement(_ element: AnyObject, depth: Int) -> AccessibilityElement {
  setBridgeToken(element)
  let enabledSelector = NSSelectorFromString("isAccessibilityEnabled")
  return AccessibilityElement(
    depth: depth,
    label: accessibilityString(element, "accessibilityLabel"),
    role: accessibilityString(element, "accessibilityRole"),
    value: accessibilityString(element, "accessibilityValue"),
    identifier: accessibilityString(element, "accessibilityIdentifier"),
    enabled: element.responds(to: enabledSelector) ? boolGetterFn(element, enabledSelector) : true,
    pid: ownerPid(element),
    rawFrame: accessibilityFrame(element)
  )
}

/// Turns a translation object into a platform element, or nil.
func platformElement(_ translator: AnyObject, _ translation: AnyObject?) -> AnyObject? {
  guard let translation, translation.responds(to: setTokenSelector) else { return nil }
  _ = translation.perform(setTokenSelector, with: bridgeToken as NSString)
  guard let element = objectToObjectFn(translator, macElementSelector, translation) else { return nil }
  setBridgeToken(element)
  return element
}

let maxElements = 3000
let maxDepth = 64

func walk(_ element: AnyObject, depth: Int, into elements: inout [AccessibilityElement]) {
  guard elements.count < maxElements else {
    describeProgress.markIncomplete()
    return
  }
  // Each read creates autoreleased proxies; drain them per element.
  let children: [AnyObject] = autoreleasepool {
    elements.append(readElement(element, depth: depth))
    return getObject(element, "accessibilityChildren") as? [AnyObject] ?? []
  }
  guard !children.isEmpty else { return }
  guard depth < maxDepth else {
    describeProgress.markIncomplete()
    return
  }
  for child in children {
    walk(child, depth: depth + 1, into: &elements)
  }
}

// Interface point to portrait point: the same mapping as the tap below.
func describePortraitPoint(_ point: CGPoint) -> CGPoint {
  switch orientation {
  case 2: return CGPoint(x: widthPoints - point.x, y: heightPoints - point.y)
  case 3: return CGPoint(x: point.y, y: heightPoints - point.x)
  case 4: return CGPoint(x: widthPoints - point.y, y: point.x)
  default: return point
  }
}

// Portrait point to interface point, the inverse of describePortraitPoint.
// Keep in sync with `iosSimulatorInterfacePoint` in ios_simulator_hid.dart.
func describeInterfacePoint(_ point: CGPoint) -> CGPoint {
  switch orientation {
  case 2: return CGPoint(x: widthPoints - point.x, y: heightPoints - point.y)
  case 3: return CGPoint(x: heightPoints - point.y, y: point.x)
  case 4: return CGPoint(x: point.y, y: widthPoints - point.x)
  default: return point
  }
}

func interfaceRect(fromPortrait rect: CGRect) -> CGRect {
  let a = describeInterfacePoint(rect.origin)
  let b = describeInterfacePoint(CGPoint(x: rect.maxX, y: rect.maxY))
  return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}

func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
  abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
}

enum FrameSpace {
  case interface
  case portrait
  case unresolved
}

// A process reports frames in its own interface orientation. SpringBoard on
// iPhone stays portrait even over a landscape app, so outside portrait decide
// per process whether its frames are already in the interface orientation or
// still portrait: hit-test the centre of small elements under both readings
// and keep the one that finds the element again. Hit-tests take portrait
// points. When no hit-test decides, fall back to geometry: if every frame
// fits on screen under one reading only, use that one. The application
// element's own frame is no guide: SpringBoard's reports the rotated screen
// while its alert's frames are portrait.
func frameSpaces(_ translator: AnyObject, _ elements: [AccessibilityElement]) -> [Int32: FrameSpace] {
  let interfaceScreen = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
  let portraitScreen = CGRect(x: 0, y: 0, width: widthPoints, height: heightPoints)
  var spaces: [Int32: FrameSpace] = [:]
  for pid in Set(elements.map { $0.pid }) {
    if orientation == 1 {
      spaces[pid] = .interface
      continue
    }
    let framed = elements.dropFirst()
      .filter { $0.pid == pid && $0.rawFrame.width > 0 && $0.rawFrame.height > 0 }
    let candidates = framed
      .sorted { $0.rawFrame.width * $0.rawFrame.height < $1.rawFrame.width * $1.rawFrame.height }
      .prefix(8)
    var space = FrameSpace.unresolved
    for candidate in candidates {
      let centre = CGPoint(x: candidate.rawFrame.midX, y: candidate.rawFrame.midY)
      var readings: [(FrameSpace, CGPoint)] = []
      if interfaceScreen.contains(centre) { readings.append((.interface, describePortraitPoint(centre))) }
      if portraitScreen.contains(centre) { readings.append((.portrait, centre)) }
      for (reading, point) in readings {
        let found: Bool = autoreleasepool {
          let translation = objectAtPointFn(translator, objectAtPointSelector, point, 0, bridgeToken as NSString)
          guard let hit = platformElement(translator, translation) else { return false }
          let hitElement = readElement(hit, depth: 0)
          return hitElement.pid == pid && sameFrame(hitElement.rawFrame, candidate.rawFrame)
        }
        if found {
          space = reading
          break
        }
      }
      if space != .unresolved { break }
    }
    if space == .unresolved, !framed.isEmpty {
      let fitsInterface = framed.allSatisfy { interfaceScreen.insetBy(dx: -1, dy: -1).contains($0.rawFrame) }
      let fitsPortrait = framed.allSatisfy { portraitScreen.insetBy(dx: -1, dy: -1).contains($0.rawFrame) }
      if fitsInterface != fitsPortrait { space = fitsInterface ? .interface : .portrait }
    }
    spaces[pid] = space
  }
  return spaces
}

func frameJSON(_ rect: CGRect) -> Any {
  let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].map { Double($0) }
  guard values.allSatisfy({ $0.isFinite }) else { return NSNull() }
  return ["x": values[0], "y": values[1], "width": values[2], "height": values[3]]
}

func describeScreen() -> Never {
  guard
    dlopen(
      "/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation",
      RTLD_NOW
    ) != nil
  else {
    fail("could not load AccessibilityPlatformTranslation.framework")
  }
  guard device.responds(to: sendAXSelector) else {
    fail("this CoreSimulator has no accessibility request API")
  }
  guard let translatorClass = NSClassFromString("AXPTranslator"),
    let translator = getObject(translatorClass, "sharedInstance") as? NSObject,
    translator.responds(to: frontmostSelector),
    translator.responds(to: objectAtPointSelector),
    translator.responds(to: macElementSelector),
    translator.responds(to: NSSelectorFromString("setBridgeTokenDelegate:"))
  else {
    fail("the accessibility translator API (AXPTranslator) is missing")
  }
  let delegate = TranslationDelegate(device: device)
  if let helperProtocol = objc_getProtocol("AXPTranslationTokenDelegateHelper") {
    class_addProtocol(TranslationDelegate.self, helperProtocol)
  }
  translator.setValue(delegate, forKey: "bridgeTokenDelegate")
  // The translator holds its delegate weakly: keep it alive while reading.
  let (elements, spaces) = withExtendedLifetime(delegate) { () -> ([AccessibilityElement], [Int32: FrameSpace]) in
    var elements: [AccessibilityElement] = []
    let rootTranslation = frontmostFn(translator, frontmostSelector, 0, bridgeToken as NSString)
    if let root = platformElement(translator, rootTranslation) {
      walk(root, depth: 0, into: &elements)
    }
    return (elements, frameSpaces(translator, elements))
  }
  let items: [[String: Any]] = elements.enumerated().map { index, element in
    // The application element reports the screen in the interface orientation.
    let space = index == 0 ? FrameSpace.interface : (spaces[element.pid] ?? .unresolved)
    var item: [String: Any] = [
      "label": element.label ?? "",
      "role": element.role ?? "",
      "enabled": element.enabled,
      "pid": Int(element.pid),
      "depth": element.depth,
    ]
    if let identifier = element.identifier, !identifier.isEmpty { item["identifier"] = identifier }
    if let value = element.value, !value.isEmpty { item["value"] = value }
    switch space {
    case .interface: item["frame"] = frameJSON(element.rawFrame)
    case .portrait: item["frame"] = frameJSON(interfaceRect(fromPortrait: element.rawFrame))
    case .unresolved: item["frame"] = NSNull()
    }
    return item
  }
  let document: [String: Any] = [
    "orientation": orientationName,
    "screen": ["width": frameWidth, "height": frameHeight],
    "complete": !describeProgress.incomplete,
    "elements": items,
  ]
  guard JSONSerialization.isValidJSONObject(document),
    let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]),
    let json = String(data: data, encoding: .utf8)
  else {
    fail("could not encode the accessibility tree as JSON")
  }
  print(json)
  exit(0)
}

if isDescribe {
  describeScreen()
}
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
case 1:
  portraitX = x
  portraitY = y
default:
  // Unreachable: orientationNames only holds 1-4.
  fail("native-tap can't map interface orientation \(orientation)", code: 5)
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
