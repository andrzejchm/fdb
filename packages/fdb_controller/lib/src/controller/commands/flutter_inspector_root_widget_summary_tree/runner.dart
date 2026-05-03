import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FlutterInspectorRootWidgetSummaryTreeCommandRunner
    extends VmServiceCommand<FlutterInspectorRootWidgetSummaryTreeCommandRequest> {
  const FlutterInspectorRootWidgetSummaryTreeCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(
    FlutterInspectorRootWidgetSummaryTreeCommandRequest request,
  ) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      params: {
        'isolateId': request.isolateId,
        'objectGroup': request.objectGroup,
      },
      timeout: const Duration(seconds: 60),
    );
    return FlutterInspectorTreeCommandResponse.fromResponse(response);
  }
}
