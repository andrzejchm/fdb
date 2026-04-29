import 'dart:io';

import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/process_utils.dart';

/// Input parameters for [nativeTap].
typedef NativeTapInput = ({double x, double y});

/// Result of a [nativeTap] invocation.
sealed class NativeTapResult extends CommandResult {
  const NativeTapResult();
}

/// Android tap succeeded.
class NativeTapAndroid extends NativeTapResult {
  const NativeTapAndroid({required this.x, required this.y});
  final int x;
  final int y;
}

/// iOS Simulator tap succeeded via IndigoHID.
class NativeTapIosSimulator extends NativeTapResult {
  const NativeTapIosSimulator({required this.x, required this.y});
  final int x;
  final int y;
}

/// No active fdb session found.
class NativeTapNoSession extends NativeTapResult {
  const NativeTapNoSession();
}

/// Physical iOS device — not yet supported.
class NativeTapPhysicalIosUnsupported extends NativeTapResult {
  const NativeTapPhysicalIosUnsupported({required this.x, required this.y});
  final double x;
  final double y;
}

/// macOS — not supported.
class NativeTapMacosUnsupported extends NativeTapResult {
  const NativeTapMacosUnsupported({required this.x, required this.y});
  final double x;
  final double y;
}

/// Unsupported platform.
class NativeTapPlatformUnsupported extends NativeTapResult {
  const NativeTapPlatformUnsupported(this.platform);
  final String platform;
}

/// `adb shell input tap` exited non-zero.
class NativeTapAdbFailed extends NativeTapResult {
  const NativeTapAdbFailed(this.details);
  final String details;
}

/// `adb` binary could not be launched.
class NativeTapAdbExecutionFailed extends NativeTapResult {
  const NativeTapAdbExecutionFailed(this.error);
  final String error;
}

/// IndigoHID swift script exited non-zero.
class NativeTapIndigoFailed extends NativeTapResult {
  const NativeTapIndigoFailed(this.details);
  final String details;
}

/// IndigoHID swift script succeeded but stdout didn't contain "TAPPED".
class NativeTapIndigoUnexpectedOutput extends NativeTapResult {
  const NativeTapIndigoUnexpectedOutput(this.output);
  final String output;
}

/// `swift` binary could not be launched.
class NativeTapSwiftFailed extends NativeTapResult {
  const NativeTapSwiftFailed(this.error);
  final String error;
}

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// Unlike `fdb tap`, this command dispatches through the OS input system rather
/// than Flutter's GestureBinding, making it suitable for tapping system
/// dialogs (iOS permission prompts, Android runtime-permission sheets) that
/// sit outside the Flutter rendering surface.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<NativeTapResult> nativeTap(NativeTapInput input) async {
  final platformInfo = readPlatformInfo();
  if (platformInfo == null) return const NativeTapNoSession();

  final platform = platformInfo.platform;
  final isEmulator = platformInfo.emulator;

  if (platform.startsWith('android')) {
    return _tapAndroid(input: input);
  }

  if (platform.startsWith('ios') && isEmulator) {
    return _tapIosSimulator(input: input);
  }

  if (platform.startsWith('ios') && !isEmulator) {
    return NativeTapPhysicalIosUnsupported(x: input.x, y: input.y);
  }

  if (platform.startsWith('darwin')) {
    return NativeTapMacosUnsupported(x: input.x, y: input.y);
  }

  return NativeTapPlatformUnsupported(platform);
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapAndroid({required NativeTapInput input}) async {
  final deviceId = readDevice();
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];
  final x = input.x;
  final y = input.y;
  try {
    final result = await Process.run('adb', [
      ...deviceArgs,
      'shell',
      'input',
      'tap',
      x.toInt().toString(),
      y.toInt().toString(),
    ]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return NativeTapAdbFailed(details);
    }
    return NativeTapAndroid(x: x.toInt(), y: y.toInt());
  } catch (e) {
    return NativeTapAdbExecutionFailed(e.toString());
  }
}

