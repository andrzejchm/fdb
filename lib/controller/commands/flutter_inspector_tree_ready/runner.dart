import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FlutterInspectorTreeReadyCommandRunner extends VmServiceCommand<FlutterInspectorTreeReadyCommandRequest> {
  const FlutterInspectorTreeReadyCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FlutterInspectorTreeReadyCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.isWidgetTreeReady',
      params: {'isolateId': request.isolateId},
      timeout: const Duration(seconds: 5),
    );
    return FlutterInspectorTreeReadyCommandResponse.fromResponse(response);
  }
}
