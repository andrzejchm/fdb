import 'package:fdb/core/commands/shared_prefs/shared_prefs_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

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
  final result = await fdbSharedPrefs(
    'ext.fdb.sharedPrefs',
    {'isolateId': isolateId, 'action': 'get', 'key': key},
  );

  if (result.error != null) return PrefsRelayedError(result.error!);

  if (result.exists == true) {
    return PrefsGetFound(result.value);
  }
  return const PrefsGetMissing();
}

Future<SharedPrefsResult> _getAll(String isolateId) async {
  final result = await fdbSharedPrefs(
    'ext.fdb.sharedPrefs',
    {'isolateId': isolateId, 'action': 'getAll'},
  );

  if (result.error != null) return PrefsRelayedError(result.error!);

  return PrefsAllReturned(result.values ?? const {});
}

Future<SharedPrefsResult> _set(
  String isolateId,
  String key,
  String value,
  String type,
) async {
  final result = await fdbSharedPrefs('ext.fdb.sharedPrefs', {
    'isolateId': isolateId,
    'action': 'set',
    'key': key,
    'value': value,
    'type': type,
  });

  if (result.error != null) return PrefsRelayedError(result.error!);

  return PrefsSetOk(key);
}

Future<SharedPrefsResult> _remove(String isolateId, String key) async {
  final result = await fdbSharedPrefs(
    'ext.fdb.sharedPrefs',
    {'isolateId': isolateId, 'action': 'remove', 'key': key},
  );

  if (result.error != null) return PrefsRelayedError(result.error!);

  return PrefsRemoveOk(key);
}

Future<SharedPrefsResult> _clear(String isolateId) async {
  final result = await fdbSharedPrefs(
    'ext.fdb.sharedPrefs',
    {'isolateId': isolateId, 'action': 'clear'},
  );

  if (result.error != null) return PrefsRelayedError(result.error!);

  return const PrefsClearOk();
}
