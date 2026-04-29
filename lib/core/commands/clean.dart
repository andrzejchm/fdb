import 'dart:convert';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [cleanApp]. Empty record because `fdb clean` takes
/// no arguments today.
typedef CleanInput = ();

/// Result of a [cleanApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class CleanResult extends CommandResult {
  const CleanResult();
}

/// Cache directories were successfully cleaned.
class CleanSuccess extends CleanResult {
  const CleanSuccess({required this.dirs, required this.deletedEntries});
  final List<String> dirs;
  final int deletedEntries;
}

/// fdb_helper was not detected in the running app.
class CleanNoFdbHelper extends CleanResult {
  const CleanNoFdbHelper();
}

/// The VM service extension returned an error message.
class CleanError extends CleanResult {
  const CleanError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class CleanUnexpectedResponse extends CleanResult {
  const CleanUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class CleanAppDied extends CleanResult {
  const CleanAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Clears the app's cache and data directories via the ext.fdb.clean
/// VM service extension registered by fdb_helper.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<CleanResult> cleanApp(CleanInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const CleanNoFdbHelper();

    final response = await vmServiceCall(
      'ext.fdb.clean',
      params: {'isolateId': isolateId},
    );
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final error = result['error'] as String?;
      if (error != null) return CleanError(error);

      if (result['status'] == 'Success') {
        final dirs = (result['dirs'] as List<dynamic>?)?.cast<String>() ?? [];
        final deleted = result['deletedEntries'] as int? ?? 0;
        return CleanSuccess(dirs: dirs, deletedEntries: deleted);
      }
    }

    return CleanUnexpectedResponse(jsonEncode(result));
  } on AppDiedException catch (e) {
    return CleanAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return CleanError(e.toString());
  }
}
