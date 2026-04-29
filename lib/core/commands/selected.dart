import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [getSelected]. Empty record because `fdb selected`
/// takes no arguments today.
typedef SelectedInput = ();

/// Result of a [getSelected] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class SelectedResult extends CommandResult {
  const SelectedResult();
}

/// No Flutter isolate was found in the running app.
class SelectedNoIsolate extends SelectedResult {
  const SelectedNoIsolate();
}

/// No widget is currently selected in the inspector.
class SelectedNone extends SelectedResult {
  const SelectedNone();
}

/// A widget is selected; carries its description and optional source location.
class SelectedWidget extends SelectedResult {
  const SelectedWidget({required this.description, this.location});

  /// The widget's description string (e.g. `"Text"`).
  final String description;

  /// Optional source location in `"file.dart:42"` or `"file.dart"` form.
  final String? location;
}

/// The app process died while fdb was communicating with it.
class SelectedAppDied extends SelectedResult {
  const SelectedAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SelectedError extends SelectedResult {
  const SelectedError(this.message);
  final String message;
}

/// Retrieves the currently selected widget from the Flutter inspector.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SelectedResult> getSelected(SelectedInput _) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return const SelectedNoIsolate();

    final response = await vmServiceCall(
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_selected'},
    );

    final widget = unwrapExtensionResult(response);
    if (widget == null || widget is! Map<String, dynamic>) {
      return const SelectedNone();
    }

    final description = widget['description'] as String? ?? 'Unknown';
    final creationLocation = widget['creationLocation'] as Map<String, dynamic>?;

    if (creationLocation != null) {
      final file = (creationLocation['file'] as String? ?? '').split('/').last;
      final line = creationLocation['line'] as int?;
      final location = line != null ? '$file:$line' : file;
      return SelectedWidget(description: description, location: location);
    }

    return SelectedWidget(description: description);
  } on AppDiedException catch (e) {
    return SelectedAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SelectedError(e.toString());
  }
}
