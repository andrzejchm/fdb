import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/back/back_models.dart';
import 'package:fdb/controller/controller_client.dart';

export 'package:fdb/core/commands/back/back_models.dart';

/// Triggers Navigator.maybePop() in the running Flutter app.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<BackResult> navigateBack(BackInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const BackNoHelper();

    final result = await fdbBack(isolateId);

    if (result.isSuccess) {
      return (result.popped ?? false) ? const BackPopped() : const BackAtRoot();
    }

    if (result.error != null) return BackVmError(result.error!);

    return BackUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return BackAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return BackError(e.toString());
  }
}
