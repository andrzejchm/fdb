import 'dart:convert';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/clean/clean_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/clean/clean_models.dart';

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
