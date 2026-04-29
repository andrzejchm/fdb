import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/select/select_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/select/select_models.dart';

/// Toggles the Flutter inspector widget selection mode.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SelectResult> toggleSelection(SelectInput input) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return const SelectNoIsolate();

    await vmServiceCall(
      'ext.flutter.inspector.show',
      params: {'isolateId': isolateId, 'enabled': input.enabled.toString()},
    );

    return SelectSuccess(input.enabled);
  } on AppDiedException catch (e) {
    return SelectAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SelectError(e.toString());
  }
}
