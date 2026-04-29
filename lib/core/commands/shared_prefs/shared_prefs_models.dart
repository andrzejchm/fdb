import 'package:fdb/core/models/command_result.dart';

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
