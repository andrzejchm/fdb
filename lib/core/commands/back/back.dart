import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/back/back_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/back/back_models.dart';

/// Triggers Navigator.maybePop() in the running Flutter app.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<BackResult> navigateBack(BackInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const BackNoHelper();

    final response = await vmServiceCall(
      'ext.fdb.back',
      params: {'isolateId': isolateId},
    );
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final popped = result['popped'] as bool? ?? false;
        return popped ? const BackPopped() : const BackAtRoot();
      }

      if (error != null) return BackVmError(error);
    }

    return BackUnexpectedResponse(result);
  } on AppDiedException catch (e) {
    return BackAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return BackError(e.toString());
  }
}
