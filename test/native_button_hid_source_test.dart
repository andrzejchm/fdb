import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:test/test.dart';

// Compile the production button branch with the real SimulatorKit builder.
// Replace only the HID client/delivery so failures do not touch live devices.
void main() {
  group('Swift hardware button delivery', () {
    late Directory temp;
    late String binary;
    late String developer;
    setUpAll(() async {
      temp = await Directory.systemTemp.createTemp('fdb-button-swift-');
      binary = '${temp.path}/harness';
      developer = Platform.environment['DEVELOPER_DIR'] ??
          ((await Process.run('xcode-select', ['-p'])).stdout as String).trim();
      final branch = iosSimulatorHidSource.substring(
        iosSimulatorHidSource.indexOf('if isButton {'),
        iosSimulatorHidSource.indexOf('guard let mouseMessagePointer ='),
      );
      final clientStart = branch.indexOf('  guard let hidClass =');
      final clientEnd = branch.indexOf('  let queue =');
      final source = File('${temp.path}/harness.swift');
      await source
          .writeAsString('$_prefix\n${branch.replaceRange(clientStart, clientEnd, '  let hid = NSObject()\n')}');
      final compiled = await Process.run('xcrun', ['swiftc', '-swift-version', '5', '-O', source.path, '-o', binary]);
      expect(compiled.exitCode, 0, reason: '${compiled.stdout}\n${compiled.stderr}');
    });
    tearDownAll(() => temp.delete(recursive: true));

    test('Home and lock are hardware messages, acknowledged down/up once', () async {
      for (final button in ['home', 'lock']) {
        final result = await Process.run(binary, ['button', developer, 'unused-udid', button, 'normal']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
            result.stdout,
            'SEND=${button == 'home' ? 0 : 1},1,51\n'
            'SEND=${button == 'home' ? 0 : 1},2,51\nBUTTON=$button\n');
      }
    });

    test('failed or unacknowledged down still releases once, never reports success or repeats a press', () async {
      for (final mode in ['down-error', 'up-error', 'down-timeout', 'up-timeout']) {
        final result = await Process.run(binary, ['button', developer, 'unused-udid', 'lock', mode]);
        expect(result.exitCode, 4, reason: '$mode: ${result.stderr}');
        expect(result.stdout, 'SEND=1,1,51\nSEND=1,2,51\n');
        expect(result.stderr, contains('button delivery uncertain'));
        expect(result.stderr, contains('no retry'));
      }
    }, timeout: const Timeout(Duration(seconds: 45)));
  }, skip: _hasXcode() ? false : 'requires macOS and Xcode');
}

bool _hasXcode() {
  if (!Platform.isMacOS) return false;
  try {
    return Process.runSync('xcrun', ['--find', 'swiftc']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

const _prefix = r'''
import Foundation
func fail(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write("ERROR: \(message)\n".data(using: .utf8)!)
  exit(code)
}
let arguments = CommandLine.arguments
let developerDir = arguments[2]
let isButton = true
let mode = arguments[5]
let paths = [
  "\(developerDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
  "\(developerDir)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit"
]
guard let simulatorKit = paths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first else { fail("no SimulatorKit") }
func sendHid(_ hid: NSObject, _ selector: Selector, _ message: UnsafeMutableRawPointer,
             _ freeWhenDone: Bool, _ queue: DispatchQueue, _ callback: AnyObject) {
  let source = message.load(fromByteOffset: 0x30, as: UInt32.self)
  let direction = message.load(fromByteOffset: 0x34, as: UInt32.self)
  let target = message.load(fromByteOffset: 0x38, as: UInt32.self)
  print("SEND=\(source),\(direction),\(target)")
  if freeWhenDone { free(message) }
  if mode == "down-timeout" && direction == 1 || mode == "up-timeout" && direction == 2 { return }
  let completion = unsafeBitCast(callback, to: (@convention(block) (NSError?) -> Void).self)
  let failure = (mode == "down-error" && direction == 1) || (mode == "up-error" && direction == 2)
  completion(failure ? NSError(domain: "test-delivery", code: 1) : nil)
}
''';
