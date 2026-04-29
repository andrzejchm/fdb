import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [getWidgetTree].
typedef TreeInput = ({int maxDepth, bool userOnly});

/// Result of a [getWidgetTree] invocation.
sealed class TreeResult extends CommandResult {
  const TreeResult();
}

/// Widget tree retrieved successfully; [rootNode] is the raw VM service map.
class TreeReceived extends TreeResult {
  const TreeReceived(this.rootNode);
  final Map<String, dynamic> rootNode;
}

/// No Flutter isolate was found in the running app.
class TreeNoIsolate extends TreeResult {
  const TreeNoIsolate();
}

/// The VM service returned no widget tree (null or unexpected shape).
class TreeNoWidgetTree extends TreeResult {
  const TreeNoWidgetTree();
}

/// The app process died while fdb was communicating with it.
class TreeAppDied extends TreeResult {
  const TreeAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class TreeError extends TreeResult {
  const TreeError(this.message);
  final String message;
}

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
