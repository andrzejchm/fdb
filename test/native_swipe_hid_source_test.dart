import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:test/test.dart';

// Exercise the production message builder and gesture loop with SimulatorKit's
// real mouse builder, replacing only delivery. No simulator/device is contacted.
void main() {
  group('Swift HID messages and cancellation', () {
    late Directory temp;
    late String binary;
    late String developer;

    setUpAll(() async {
      temp = await Directory.systemTemp.createTemp('fdb-swipe-swift-test-');
      binary = '${temp.path}/harness';
      developer = Platform.environment['DEVELOPER_DIR'] ??
          ((await Process.run('xcode-select', ['-p'])).stdout as String).trim();
      final source = File('${temp.path}/harness.swift');
      final builder = iosSimulatorHidSource.substring(
        iosSimulatorHidSource.indexOf('// Indigo message layout'),
        iosSimulatorHidSource.indexOf('let completionQueue ='),
      );
      final loop = iosSimulatorHidSource.substring(
        iosSimulatorHidSource.indexOf('let completionQueue ='),
        iosSimulatorHidSource.lastIndexOf('switch send(touchMessage(down: true))'),
      );
      final signature = iosSimulatorHidSource.substring(
        iosSimulatorHidSource.indexOf('typealias MouseMessageFn ='),
        iosSimulatorHidSource.indexOf('var error: NSError?'),
      );
      final mouseBuilder = iosSimulatorHidSource.substring(
        iosSimulatorHidSource.indexOf('guard let mouseMessagePointer ='),
        iosSimulatorHidSource.indexOf('guard let deviceType ='),
      );
      await source.writeAsString('$_prefix\n$signature\n$mouseBuilder\n$builder\n$_delivery\n$loop');
      final compiled = await Process.run('xcrun', ['swiftc', '-swift-version', '5', '-O', source.path, '-o', binary]);
      expect(compiled.exitCode, 0, reason: '${compiled.stdout}\n${compiled.stderr}');
    });
    tearDownAll(() => temp.delete(recursive: true));

    test('down, position-only moves, and up preserve identity and duplicate payload', () async {
      final log = File('${temp.path}/normal.jsonl');
      final output = await runHidProcess(binary, ['swipe', developer, log.path, 'normal'], const Duration(seconds: 15));
      expect(output.exitCode, 0, reason: output.stderr);
      final events = log.readAsLinesSync().map((line) => jsonDecode(line) as Map<String, dynamic>).toList();
      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.first['mask'], 3);
      expect(events.first['touch'], 1);
      expect(events.first['range'], 1);
      expect(events.first['x'], closeTo(150 / 402, 0.000001));
      expect(events.first['y'], closeTo(1 / 874, 0.000001));
      for (final move in events.sublist(1, events.length - 1)) {
        expect(move['mask'], 4);
        expect(move['touch'], 1);
        expect(move['range'], 1);
      }
      expect(events.last['mask'], 3);
      expect(events.last['touch'], 0);
      expect(events.last['range'], 0);
      expect(events.last['x'], closeTo(150 / 402, 0.000001));
      expect(events.last['y'], closeTo(650 / 874, 0.000001));
      for (final event in events) {
        expect(event['identity'], events.first['identity']);
        expect(event['duplicateMask'], event['mask']);
        expect(event['duplicateTouch'], event['touch']);
        expect(event['duplicateX'], event['x']);
        expect(event['duplicateY'], event['y']);
      }
    });

    test('SIGTERM during unacknowledged down starts cleanup promptly and allows an up retry', () async {
      final log = File('${temp.path}/cancel.jsonl');
      final process = await Process.start(binary, ['swipe', developer, log.path, 'cancel']);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      try {
        final readyDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (!log.existsSync()) {
          if (DateTime.now().isAfter(readyDeadline)) fail('harness did not send down');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final stopwatch = Stopwatch()..start();
        expect(process.kill(ProcessSignal.sigterm), isTrue);
        expect(await process.exitCode.timeout(const Duration(seconds: 12)), 4);
        expect(await stderr, contains('gesture interrupted'));
        expect(await stdout, isNot(contains('SWIPED')));
        final events = log.readAsLinesSync().map((line) => jsonDecode(line) as Map<String, dynamic>).toList();
        expect(events.map((e) => e['touch']), [1, 0, 0]);
        // The first up is deliberately unacknowledged for five seconds. Down
        // must stop waiting on cancellation, leaving time for that retry.
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 7)));
        expect((events[1]['time'] as num) - (events[0]['time'] as num), lessThan(1));
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    });

    test('cancellation before down delivers no contact', () async {
      final log = File('${temp.path}/before-down.jsonl');
      final output =
          await runHidProcess(binary, ['swipe', developer, log.path, 'before-down'], const Duration(seconds: 15));
      expect(output.exitCode, 2);
      expect(output.stderr, contains('interrupted before touch down; no gesture delivered'));
      expect(log.existsSync(), isFalse);
    });
  }, skip: _hasSimulatorKit() ? false : 'requires macOS with Xcode and SimulatorKit');
}

