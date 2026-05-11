import 'package:fdb/core/commands/select/select_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/select/select_models.dart';

/// Toggles the Flutter inspector widget selection mode.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SelectResult> toggleSelection(SelectInput input) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return const SelectNoIsolate();

    final result = await flutterInspectorShow(isolateId, enabled: input.enabled);
    if (result.error != null) return SelectError(result.error!);

    return SelectSuccess(input.enabled);
  } on AppDiedException catch (e) {
    return SelectAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SelectError(e.toString());
  }
}
