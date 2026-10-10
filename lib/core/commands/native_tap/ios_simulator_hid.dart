import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:fdb/core/process_utils.dart';

// Internal helper for `fdb native-tap` on the iOS simulator.
//
// Compiles `iosSimulatorHidSource` once with `xcrun swiftc`, caches the
// binary under the fdb cache dir and runs it to inject a tap through the
// simulator's HID stack. Not a command on its own.

/// Outcome of [iosSimulatorHidTap].
sealed class IosSimulatorHidResult {
  const IosSimulatorHidResult();
}

/// The helper delivered the touch down/up pair.
class IosSimulatorHidTapped extends IosSimulatorHidResult {
  const IosSimulatorHidTapped();
}

/// The coordinates are outside the simulator screen (helper exit code 3).
class IosSimulatorHidOutOfBounds extends IosSimulatorHidResult {
  const IosSimulatorHidOutOfBounds(this.message);
  final String message;
}

/// The helper could not tell how the simulator is rotated, so it refused to
/// tap (helper exit code 5). Nothing was delivered, but callers must not fall
/// back either: the point could land on a different spot than intended.
class IosSimulatorHidOrientationUnknown extends IosSimulatorHidResult {
  const IosSimulatorHidOrientationUnknown(this.message);
  final String message;
}

/// The touch may have been partially delivered (helper exit code 4, or the
/// helper was killed on timeout). Callers must NOT fall back to another tap
/// path: that could double-tap.
class IosSimulatorHidFailed extends IosSimulatorHidResult {
  const IosSimulatorHidFailed(this.message);
  final String message;
}

/// The HID path could not be used and nothing was delivered; callers should
/// fall back.
class IosSimulatorHidUnavailable extends IosSimulatorHidResult {
  const IosSimulatorHidUnavailable(this.reason);
  final String reason;
}

/// Output of a finished process.
typedef HidProcessOutput = ({int exitCode, String stdout, String stderr});

/// Runs [executable] with [arguments]. Throws [TimeoutException] after
/// [timeout] and [ProcessException] when the executable cannot be started.
typedef HidProcessRunner = Future<HidProcessOutput> Function(
  String executable,
  List<String> arguments,
  Duration timeout,
);

const _compileTimeout = Duration(seconds: 180);
const _tapTimeout = Duration(seconds: 15);
const _toolTimeout = Duration(seconds: 15);
const _outOfBoundsExitCode = 3;
const _partialDeliveryExitCode = 4;
const _orientationUnknownExitCode = 5;
const _staleTempAge = Duration(minutes: 10);

/// Flags passed to `xcrun swiftc`. Part of the cache key.
const iosSimulatorHidCompilerFlags = ['-swift-version', '5', '-O'];

/// FNV-1a 64-bit hash of [bytes] as 16 lowercase hex digits.
String fnv1a64Hex(List<int> bytes) {
  // Dart VM ints are 64-bit and multiplication wraps, which is exactly the
  // modulo-2^64 arithmetic FNV needs.
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash *= 0x100000001b3;
  }
  final high = (hash >> 32) & 0xffffffff;
  final low = hash & 0xffffffff;
  return high.toRadixString(16).padLeft(8, '0') + low.toRadixString(16).padLeft(8, '0');
}