// ---------------------------------------------------------------------------
// iOS simulator — IndigoHID via SimulatorKit (no third-party tools)
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapIosSimulator({required NativeTapInput input}) async {
  final deviceId = readDevice();
  final x = input.x;
  final y = input.y;

  // Resolve screen size for this simulator to normalise coordinates.
  // _simulatorScreenSize always returns a value (falls back to iPhone 17 Pro
  // dimensions on miss); good enough for IndigoHID normalisation since most
  // modern iPhones share that 393×852 resolution.
  final (screenW, screenH) = await _simulatorScreenSize(deviceId);

  final udid = deviceId ?? 'booted';
  final script = _indigoTapScript(udid: udid, x: x, y: y, screenW: screenW, screenH: screenH);

  try {
    final result = await Process.run('swift', ['-e', script]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return NativeTapIndigoFailed(details);
    }
    final out = (result.stdout as String).trim();
    if (!out.contains('TAPPED')) {
      return NativeTapIndigoUnexpectedOutput(out);
    }
    return NativeTapIosSimulator(x: x.toInt(), y: y.toInt());
  } catch (e) {
    return NativeTapSwiftFailed(e.toString());
  }
}

/// Returns the logical screen size (width, height) in points for the given
/// simulator UDID. Falls back to iPhone 17 Pro dimensions (393×852) when the
/// UDID is not found or the device name doesn't match any known iPhone/iPad —
/// most modern iPhones share that resolution, and the IndigoHID xRatio/yRatio
/// normalisation is forgiving of small mismatches.
Future<(double, double)> _simulatorScreenSize(String? deviceId) async {
  const fallback = (393.0, 852.0); // iPhone 17 Pro default
  try {
    final result = await Process.run('xcrun', ['simctl', 'list', 'devices', '--json']);
    if (result.exitCode != 0) return fallback;
    final output = result.stdout as String;

    // Look up the device by UDID in the simctl JSON, then map its name to a
    // known logical screen size.
    if (deviceId != null) {
      final nameMatch = RegExp('"name" : "([^"]+)"[^}]*"udid" : "${RegExp.escape(deviceId)}"').firstMatch(output);
      if (nameMatch != null) {
        final name = nameMatch.group(1) ?? '';
        final size = _iPhoneLogicalSize(name);
        if (size != null) return size;
      }
    }

    return fallback;
  } catch (_) {
    return fallback;
  }
}

