import 'package:fdb/core/commands/selected/selected_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/selected/selected_models.dart';

/// Retrieves the currently selected widget from the Flutter inspector.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SelectedResult> getSelected(SelectedInput _) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return const SelectedNoIsolate();

    final result = await flutterInspectorSelectedSummaryWidget(
      isolateId,
      objectGroup: 'fdb_selected',
    );

    final widget = result.widget;
    if (widget == null) return const SelectedNone();

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
