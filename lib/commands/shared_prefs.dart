import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/vm_service.dart';

/// Reads, writes, and clears SharedPreferences via the ext.fdb.sharedPrefs
/// VM service extension registered by fdb_helper.
///
/// Sub-commands:
///   fdb shared-prefs get `<key>`
///   fdb shared-prefs get-all
///   fdb shared-prefs set `<key>` `<value>` [--type string|bool|int|double]
///   fdb shared-prefs remove `<key>`
///   fdb shared-prefs clear
///
/// Output tokens:
///   PREF_VALUE=`<value>`        (get — key exists)
///   PREF_NOT_FOUND              (get — key missing)
///   PREF_ALL=`<json>`           (get-all)
///   PREF_SET=`<key>`            (set)
///   PREF_REMOVED=`<key>`        (remove)
///   PREF_CLEARED                (clear)
Future<int> runSharedPrefs(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'ERROR: sub-command required.\n'
      'Usage: fdb shared-prefs <get|get-all|set|remove|clear> [args]',
    );
    return 1;
  }

  final isolateId = await checkFdbHelper();
  if (isolateId == null) {
    stderr.writeln(
      'ERROR: fdb_helper not found in the running app. '
      'Add FdbBinding.ensureInitialized() to main().',
    );
    return 1;
  }

  final sub = args[0];
  final rest = args.sublist(1);

  switch (sub) {
    case 'get':
      return _get(isolateId, rest);
    case 'get-all':
      return _getAll(isolateId);
    case 'set':
      return _set(isolateId, rest);
    case 'remove':
      return _remove(isolateId, rest);
    case 'clear':
      return _clear(isolateId);
    default:
      stderr.writeln('ERROR: unknown sub-command: $sub');
      return 1;
  }
}

Future<int> _get(String isolateId, List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: key required — fdb shared-prefs get <key>');
    return 1;
  }
  final key = args[0];
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'get', 'key': key},
    ),
  ) as Map<String, dynamic>?;

  if (result == null || result.containsKey('error')) {
    stderr.writeln('ERROR: ${result?['error'] ?? 'no response'}');
    return 1;
  }

  if (result['exists'] == true) {
    stdout.writeln('PREF_VALUE=${result['value']}');
  } else {
    stdout.writeln('PREF_NOT_FOUND');
  }
  return 0;
}

Future<int> _getAll(String isolateId) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'getAll'},
    ),
  ) as Map<String, dynamic>?;

  if (result == null || result.containsKey('error')) {
    stderr.writeln('ERROR: ${result?['error'] ?? 'no response'}');
    return 1;
  }

  final values = result['values'] as Map<String, dynamic>? ?? {};
  stdout.writeln('PREF_ALL=${jsonEncode(values)}');
  // Also print each key=value on its own line for easy parsing
  for (final entry in values.entries) {
    stdout.writeln('PREF_ENTRY=${entry.key}=${entry.value}');
  }
  return 0;
}

Future<int> _set(String isolateId, List<String> args) async {
  // Parse: <key> <value> [--type <type>]
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

  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {
        'isolateId': isolateId,
        'action': 'set',
        'key': key,
        'value': value,
        'type': type,
      },
    ),
  ) as Map<String, dynamic>?;

  if (result == null || result.containsKey('error')) {
    stderr.writeln('ERROR: ${result?['error'] ?? 'no response'}');
    return 1;
  }

  stdout.writeln('PREF_SET=$key');
  return 0;
}

Future<int> _remove(String isolateId, List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: key required — fdb shared-prefs remove <key>');
    return 1;
  }
  final key = args[0];
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'remove', 'key': key},
    ),
  ) as Map<String, dynamic>?;

  if (result == null || result.containsKey('error')) {
    stderr.writeln('ERROR: ${result?['error'] ?? 'no response'}');
    return 1;
  }

  stdout.writeln('PREF_REMOVED=$key');
  return 0;
}

Future<int> _clear(String isolateId) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'clear'},
    ),
  ) as Map<String, dynamic>?;

  if (result == null || result.containsKey('error')) {
    stderr.writeln('ERROR: ${result?['error'] ?? 'no response'}');
    return 1;
  }

  stdout.writeln('PREF_CLEARED');
  return 0;
}
