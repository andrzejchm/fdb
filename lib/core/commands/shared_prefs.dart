import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

// ---------------------------------------------------------------------------
// Input types
// ---------------------------------------------------------------------------

sealed class SharedPrefsInput {
  const SharedPrefsInput();
}

class PrefsGetInput extends SharedPrefsInput {
  const PrefsGetInput(this.key);
  final String key;
}

class PrefsGetAllInput extends SharedPrefsInput {
  const PrefsGetAllInput();
}

class PrefsSetInput extends SharedPrefsInput {
  const PrefsSetInput({required this.key, required this.value, required this.type});
  final String key;
  final String value;

  /// One of: 'string', 'bool', 'int', 'double'
  final String type;
}

class PrefsRemoveInput extends SharedPrefsInput {
  const PrefsRemoveInput(this.key);
  final String key;
}

class PrefsClearInput extends SharedPrefsInput {
  const PrefsClearInput();
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class SharedPrefsResult extends CommandResult {
  const SharedPrefsResult();
}

/// get — key exists; [value] is whatever the VM returned (String/int/bool/double).
class PrefsGetFound extends SharedPrefsResult {
  const PrefsGetFound(this.value);
  final dynamic value;
}

/// get — key does not exist.
class PrefsGetMissing extends SharedPrefsResult {
  const PrefsGetMissing();
}

/// get-all succeeded; [values] is the full map from the VM.
class PrefsAllReturned extends SharedPrefsResult {
  const PrefsAllReturned(this.values);
  final Map<String, dynamic> values;
}

/// set succeeded.
class PrefsSetOk extends SharedPrefsResult {
  const PrefsSetOk(this.key);
  final String key;
}

/// remove succeeded.
class PrefsRemoveOk extends SharedPrefsResult {
  const PrefsRemoveOk(this.key);
  final String key;
}

/// clear succeeded.
class PrefsClearOk extends SharedPrefsResult {
  const PrefsClearOk();
}

/// fdb_helper is not present in the running app.
class PrefsNoFdbHelper extends SharedPrefsResult {
  const PrefsNoFdbHelper();
}

/// The VM extension returned an error payload.
class PrefsRelayedError extends SharedPrefsResult {
  const PrefsRelayedError(this.message);
  final String message;
}

/// The app process died while fdb was communicating with it.
class PrefsAppDied extends SharedPrefsResult {
  const PrefsAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class PrefsError extends SharedPrefsResult {
  const PrefsError(this.message);
  final String message;
}

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
      PrefsSetInput(:final key, :final value, :final type) =>
        await _set(isolateId, key, value, type),
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
