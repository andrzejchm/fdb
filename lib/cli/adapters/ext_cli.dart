import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/ext/ext.dart';

/// CLI adapter for `fdb ext`.
///
/// Sub-commands:
///   fdb ext list
///   fdb ext call `<method>` [--arg key=value ...]
Future<int> runExtCli(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return 0;
  }

  if (args.isEmpty) {
    stderr.writeln('ERROR: sub-command required.\n$_usage');
    return 1;
  }

  final sub = args[0];
  final rest = args.sublist(1);

  switch (sub) {
    case 'list':
      return _runList(rest);
    case 'call':
      return _runCall(rest);
    default:
      stderr.writeln('ERROR: unknown sub-command: $sub\n$_usage');
      return 1;
  }
}

// ---------------------------------------------------------------------------
// Sub-command runners
// ---------------------------------------------------------------------------

Future<int> _runList(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: fdb ext list');
    return 0;
  }

  if (args.isNotEmpty) {
    stderr.writeln('ERROR: unexpected argument: ${args[0]}');
    return 1;
  }

  final result = await ext(const ExtListInput());
  return _format(result);
}

Future<int> _runCall(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: fdb ext call <method> [--arg key=value ...]');
    return 0;
  }

  if (args.isEmpty) {
    stderr.writeln('ERROR: method required — fdb ext call <method> [--arg key=value ...]');
    return 1;
  }

  final method = args[0];
  final rest = args.sublist(1);

  // Parse repeatable --arg key=value pairs.
  final callArgs = <String, String>{};
  for (var i = 0; i < rest.length; i++) {
    if (rest[i] == '--arg' && i + 1 < rest.length) {
      final pair = rest[++i];
      final eqIndex = pair.indexOf('=');
      if (eqIndex <= 0) {
        stderr.writeln('ERROR: --arg must be in key=value format, got: $pair');
        return 1;
      }
      callArgs[pair.substring(0, eqIndex)] = pair.substring(eqIndex + 1);
    } else {
      stderr.writeln('ERROR: unexpected argument: ${rest[i]}');
      return 1;
    }
  }

  final result = await ext(ExtCallInput(method: method, args: callArgs));
  return _format(result);
}

// ---------------------------------------------------------------------------
// Result formatter
// ---------------------------------------------------------------------------

int _format(ExtResult result) {
  switch (result) {
    case ExtListOk(:final extensions):
      if (extensions.isEmpty) {
        stdout.writeln('EXT_LIST_EMPTY');
        return 0;
      }
      stdout.writeln('EXT_LIST_COUNT=${extensions.length}');
      for (final name in extensions) {
        stdout.writeln(name);
      }
      return 0;

    case ExtCallOk(:final json):
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(json));
      return 0;

    case ExtNoIsolates():
      stderr.writeln('ERROR: No isolates found. Is the app running?');
      return 1;

    case ExtRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;

    case ExtAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);

    case ExtError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

// ---------------------------------------------------------------------------
// Usage text
// ---------------------------------------------------------------------------

const _usage = '''
Usage: fdb ext <list|call> [args]

Sub-commands:
  list                          List all registered VM service extensions
  call <method> [--arg k=v ...] Invoke an extension and print the JSON result

Examples:
  fdb ext list
  fdb ext call ext.flutter.imageCache.size
  fdb ext call ext.flutter.platformOverride --arg value=iOS
  fdb ext call ext.myapp.clearAuthCache''';
