import 'package:fdb/core/models/command_result.dart';

// ---------------------------------------------------------------------------
// Input types
// ---------------------------------------------------------------------------

sealed class ExtInput {
  const ExtInput();
}

/// Input for `fdb ext list` — enumerates all registered VM service extensions.
class ExtListInput extends ExtInput {
  const ExtListInput();
}

/// Input for `fdb ext call <method> [--arg key=value ...]`.
class ExtCallInput extends ExtInput {
  const ExtCallInput({required this.method, required this.args});

  /// Fully-qualified extension method name, e.g. `ext.flutter.imageCache.size`.
  final String method;

  /// Key/value parameters forwarded to the extension (may be empty).
  final Map<String, String> args;
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class ExtResult extends CommandResult {
  const ExtResult();
}

/// `ext list` succeeded; [extensions] is the sorted, deduplicated list.
class ExtListOk extends ExtResult {
  const ExtListOk(this.extensions);
  final List<String> extensions;
}

/// `ext call` succeeded; [json] is the raw JSON response map from the extension.
class ExtCallOk extends ExtResult {
  const ExtCallOk(this.json);
  final Map<String, dynamic> json;
}

/// No isolates found in the running app.
class ExtNoIsolates extends ExtResult {
  const ExtNoIsolates();
}

/// The VM extension returned an error payload.
class ExtRelayedError extends ExtResult {
  const ExtRelayedError(this.message);
  final String message;
}

/// The app process died while fdb was communicating with it.
class ExtAppDied extends ExtResult {
  const ExtAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class ExtError extends ExtResult {
  const ExtError(this.message);
  final String message;
}
