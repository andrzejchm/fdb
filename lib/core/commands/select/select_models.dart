import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [toggleSelection].
typedef SelectInput = ({bool enabled});

/// Result of a [toggleSelection] invocation.
sealed class SelectResult extends CommandResult {
  const SelectResult();
}

/// The selection mode was toggled successfully.
class SelectSuccess extends SelectResult {
  const SelectSuccess(this.enabled);
  final bool enabled;
}

/// No Flutter isolate was found in the running app.
class SelectNoIsolate extends SelectResult {
  const SelectNoIsolate();
}

/// The app process died while fdb was communicating with it.
class SelectAppDied extends SelectResult {
  const SelectAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SelectError extends SelectResult {
  const SelectError(this.message);
  final String message;
}
