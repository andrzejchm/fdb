import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tap/tap.dart';

/// CLI adapter for `fdb tap`.
///
/// Accepts:
/// - `--text <value>`: Widget text selector
/// - `--key <value>`: Widget key selector
/// - `--type <value>`: Widget type selector
/// - `--index <n>`: Widget index (when multiple matches)
/// - `--x <n>`: X coordinate
/// - `--y <n>`: Y coordinate
/// - `--at <x,y>`: Coordinate shorthand (e.g. 200,400)
/// - `--timeout <secs>`: Retry timeout in seconds (default: 5)
/// - `@N`: Positional ref from `fdb describe`
/// - `--expect-text <value>`: With `@N`, fail unless the entry shows this text
/// - `--expect-type <value>`: With `@N`, fail unless the entry has this type
Future<int> runTapCli(List<String> args) async {
  final parser = ArgParser()
    ..addOption('text')
    ..addOption('key')
    ..addOption('type')
    ..addOption('index')
    ..addOption('x')
    ..addOption('y')
    ..addOption('at')
    ..addOption('timeout', defaultsTo: '5')
    ..addOption('expect-text', help: 'With @N: fail unless the entry shows this text (or a " · " part of it).')
    ..addOption('expect-type', help: 'With @N: fail unless the entry has this widget type.');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  // Parse --index
  int? index;
  if (results['index'] != null) {
    final rawIndex = results['index'] as String;
    index = int.tryParse(rawIndex);
    if (index == null) {
      stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
      return 1;
    }
  }

  // Parse --x
  double? x;
  if (results['x'] != null) {
    final rawX = results['x'] as String;
    x = double.tryParse(rawX);
    if (x == null) {
      stderr.writeln('ERROR: Invalid value for --x: $rawX');
      return 1;
    }
  }

  // Parse --y
  double? y;
  if (results['y'] != null) {
    final rawY = results['y'] as String;
    y = double.tryParse(rawY);
    if (y == null) {
      stderr.writeln('ERROR: Invalid value for --y: $rawY');
      return 1;
    }
  }

  // Parse --at
  var usedAt = false;
  if (results['at'] != null) {
    final rawAt = results['at'] as String;
    final parsed = parseXY(rawAt);
    if (parsed == null) {
      stderr.writeln(
        'ERROR: Invalid --at value: "$rawAt". Expected format: x,y (e.g. 200,400).',
      );
      return 1;
    }
    x = parsed.$1;
    y = parsed.$2;
    usedAt = true;
  }

  // Parse --timeout
  final rawTimeout = results['timeout'] as String;
  final timeoutSeconds = int.tryParse(rawTimeout);
  if (timeoutSeconds == null) {
    stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
    return 1;
  }

  // Parse @N positional ref
  int? describeRef;
  for (final arg in results.rest) {
    if (arg.startsWith('@')) {
      final refNum = int.tryParse(arg.substring(1));
      if (refNum == null || refNum < 1) {
        stderr.writeln('ERROR: Invalid ref: $arg. Expected @N where N >= 1');
        return 1;
      }
      describeRef = refNum;
    }
  }

  final String? text = results['text'] as String?;
  final String? key = results['key'] as String?;
  final String? type = results['type'] as String?;
  final expectText = results.option('expect-text');
  final expectType = results.option('expect-type');

  // Validation
  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together');
    return 1;
  }

  final hasSelector = text != null || key != null || type != null;
  final hasCoords = x != null && y != null;

  if (usedAt && hasSelector) {
    stderr.writeln('ERROR: --at cannot be combined with --key, --text, or --type.');
    return 1;
  }

  if ((expectText != null || expectType != null) && describeRef == null) {
    stderr.writeln('ERROR: --expect-text and --expect-type only apply to an @N ref');
    return 1;
  }

  if (!hasSelector && !hasCoords && describeRef == null) {
    stderr.writeln('ERROR: Provide --text, --key, --type, --at, --x/--y, or @N ref');
    return 1;
  }

  final input = (
    text: text,
    key: key,
    type: type,
    index: index,
    x: x,
    y: y,
    usedAt: usedAt,
    describeRef: describeRef,
    expectText: expectText,
    expectType: expectType,
    timeoutSeconds: timeoutSeconds,
  );

  final result = await tapWidget(input);
  return formatTapResult(result);
}

/// Formats a [TapResult] to stdout/stderr and returns the exit code.
///
/// Exposed so other CLI adapters (e.g. `native_tap_cli`) can reuse the
/// same result formatting without duplicating the switch.
int formatTapResult(TapResult result) {
  switch (result) {
    case TapSuccess(:final widgetType, :final x, :final y, :final warning, :final text):
      final textSuffix = text != null ? ' TEXT="$text"' : '';
      final warningSuffix = warning != null ? ' WARNING=$warning' : '';
      stdout.writeln('TAPPED=$widgetType X=$x Y=$y$textSuffix$warningSuffix');
      return 0;
    case TapNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case TapUnexpectedDescribeResponse():
      stderr.writeln('ERROR: Unexpected response from ext.fdb.describe');
      return 1;
    case TapRelayedDescribeError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case TapRefNotFound(:final ref):
      stderr.writeln(
        'ERROR: No interactive element with ref @$ref. '
        'Run `fdb describe` to see available refs.',
      );
      return 1;
    case TapRefMismatch(:final ref, :final type, :final text, :final expectedText, :final expectedType):
      final expected = [
        if (expectedType != null) expectedType,
        if (expectedText != null) '"$expectedText"',
      ].join(' ');
      stderr.writeln(
        'ERROR: @$ref is now ${_entryLabel(type, text)}, not $expected. Nothing was tapped. '
        'Refs are positions in the current screen and shift when it changes. Run `fdb describe` again.',
      );
      return 1;
    case TapRefOffScreen(:final ref, :final type, :final text):
      stderr.writeln(
        'ERROR: @$ref ${_entryLabel(type, text)} is not on screen. Nothing was tapped. '
        'Scroll it into view (fdb scroll-to), then run `fdb describe` again for its new ref.',
      );
      return 1;
    case TapRefMoved(:final ref, :final type, :final text):
      stderr.writeln(
        'ERROR: @$ref ${_entryLabel(type, text)} moved or disappeared before it could be tapped. Nothing was tapped. '
        'Wait for the screen to settle and run `fdb describe` again.',
      );
      return 1;
    case TapRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case TapUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.tap: $raw');
      return 1;
    case TapAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case TapError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

String _entryLabel(String type, String? text) => text != null ? '$type "$text"' : type;
