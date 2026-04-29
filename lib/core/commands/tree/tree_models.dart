import 'package:fdb/core/models/command_result.dart';

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
