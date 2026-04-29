import 'dart:io';

import 'package:fdb/core/process_utils.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// Unlike [runTap], this command dispatches through the OS input system rather
/// than Flutter's [GestureBinding], making it suitable for tapping system
/// dialogs (iOS permission prompts, Android runtime-permission sheets) that
/// sit outside the Flutter rendering surface.
///
/// Usage:
///   fdb native-tap --at 200,400
///   fdb native-tap --x 200 --y 400
///
/// Platforms and tools:
///   Android (device or emulator) — `adb shell input tap X Y`
///   iOS simulator                — IndigoHID via SimulatorKit private framework (no extra tools)
///
/// Physical iOS is not yet supported. The de-facto standard for out-of-process
/// tap injection on physical iOS is WebDriverAgent (a signed XCUITest runner
/// installed on the device), which has higher setup burden than the current
/// zero-setup paths. Use `fdb tap --at` instead — it performs in-process tap
/// injection via `fdb_helper` and reaches in-app native overlays
/// (UIAlertController, etc.) on physical iOS devices. See beads issue fdb-6sz.
///
/// macOS is not supported. Out-of-process click injection on macOS requires
/// Accessibility permission, which the system only grants to signed `.app`
/// bundles. Homebrew CLIs (cliclick, opencode, tmux) are unsigned binaries
/// and cannot receive Accessibility permission on macOS Sequoia/Tahoe — they
/// don't even appear in the System Settings list when added. Shipping a
/// signed `.app` just for this is not justified for a niche feature. Use
/// `fdb tap --at` instead, which performs in-process tap injection via
/// `fdb_helper` and does not require any system permissions.
///
/// Coordinates:
///   Android  — Android logical pixels (dp), same as Flutter logical coords.
///   iOS      — iOS UIKit logical points (same coordinate space as Flutter).
Future<int> runNativeTap(List<String> args) async {
  double? x;
  double? y;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--x':
        final raw = args[++i];
        x = double.tryParse(raw);
        if (x == null) {
          stderr.writeln('ERROR: Invalid value for --x: $raw');
          return 1;
        }
      case '--y':
        final raw = args[++i];
        y = double.tryParse(raw);
        if (y == null) {
          stderr.writeln('ERROR: Invalid value for --y: $raw');
          return 1;
        }
      case '--at':
        final raw = args[++i];
        final parsed = _parseAt(raw);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid --at value: "$raw". Expected format: x,y (e.g. 200,400).');
          return 1;
        }
        x = parsed.$1;
        y = parsed.$2;
    }
  }

  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together.');
    return 1;
  }

  if (x == null || y == null) {
    stderr.writeln(
      'ERROR: No coordinates provided. Use --at x,y or --x <x> --y <y>.\n'
      'Usage: fdb native-tap --at 200,400',
    );
    return 1;
  }

  final platformInfo = readPlatformInfo();
  final deviceId = readDevice();

  if (platformInfo == null) {
    stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
    return 1;
  }

  final platform = platformInfo.platform;
  final isEmulator = platformInfo.emulator;

  if (platform.startsWith('android')) {
    return _tapAndroid(deviceId: deviceId, x: x, y: y);
  }

  if (platform.startsWith('ios') && isEmulator) {
    return _tapIosSimulator(deviceId: deviceId, x: x, y: y);
  }

  if (platform.startsWith('ios') && !isEmulator) {
    stderr.writeln(
      'ERROR: native-tap is not yet supported on physical iOS devices.\n'
      '  Use `fdb tap --at $x,$y` instead — it performs in-process tap\n'
      '  injection via fdb_helper, which reaches UIAlertController and other\n'
      '  in-app native overlays on physical iOS devices.\n'
      '\n'
      '  Why: out-of-process tap injection on physical iOS requires\n'
      '  WebDriverAgent (a signed XCUITest runner installed on the device).\n'
      '  Tracking implementation in beads issue fdb-6sz.',
    );
    return 1;
  }

  if (platform.startsWith('darwin')) {
    stderr.writeln(
      'ERROR: native-tap is not supported on macOS.\n'
      '  Use `fdb tap --at $x,$y` instead — it performs in-process tap injection\n'
      '  via fdb_helper and does not require Accessibility permission.\n'
      '\n'
      '  Why: cross-process tap injection on macOS requires Accessibility\n'
      '  permission, which is only grantable to signed .app bundles. Homebrew\n'
      '  CLIs are unsigned and cannot be added to the Accessibility list.',
    );
    return 1;
  }

  stderr.writeln('ERROR: native-tap is not supported on platform "$platform".');
  return 1;
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

/// Taps an Android device or emulator at ([x], [y]) via `adb shell input tap`.
///
/// Coordinates are in Android dp, which equals Flutter logical pixels.
Future<int> _tapAndroid({required String? deviceId, required double x, required double y}) async {
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];
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
      stderr.writeln('ERROR: adb input tap failed: $details');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=android X=${x.toInt()} Y=${y.toInt()}');
    return 0;
  } catch (e) {
    stderr.writeln(
      'ERROR: Failed to run adb: $e\n'
      '  Install adb: https://developer.android.com/studio/command-line/adb',
    );
    return 1;
  }
}

// ---------------------------------------------------------------------------
// iOS simulator — IndigoHID via SimulatorKit (no third-party tools)
// ---------------------------------------------------------------------------

/// Taps inside an iOS Simulator at ([x], [y]) using IndigoHID via the
/// SimulatorKit private framework bundled inside Xcode.
///
/// IndigoHID is the same Mach IPC path that Simulator.app uses internally to
/// translate macOS mouse events into simulated iOS touch events. Injecting
/// directly via [SimDeviceLegacyHIDClient] bypasses the Simulator.app window
/// entirely, so it works regardless of whether the Simulator is focused and
/// correctly reaches native OS dialogs in SpringBoard (permission prompts, etc.)
/// that run outside the Flutter process.
///
/// Coordinates are iOS UIKit logical points (same space as Flutter logical px).
/// They are normalised to xRatio/yRatio (0.0–1.0) before transmission.
/// Screen dimensions are read from simctl to perform the normalisation.
///
/// No extra tools required beyond Xcode.
Future<int> _tapIosSimulator({required String? deviceId, required double x, required double y}) async {
  // Resolve screen size for this simulator to normalise coordinates.
  // _simulatorScreenSize always returns a value (falls back to iPhone 17 Pro
  // dimensions on miss); good enough for IndigoHID normalisation since most
  // modern iPhones share that 393×852 resolution.
  final (screenW, screenH) = await _simulatorScreenSize(deviceId);

  // Inline Swift script using SimulatorKit.SimDeviceLegacyHIDClient to
  // send IndigoHID touch events. No idb, no cliclick, no AX permission needed.
  final udid = deviceId ?? 'booted';
  final script = _indigoTapScript(udid: udid, x: x, y: y, screenW: screenW, screenH: screenH);

  try {
    final result = await Process.run('swift', ['-e', script]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      stderr.writeln('ERROR: IndigoHID tap failed:\n$details');
      return 1;
    }
    final out = (result.stdout as String).trim();
    if (!out.contains('TAPPED')) {
      stderr.writeln('ERROR: IndigoHID tap produced unexpected output: $out');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=ios-simulator X=${x.toInt()} Y=${y.toInt()}');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run swift for IndigoHID tap: $e');
    return 1;
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

(double, double)? _parseAt(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final px = double.tryParse(parts[0].trim());
  final py = double.tryParse(parts[1].trim());
  if (px == null || py == null) return null;
  return (px, py);
}