/// Maps known iPhone/iPad simulator names to their logical screen sizes.
(double, double)? _iPhoneLogicalSize(String deviceName) {
  // Common logical point sizes by device name fragment
  const sizes = <String, (double, double)>{
    'iPhone 17 Pro Max': (440.0, 956.0),
    'iPhone 17 Pro': (393.0, 852.0),
    'iPhone 17 Plus': (430.0, 932.0),
    'iPhone 17': (393.0, 852.0),
    'iPhone Air': (393.0, 852.0),
    'iPhone 16 Pro Max': (440.0, 956.0),
    'iPhone 16 Pro': (402.0, 874.0),
    'iPhone 16 Plus': (430.0, 932.0),
    'iPhone 16': (393.0, 852.0),
    'iPhone 15 Pro Max': (430.0, 932.0),
    'iPhone 15 Pro': (393.0, 852.0),
    'iPhone 15 Plus': (430.0, 932.0),
    'iPhone 15': (393.0, 852.0),
    'iPhone SE': (375.0, 667.0),
    'iPad Pro 13': (1032.0, 1376.0),
    'iPad Pro 11': (834.0, 1210.0),
    'iPad Air 13': (1024.0, 1366.0),
    'iPad Air 11': (820.0, 1180.0),
    'iPad mini': (744.0, 1133.0),
    'iPad': (810.0, 1080.0),
  };
  for (final entry in sizes.entries) {
    if (deviceName.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Returns a self-contained Swift script that injects a touch via IndigoHID.
///
/// Uses [SimulatorKit.SimDeviceLegacyHIDClient] to send an IndigoMessage
/// (192-byte Mach IPC message) directly to the simulator guest runtime.
/// This is the same mechanism Simulator.app uses internally and what idb
/// wraps with its Python CLI — here done without any third-party dependency.
String _indigoTapScript({
  required String udid,
  required double x,
  required double y,
  required double screenW,
  required double screenH,
}) {
  final xRatio = x / screenW;
  final yRatio = y / screenH;
  // Uses IndigoHIDMessageForMouseNSEvent from SimulatorKit — the same private
  // function idb uses internally. This correctly constructs an IndigoMessage
  // without risk of corrupting uninitialized struct fields.
  return '''
import Foundation
dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)
let simKit = dlopen("/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW)
let lib = dlopen(nil, RTLD_NOW)
typealias Fn1Err = @convention(c) (AnyObject,Selector,NSString,UnsafeMutablePointer<NSError?>?)->AnyObject?
typealias Fn0Err = @convention(c) (AnyObject,Selector,UnsafeMutablePointer<NSError?>?)->AnyObject?
typealias FnObjErr = @convention(c) (AnyObject,Selector,AnyObject,UnsafeMutablePointer<NSError?>?)->AnyObject?
typealias FnSend = @convention(c) (AnyObject,Selector,UnsafeMutableRawPointer,Bool,AnyObject?,AnyObject?)->Void
typealias MouseMsgFn = @convention(c) (UnsafeMutablePointer<CGPoint>,UnsafeMutablePointer<CGPoint>?,Int32,Int32,Bool)->UnsafeMutableRawPointer
let fn1 = unsafeBitCast(dlsym(lib,"objc_msgSend"),to:Fn1Err.self)
let fn0 = unsafeBitCast(dlsym(lib,"objc_msgSend"),to:Fn0Err.self)
let fnObj = unsafeBitCast(dlsym(lib,"objc_msgSend"),to:FnObjErr.self)
let fnSend = unsafeBitCast(dlsym(lib,"objc_msgSend"),to:FnSend.self)
guard let mmPtr = dlsym(simKit,"IndigoHIDMessageForMouseNSEvent") else {
  print("ERROR: IndigoHIDMessageForMouseNSEvent not found in SimulatorKit"); exit(1)
}
let mouseMsg = unsafeBitCast(mmPtr,to:MouseMsgFn.self)
var err:NSError?=nil
guard let ctx = fn1(NSClassFromString("SimServiceContext")!,
    NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"),
    "/Applications/Xcode.app/Contents/Developer",&err) as? NSObject,
  let devSet = fn0(ctx,NSSelectorFromString("defaultDeviceSetWithError:"),&err) as? NSObject,
  let devs = devSet.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [NSObject]
else { print("ERROR: CoreSimulator init failed"); exit(1) }
let udid="${udid.replaceAll('"', r'\"')}"
guard let device = devs.first(where:{ dev in
  if udid=="booted"{return (dev.value(forKey:"state") as? Int)==3}
  return (dev.value(forKey:"UDID") as? UUID)?.uuidString==udid.uppercased()
}) else { print("ERROR: device \\(udid) not found"); exit(1) }
guard let hidAlloc=(NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient")! as AnyObject)
    .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
  let hid=fnObj(hidAlloc,NSSelectorFromString("initWithDevice:error:"),device,&err) as? NSObject
else { print("ERROR: HIDClient init failed: \\(err?.localizedDescription ?? "nil")"); exit(1) }
let sel=NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:")
var point=CGPoint(x:$xRatio,y:$yRatio)
var zero=CGPoint(x:0,y:0)
// target 0x32, ButtonEventTypeDown=1, ButtonEventTypeUp=2
let down=mouseMsg(&point,&zero,0x32,1,false)
down.storeBytes(of:$xRatio,toByteOffset:0x3c,as:Double.self)
down.storeBytes(of:$yRatio,toByteOffset:0x44,as:Double.self)
fnSend(hid,sel,down,true,nil,nil)
Thread.sleep(forTimeInterval:0.15)
let up=mouseMsg(&point,&zero,0x32,2,false)
up.storeBytes(of:$xRatio,toByteOffset:0x3c,as:Double.self)
up.storeBytes(of:$yRatio,toByteOffset:0x44,as:Double.self)
fnSend(hid,sel,up,true,nil,nil)
Thread.sleep(forTimeInterval:0.3)
print("TAPPED")
''';
}
