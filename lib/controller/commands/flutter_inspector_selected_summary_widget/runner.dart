import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FlutterInspectorSelectedSummaryWidgetCommandRunner
    extends VmServiceCommand<FlutterInspectorSelectedSummaryWidgetCommandRequest> {
  const FlutterInspectorSelectedSummaryWidgetCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(
    FlutterInspectorSelectedSummaryWidgetCommandRequest request,
  ) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {
        'isolateId': request.isolateId,
        'objectGroup': request.objectGroup,
      },
    );
    return FlutterInspectorSelectedWidgetCommandResponse.fromResponse(response);
  }
}
