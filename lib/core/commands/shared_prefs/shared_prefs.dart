import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/shared_prefs/shared_prefs_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/shared_prefs/shared_prefs_models.dart';

// ---------------------------------------------------------------------------
// Core function
// ---------------------------------------------------------------------------

/// Reads, writes, and clears SharedPreferences via the ext.fdb.sharedPrefs
/// VM service extension registered by fdb_helper.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SharedPrefsResult> sharedPrefs(SharedPrefsInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const PrefsNoFdbHelper();

    return switch (input) {
      PrefsGetInput(:final key) => await _get(isolateId, key),
      PrefsGetAllInput() => await _getAll(isolateId),
      PrefsSetInput(:final key, :final value, :final type) => await _set(isolateId, key, value, type),
      PrefsRemoveInput(:final key) => await _remove(isolateId, key),
      PrefsClearInput() => await _clear(isolateId),
    };
  } on AppDiedException catch (e) {
    return PrefsAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return PrefsError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Private helpers — one per sub-command
// ---------------------------------------------------------------------------

Future<SharedPrefsResult> _get(String isolateId, String key) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'get', 'key': key},
    ),
  ) as Map<String, dynamic>?;

  if (result == null) return const PrefsRelayedError('no response');
  if (result.containsKey('error')) return PrefsRelayedError(result['error'] as String);

  if (result['exists'] == true) {
    return PrefsGetFound(result['value']);
  }
  return const PrefsGetMissing();
}

Future<SharedPrefsResult> _getAll(String isolateId) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'getAll'},
    ),
  ) as Map<String, dynamic>?;

  if (result == null) return const PrefsRelayedError('no response');
  if (result.containsKey('error')) return PrefsRelayedError(result['error'] as String);

  final values = result['values'] as Map<String, dynamic>? ?? {};
  return PrefsAllReturned(values);
}

Future<SharedPrefsResult> _set(
  String isolateId,
  String key,
  String value,
  String type,
) async {
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

  if (result == null) return const PrefsRelayedError('no response');
  if (result.containsKey('error')) return PrefsRelayedError(result['error'] as String);

  return PrefsSetOk(key);
}

Future<SharedPrefsResult> _remove(String isolateId, String key) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'remove', 'key': key},
    ),
  ) as Map<String, dynamic>?;

  if (result == null) return const PrefsRelayedError('no response');
  if (result.containsKey('error')) return PrefsRelayedError(result['error'] as String);

  return PrefsRemoveOk(key);
}

Future<SharedPrefsResult> _clear(String isolateId) async {
  final result = unwrapRawExtensionResult(
    await vmServiceCall(
      'ext.fdb.sharedPrefs',
      params: {'isolateId': isolateId, 'action': 'clear'},
    ),
  ) as Map<String, dynamic>?;

  if (result == null) return const PrefsRelayedError('no response');
  if (result.containsKey('error')) return PrefsRelayedError(result['error'] as String);

  return const PrefsClearOk();
}
