import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/shared_prefs.dart';

/// CLI adapter for `fdb shared-prefs`.
///
/// Sub-commands:
///   fdb shared-prefs get KEY
///   fdb shared-prefs get-all
///   fdb shared-prefs set KEY VALUE [--type string|bool|int|double]
///   fdb shared-prefs remove KEY
///   fdb shared-prefs clear
Future<int> runSharedPrefsCli(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: fdb shared-prefs <get|get-all|set|remove|clear> [args]',
    );
    return 0;
  }

  if (args.isEmpty) {
    stderr.writeln(
      'ERROR: sub-command required.\n'
      'Usage: fdb shared-prefs <get|get-all|set|remove|clear> [args]',
    );
    return 1;
  }

  final sub = args[0];
  final rest = args.sublist(1);

  switch (sub) {
    case 'get':
      return _runGet(rest);
    case 'get-all':
      return _runGetAll();
    case 'set':
      return _runSet(rest);
    case 'remove':
      return _runRemove(rest);
    case 'clear':
      return _runClear();
    default:
      stderr.writeln('ERROR: unknown sub-command: $sub');
      return 1;
  }
}

// ---------------------------------------------------------------------------
// Sub-command runners
// ---------------------------------------------------------------------------

Future<int> _runGet(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: key required — fdb shared-prefs get <key>');
    return 1;
  }
  final result = await sharedPrefs(PrefsGetInput(args[0]));
  return _format(result);
}

Future<int> _runGetAll() async {
  final result = await sharedPrefs(const PrefsGetAllInput());
  return _format(result);
}

Future<int> _runSet(List<String> args) async {
  String? key;
  String? value;
  String type = 'string';

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--type' && i + 1 < args.length) {
      type = args[++i];
    } else if (key == null) {
      key = args[i];
    } else {
      value ??= args[i];
    }
  }

  if (key == null || value == null) {
    stderr.writeln(
      'ERROR: key and value required — '
      'fdb shared-prefs set <key> <value> [--type string|bool|int|double]',
    );
    return 1;
  }

  final result = await sharedPrefs(
    PrefsSetInput(key: key, value: value, type: type),
  );
  return _format(result);
}

Future<int> _runRemove(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: key required — fdb shared-prefs remove <key>');
    return 1;
  }
  final result = await sharedPrefs(PrefsRemoveInput(args[0]));
  return _format(result);
}

Future<int> _runClear() async {
  final result = await sharedPrefs(const PrefsClearInput());
  return _format(result);
}

// ---------------------------------------------------------------------------
// Result formatter
// ---------------------------------------------------------------------------

int _format(SharedPrefsResult result) {
  switch (result) {
    case PrefsGetFound(:final value):
      stdout.writeln('PREF_VALUE=$value');
      return 0;
    case PrefsGetMissing():
      stdout.writeln('PREF_NOT_FOUND');
      return 0;
    case PrefsAllReturned(:final values):
      stdout.writeln('PREF_ALL=${jsonEncode(values)}');
      for (final entry in values.entries) {
        stdout.writeln('PREF_ENTRY=${entry.key}=${entry.value}');
      }
      return 0;
    case PrefsSetOk(:final key):
      stdout.writeln('PREF_SET=$key');
      return 0;
    case PrefsRemoveOk(:final key):
      stdout.writeln('PREF_REMOVED=$key');
      return 0;
    case PrefsClearOk():
      stdout.writeln('PREF_CLEARED');
      return 0;
    case PrefsNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not found in the running app. '
        'Add FdbBinding.ensureInitialized() to main().',
      );
      return 1;
    case PrefsRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case PrefsAppDied(:final logLines, :final reason):
      // Rethrow so bin/fdb.dart's _formatAppDied produces byte-identical output.
      throw AppDiedException(logLines: logLines, reason: reason);
    case PrefsError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