bool _hasSimulatorKit() {
  if (!Platform.isMacOS) return false;
  try {
    if (Process.runSync('xcrun', ['--find', 'swiftc']).exitCode != 0) return false;
    final developer =
        Platform.environment['DEVELOPER_DIR'] ?? (Process.runSync('xcode-select', ['-p']).stdout as String).trim();
    return Directory('$developer/Library/PrivateFrameworks/SimulatorKit.framework').existsSync() ||
        Directory('$developer/../SharedFrameworks/SimulatorKit.framework').existsSync();
  } catch (_) {
    return false;
  }
}

const _prefix = r'''
import Foundation
import CoreGraphics
func fail(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write("ERROR: \(message)\n".data(using: .utf8)!)
  exit(code)
}
let args = CommandLine.arguments
let developerDir = args[2]
let logPath = args[3]
let cancel = args[4] == "cancel"
let paths = ["\(developerDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
             "\(developerDir)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit"]
guard let simulatorKit = paths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first else { fail("SimulatorKit unavailable") }
let isSwipe = true
var interrupted = args[4] == "before-down"
signal(SIGTERM) { _ in interrupted = true }
let x = 150.0, y = 1.0, endX = 150.0, endY = 650.0
let portraitX = x, portraitY = y, widthPoints = 402.0, heightPoints = 874.0
let durationMs = 40
let orientationName = "portrait"
let hid = NSObject()
func describePortraitPoint(_ point: CGPoint) -> CGPoint { point }
''';

const _delivery = r'''
var upCount = 0
func sendHid(_ hid: NSObject, _ selector: Selector, _ message: UnsafeMutableRawPointer,
             _ freeWhenDone: Bool, _ queue: DispatchQueue, _ completion: AnyObject) {
  let touch = message.load(fromByteOffset: 0x68, as: UInt32.self)
  let event: [String: Any] = [
    "mask": message.load(fromByteOffset: 0x38, as: UInt32.self),
    "identity": message.load(fromByteOffset: 0x30, as: UInt32.self),
    "range": message.load(fromByteOffset: 0x64, as: UInt32.self), "touch": touch,
    "x": message.load(fromByteOffset: 0x3c, as: Double.self),
    "y": message.load(fromByteOffset: 0x44, as: Double.self),
    "duplicateMask": message.load(fromByteOffset: 0xb0 + 0x18, as: UInt32.self),
    "duplicateTouch": message.load(fromByteOffset: 0xb0 + 0x48, as: UInt32.self),
    "duplicateX": message.load(fromByteOffset: 0xb0 + 0x1c, as: Double.self),
    "duplicateY": message.load(fromByteOffset: 0xb0 + 0x24, as: Double.self),
    "time": ProcessInfo.processInfo.systemUptime,
  ]
  let data = try! JSONSerialization.data(withJSONObject: event)
  if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
  let file = FileHandle(forWritingAtPath: logPath)!
  file.seekToEndOfFile()
  file.write(data)
  file.write(Data([10]))
  file.closeFile()
  free(message)
  if touch == 0 { upCount += 1 }
  if cancel && (touch != 0 || upCount == 1) { return }
  let callback = unsafeBitCast(completion, to: (@convention(block) (NSError?) -> Void).self)
  callback(nil)
}
''';
