import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/selected/selected_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/selected/selected_models.dart';

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
