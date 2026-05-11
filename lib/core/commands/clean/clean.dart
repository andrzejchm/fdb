import 'dart:convert';

import 'package:fdb/core/commands/clean/clean_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/clean/clean_models.dart';

/// Clears the app's cache and data directories via the ext.fdb.clean
/// VM service extension registered by fdb_helper.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<CleanResult> cleanApp(CleanInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const CleanNoFdbHelper();

    final result = await fdbClean(isolateId);

    if (result.error != null) return CleanError(result.error!);

    if (result.isSuccess) {
      return CleanSuccess(
        dirs: result.dirs,
        deletedEntries: result.deletedEntries ?? 0,
      );
    }

    return CleanUnexpectedResponse(jsonEncode(result.unexpected));
  } on AppDiedException catch (e) {
    return CleanAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return CleanError(e.toString());
  }
}
