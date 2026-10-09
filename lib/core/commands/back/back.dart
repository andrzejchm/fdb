import 'package:fdb/core/commands/back/back_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/back/back_models.dart';

/// Presses the system back button in the running Flutter app, the same way the
/// Android back button does (fdb_helper injects the engine's `popRoute`).
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<BackResult> navigateBack(BackInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const BackNoHelper();

    final result = await fdbBack(isolateId);

    if (result.isSuccess) {
      return (result.popped ?? false) ? const BackPopped() : BackAtRoot(passedToOs: result.passedToOs);
    }

    if (result.error != null) return BackVmError(result.error!);

    return BackUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return BackAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return BackError(e.toString());
  }
}
