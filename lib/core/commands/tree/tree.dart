import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tree/tree_models.dart';
import 'package:fdb/controller/controller_client.dart';

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

    final result = await flutterInspectorRootWidgetSummaryTree(
      isolateId,
      objectGroup: 'fdb_tree',
    );

    final tree = result.tree;
    if (tree == null) return const TreeNoWidgetTree();

    return TreeReceived(tree);
  } on AppDiedException catch (e) {
    return TreeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return TreeError(e.toString());
  }
}