/// Directory holding compiled helpers: `FDB_CACHE_DIR`, else
/// `HOME/Library/Caches/fdb`. Returns null when neither is available.
String? iosSimulatorHidCacheDir({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final override = env['FDB_CACHE_DIR'];
  if (override != null && override.isNotEmpty) return override;
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/Library/Caches/fdb';
}

/// Path of the cached helper binary for [source] compiled with [flags]
/// inside [cacheDir].
String iosSimulatorHidBinaryPath(
  String cacheDir, {
  String source = iosSimulatorHidSource,
  List<String> flags = iosSimulatorHidCompilerFlags,
}) {
  final key = fnv1a64Hex(utf8.encode('${flags.join(' ')}\n$source'));
  return '$cacheDir/ios-simulator-hid-$key';
}

/// Interface orientation of the simulator's main screen, as the helper reads
/// it from CoreSimulator (`SimScreenProperties.uiOrientation`). Names follow
/// `devicectl device orientation set`.
enum IosSimulatorOrientation {
  portrait(1),
  portraitUpsideDown(2),
  landscapeRight(3),
  landscapeLeft(4);

  const IosSimulatorOrientation(this.rawValue);

  /// Value reported by CoreSimulator.
  final int rawValue;

  bool get isLandscape => this == landscapeLeft || this == landscapeRight;

  /// Orientation for [rawValue], or null for values the helper refuses.
  static IosSimulatorOrientation? fromRawValue(int rawValue) {
    for (final orientation in values) {
      if (orientation.rawValue == rawValue) return orientation;
    }
    return null;
  }
}

/// Size of the on-screen frame for a screen that is [portraitWidth] x
/// [portraitHeight] points in portrait. Width and height swap in landscape.
///
/// Mirrors the Swift helper; keep both in sync.
({double width, double height}) iosSimulatorOrientedSize(
  IosSimulatorOrientation orientation, {
  required double portraitWidth,
  required double portraitHeight,
}) =>
    orientation.isLandscape
        ? (width: portraitHeight, height: portraitWidth)
        : (width: portraitWidth, height: portraitHeight);

/// Whether ([x], [y]), in the current orientation's frame, lies on screen.
bool iosSimulatorPointInBounds(
  IosSimulatorOrientation orientation, {
  required double x,
  required double y,
  required double portraitWidth,
  required double portraitHeight,
}) {
  final size = iosSimulatorOrientedSize(orientation, portraitWidth: portraitWidth, portraitHeight: portraitHeight);
  return x >= 0 && y >= 0 && x <= size.width && y <= size.height;
}

/// Rotates ([x], [y]) from the current orientation's frame (what screenshots
/// and `fdb tap` use) into the portrait frame the simulator HID stack expects.
///
/// Mirrors the Swift helper; keep both in sync.
({double x, double y}) iosSimulatorPortraitPoint(
  IosSimulatorOrientation orientation, {
  required double x,
  required double y,
  required double portraitWidth,
  required double portraitHeight,
}) =>
    switch (orientation) {
      IosSimulatorOrientation.portrait => (x: x, y: y),
      IosSimulatorOrientation.portraitUpsideDown => (x: portraitWidth - x, y: portraitHeight - y),
      IosSimulatorOrientation.landscapeRight => (x: y, y: portraitHeight - x),
      IosSimulatorOrientation.landscapeLeft => (x: portraitWidth - y, y: x),
    };

/// Taps ([x], [y]) in points on the booted simulator [udid]. The point is in
/// the current interface orientation, like screenshots and `fdb tap --at`.
///
/// [environment], [runner] and [cacheDir] are injectable for tests.
/// Never throws.
Future<IosSimulatorHidResult> iosSimulatorHidTap({
  required String udid,
  required double x,
  required double y,
  Map<String, String>? environment,
  HidProcessRunner? runner,
  String? cacheDir,
}) async {
  final env = environment ?? Platform.environment;
  final run = runner ?? runHidProcess;
  try {
    final dir = cacheDir ?? iosSimulatorHidCacheDir(environment: env);
    if (dir == null) {
      return const IosSimulatorHidUnavailable('no cache directory: set FDB_CACHE_DIR or HOME');
    }

    final binaryPath = await _ensureCompiled(cacheDir: dir, run: run);
    final devDir = await _developerDir(env: env, run: run);
    final arguments = ['tap', devDir, udid, '$x', '$y'];

    HidProcessOutput output;
    try {
      output = await _runHelper(binaryPath, arguments, run);
    } on _BadBinary catch (e) {
      // A corrupt or incompatible cached binary never got far enough to send
      // a touch, so rebuilding and retrying once is safe.
      await _deleteQuietly(File(binaryPath));
      await _ensureCompiled(cacheDir: dir, run: run);
      try {
        output = await _runHelper(binaryPath, arguments, run);
      } on _BadBinary catch (retry) {
        throw _HidUnavailable('helper failed after rebuild: ${retry.reason} (first attempt: ${e.reason})');
      }
    }

    switch (output.exitCode) {
      case 0:
        return const IosSimulatorHidTapped();
      case _outOfBoundsExitCode:
        return IosSimulatorHidOutOfBounds(
          extractHidErrorMessage(output.stderr) ?? 'coordinates are outside the simulator screen',
        );
      case _partialDeliveryExitCode:
        return IosSimulatorHidFailed(
          extractHidErrorMessage(output.stderr) ?? 'touch partially delivered',
        );
      case _orientationUnknownExitCode:
        return IosSimulatorHidOrientationUnknown(
          extractHidErrorMessage(output.stderr) ??
              "native-tap can't tell which way the simulator is rotated; "
                  'wait a moment and try again, or rotate it to portrait',
        );
    }
    final message = _stripErrorPrefix(_tail(output.stderr));
    return IosSimulatorHidUnavailable(
      message.isEmpty ? 'helper exited with code ${output.exitCode}' : message,
    );
  } on _HidPartialDelivery catch (e) {
    return IosSimulatorHidFailed(e.message);
  } on _HidUnavailable catch (e) {
    return IosSimulatorHidUnavailable(e.reason);
  } catch (e) {
    return IosSimulatorHidUnavailable('helper failed: $e');
  }
}

/// Message of the last `ERROR: ` line in [stderr], without the prefix.
/// Other lines (e.g. objc duplicate-class warnings) are ignored.
String? extractHidErrorMessage(String stderr) {
  const prefix = 'ERROR: ';
  final lines = stderr.split('\n').map((l) => l.trimRight()).where((l) => l.startsWith(prefix)).toList();
  if (lines.isEmpty) return null;
  final message = lines.last.substring(prefix.length).trim();
  return message.isEmpty ? null : message;
}

/// Default [HidProcessRunner]: starts the process, decodes output leniently
/// and SIGKILLs it after [timeout] (then throws [TimeoutException]).
Future<HidProcessOutput> runHidProcess(String executable, List<String> arguments, Duration timeout) async {
  final process = await Process.start(executable, arguments);
  final stdoutFuture = process.stdout.transform(tolerantUtf8.decoder).join();
  final stderrFuture = process.stderr.transform(tolerantUtf8.decoder).join();
  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    rethrow;
  }
  return (exitCode: exitCode, stdout: await stdoutFuture, stderr: await stderrFuture);
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

class _HidUnavailable implements Exception {
  const _HidUnavailable(this.reason);
  final String reason;
}

class _HidPartialDelivery implements Exception {
  const _HidPartialDelivery(this.message);
  final String message;
}

/// The cached binary could not be started or died from a signal before
/// printing anything.
class _BadBinary implements Exception {
  const _BadBinary(this.reason);
  final String reason;
}

/// Runs the helper once. Throws [_BadBinary] when the binary looks broken and
/// [_HidPartialDelivery] when it was killed on timeout.
Future<HidProcessOutput> _runHelper(String binaryPath, List<String> arguments, HidProcessRunner run) async {
  final HidProcessOutput output;
  try {
    output = await run(binaryPath, arguments, _tapTimeout);
  } on ProcessException catch (e) {
    throw _BadBinary('could not start the helper: ${e.message}');
  } on TimeoutException {
    // The touch down may already have reached the simulator.
    throw _HidPartialDelivery(
      'iOS simulator HID helper timed out after ${_tapTimeout.inSeconds}s and was killed; '
      'the touch may have been partially delivered',
    );
  }
  if (output.exitCode < 0 && output.stdout.trim().isEmpty && output.stderr.trim().isEmpty) {
    throw _BadBinary('helper killed by signal ${-output.exitCode}');
  }
  return output;
}

/// Returns the cached binary path, compiling it first if needed.
/// Throws [_HidUnavailable] when the compiler is missing or fails.
Future<String> _ensureCompiled({
  required String cacheDir,
  required HidProcessRunner run,
}) async {
  final binaryPath = iosSimulatorHidBinaryPath(cacheDir);
  if (File(binaryPath).existsSync()) return binaryPath;

  await Directory(cacheDir).create(recursive: true);
  _deleteStaleTempBinaries(cacheDir);

  final tempDir = await Directory.systemTemp.createTemp('fdb-ios-simulator-hid-');
  // Compile straight into the cache dir under a unique name so the final
  // rename stays on one filesystem and is atomic: a concurrent fdb sees
  // either no binary or a complete one.
  final tempBinary = File('$binaryPath.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    final sourceFile = File('${tempDir.path}/ios_simulator_hid.swift');
    await sourceFile.writeAsString(iosSimulatorHidSource);

    final HidProcessOutput output;
    try {
      output = await run(
        'xcrun',
        ['swiftc', ...iosSimulatorHidCompilerFlags, sourceFile.path, '-o', tempBinary.path],
        _compileTimeout,
      );
    } on ProcessException catch (e) {
      throw _HidUnavailable('xcrun not available: ${e.message}');
    } on TimeoutException {
      throw _HidUnavailable('swiftc timed out after ${_compileTimeout.inSeconds}s');
    }
    if (output.exitCode != 0) {
      final details = _tail(output.stderr);
      throw _HidUnavailable('swiftc failed (exit ${output.exitCode})${details.isEmpty ? '' : ': $details'}');
    }
    if (!tempBinary.existsSync()) {
      throw const _HidUnavailable('swiftc produced no binary');
    }

    try {
      await tempBinary.rename(binaryPath);
    } on FileSystemException {
      if (!File(binaryPath).existsSync()) rethrow;
    }
    return binaryPath;
  } finally {
    await _deleteQuietly(tempDir);
    await _deleteQuietly(tempBinary);
  }
}

/// Removes `ios-simulator-hid-*.tmp` leftovers from compiles that were
/// interrupted more than [_staleTempAge] ago. Recent ones may belong to a
/// concurrent fdb that is still compiling.
void _deleteStaleTempBinaries(String cacheDir) {
  try {
    final cutoff = DateTime.now().subtract(_staleTempAge);
    for (final entity in Directory(cacheDir).listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('ios-simulator-hid-') || !name.endsWith('.tmp')) continue;
      if (entity.lastModifiedSync().isBefore(cutoff)) entity.deleteSync();
    }
  } catch (_) {
    // Best effort: stale temp files only waste disk space.
  }
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (entity.existsSync()) await entity.delete(recursive: true);
  } catch (_) {
    // Best effort: a leftover temp file is harmless.
  }
}

/// `DEVELOPER_DIR` if set, else `xcode-select -p`.
/// Throws [_HidUnavailable] when neither works.
Future<String> _developerDir({
  required Map<String, String> env,
  required HidProcessRunner run,
}) async {
  final fromEnv = env['DEVELOPER_DIR'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final HidProcessOutput output;
  try {
    output = await run('xcode-select', ['-p'], _toolTimeout);
  } on ProcessException catch (e) {
    throw _HidUnavailable('xcode-select not available: ${e.message}');
  } on TimeoutException {
    throw const _HidUnavailable('xcode-select -p timed out');
  }
  final path = output.stdout.trim();
  if (output.exitCode != 0 || path.isEmpty) {
    throw _HidUnavailable('xcode-select -p failed: ${_tail(output.stderr)}');
  }
  return path;
}

/// Last few non-empty lines of [text] joined on one line, for messages that
/// end up in a single WARNING/ERROR line.
String _tail(String text, {int maxLines = 5}) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final kept = lines.length <= maxLines ? lines : lines.sublist(lines.length - maxLines);
  return kept.join('; ');
}

String _stripErrorPrefix(String message) =>
    message.startsWith('ERROR: ') ? message.substring('ERROR: '.length) : message;
