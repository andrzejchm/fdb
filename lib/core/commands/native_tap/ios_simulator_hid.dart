import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:fdb/core/process_utils.dart';

// Internal helper for `fdb native-tap` on the iOS simulator.
//
// Compiles `iosSimulatorHidSource` once with `xcrun swiftc`, caches the
// binary under the fdb cache dir and runs it to inject a tap through the
// simulator's HID stack, or to read the simulator's accessibility tree
// (`describe`, for `--text`). Not a command on its own.

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

/// Default limit for one `describe` run. The first accessibility query on a
/// freshly booted simulator took up to 7.5 s on an M-series Mac; later ones
/// take about 0.2 s.
const iosSimulatorDescribeTimeout = Duration(seconds: 30);
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

/// Rotates ([x], [y]) from the portrait frame back into the current
/// orientation's frame: the inverse of [iosSimulatorPortraitPoint].
///
/// Mirrors `describeInterfacePoint` in the Swift helper, which uses it to
/// map SpringBoard's portrait frames over a landscape app; keep both in sync.
({double x, double y}) iosSimulatorInterfacePoint(
  IosSimulatorOrientation orientation, {
  required double x,
  required double y,
  required double portraitWidth,
  required double portraitHeight,
}) =>
    switch (orientation) {
      IosSimulatorOrientation.portrait => (x: x, y: y),
      IosSimulatorOrientation.portraitUpsideDown => (x: portraitWidth - x, y: portraitHeight - y),
      IosSimulatorOrientation.landscapeRight => (x: portraitHeight - y, y: x),
      IosSimulatorOrientation.landscapeLeft => (x: y, y: portraitWidth - x),
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
  try {
    final output = await _runHelperCommand(
      command: 'tap',
      arguments: [udid, '$x', '$y'],
      timeout: _tapTimeout,
      // The touch down may already have reached the simulator.
      onTimeout: () => _HidPartialDelivery(
        'iOS simulator HID helper timed out after ${_tapTimeout.inSeconds}s and was killed; '
        'the touch may have been partially delivered',
      ),
      environment: environment,
      runner: runner,
      cacheDir: cacheDir,
    );

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

/// Outcome of [iosSimulatorDescribe].
sealed class IosSimulatorDescribeResult {
  const IosSimulatorDescribeResult();
}

/// The helper read the accessibility tree; [json] is its stdout, parsed by
/// `parseIosSimulatorAccessibility`.
class IosSimulatorDescribed extends IosSimulatorDescribeResult {
  const IosSimulatorDescribed(this.json);
  final String json;
}

/// The helper could not tell how the simulator is rotated (exit code 5), so
/// it could not map the frames. Usually brief (boot, rotation): retry.
class IosSimulatorDescribeOrientationUnknown extends IosSimulatorDescribeResult {
  const IosSimulatorDescribeOrientationUnknown(this.message);
  final String message;
}

/// This read failed but the next one may work: it timed out, or the helper
/// exited in an unexpected way.
class IosSimulatorDescribeFailed extends IosSimulatorDescribeResult {
  const IosSimulatorDescribeFailed(this.reason);
  final String reason;
}

/// The accessibility tree cannot be read and retrying won't help: no
/// toolchain, the helper doesn't build, unknown or shut down simulator, a
/// CoreSimulator without the accessibility API (helper exit code 1).
class IosSimulatorDescribeUnavailable extends IosSimulatorDescribeResult {
  const IosSimulatorDescribeUnavailable(this.reason);
  final String reason;
}

/// Reads the accessibility tree of the frontmost application on the booted
/// simulator [udid] (SpringBoard while a system alert is up). The helper is
/// killed after [timeout]; compiling it on first use has its own limit.
///
/// [environment], [runner] and [cacheDir] are injectable for tests.
/// Never throws.
Future<IosSimulatorDescribeResult> iosSimulatorDescribe({
  required String udid,
  Duration timeout = iosSimulatorDescribeTimeout,
  Map<String, String>? environment,
  HidProcessRunner? runner,
  String? cacheDir,
}) async {
  try {
    final output = await _runHelperCommand(
      command: 'describe',
      arguments: [udid],
      timeout: timeout,
      onTimeout: () => _HidRetryable('reading the accessibility tree timed out after ${timeout.inSeconds}s'),
      environment: environment,
      runner: runner,
      cacheDir: cacheDir,
    );
    switch (output.exitCode) {
      case 0:
        return IosSimulatorDescribed(output.stdout);
      case _orientationUnknownExitCode:
        return IosSimulatorDescribeOrientationUnknown(
          extractHidErrorMessage(output.stderr) ?? "native-tap can't tell which way the simulator is rotated",
        );
    }
    final message = extractHidErrorMessage(output.stderr) ?? _stripErrorPrefix(_tail(output.stderr));
    final reason = message.isEmpty ? 'helper exited with code ${output.exitCode}' : message;
    // Exit code 1 is the helper's own diagnosis (unknown simulator, missing
    // API...). Anything else, e.g. a crash, may not happen again.
    return output.exitCode == 1 ? IosSimulatorDescribeUnavailable(reason) : IosSimulatorDescribeFailed(reason);
  } on _HidRetryable catch (e) {
    return IosSimulatorDescribeFailed(e.reason);
  } on _HidUnavailable catch (e) {
    return IosSimulatorDescribeUnavailable(e.reason);
  } catch (e) {
    return IosSimulatorDescribeFailed('helper failed: $e');
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

/// A describe run timed out; the next one may work.
class _HidRetryable implements Exception {
  const _HidRetryable(this.reason);
  final String reason;
}

class _HidPartialDelivery implements Exception {
  const _HidPartialDelivery(this.message);
  final String message;
}

/// Compiles the helper if needed and runs it with [command], the developer
/// dir and [arguments]. A cached binary that cannot start is rebuilt and run once
/// more: it never got far enough to send a touch, so that is safe.
///
/// Throws [_HidUnavailable] when the helper cannot be built or run, and what
/// [onTimeout] returns when it is killed on [timeout].
Future<HidProcessOutput> _runHelperCommand({
  required String command,
  required List<String> arguments,
  required Duration timeout,
  required Exception Function() onTimeout,
  required Map<String, String>? environment,
  required HidProcessRunner? runner,
  required String? cacheDir,
}) async {
  final env = environment ?? Platform.environment;
  final run = runner ?? runHidProcess;
  final dir = cacheDir ?? iosSimulatorHidCacheDir(environment: env);
  if (dir == null) {
    throw const _HidUnavailable('no cache directory: set FDB_CACHE_DIR or HOME');
  }

  final binaryPath = await _ensureCompiled(cacheDir: dir, run: run);
  final devDir = await _developerDir(env: env, run: run);
  final fullArguments = [command, devDir, ...arguments];

  try {
    return await _runHelper(binaryPath, fullArguments, run, timeout, onTimeout);
  } on _BadBinary catch (e) {
    await _deleteQuietly(File(binaryPath));
    await _ensureCompiled(cacheDir: dir, run: run);
    try {
      return await _runHelper(binaryPath, fullArguments, run, timeout, onTimeout);
    } on _BadBinary catch (retry) {
      throw _HidUnavailable('helper failed after rebuild: ${retry.reason} (first attempt: ${e.reason})');
    }
  }
}

/// The cached binary could not be started or died from a signal before
/// printing anything.
class _BadBinary implements Exception {
  const _BadBinary(this.reason);
  final String reason;
}

/// Runs the helper once. Throws [_BadBinary] when the binary looks broken and
/// what [onTimeout] returns when it was killed on [timeout].
Future<HidProcessOutput> _runHelper(
  String binaryPath,
  List<String> arguments,
  HidProcessRunner run,
  Duration timeout,
  Exception Function() onTimeout,
) async {
  final HidProcessOutput output;
  try {
    output = await run(binaryPath, arguments, timeout);
  } on ProcessException catch (e) {
    throw _BadBinary('could not start the helper: ${e.message}');
  } on TimeoutException {
    throw onTimeout();
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
