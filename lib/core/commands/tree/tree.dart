import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tree/tree_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/tree/tree_models.dart';

/// Fetches the root widget summary tree from the running Flutter app.
///
/// Never throws; all error conditions are represented as sealed result cases.
/// Presentation concerns (depth filtering, user-only filtering, indented
/// printing) are left to the caller / CLI adapter.
Future<TreeResult> getWidgetTree(TreeInput _) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return const TreeNoIsolate();

    final response = await vmServiceCall(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_tree'},
      timeout: const Duration(seconds: 60),
    );

    final tree = unwrapExtensionResult(response);
    if (tree == null || tree is! Map<String, dynamic>) {
      return const TreeNoWidgetTree();
    }

    return TreeReceived(tree);
  } on AppDiedException catch (e) {
    return TreeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return TreeError(e.toString());
  }
}
