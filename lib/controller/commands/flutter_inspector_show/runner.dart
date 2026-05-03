import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FlutterInspectorShowCommandRunner extends VmServiceCommand<FlutterInspectorShowCommandRequest> {
  const FlutterInspectorShowCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FlutterInspectorShowCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.show',
      params: {
        'isolateId': request.isolateId,
        'enabled': request.enabled.toString(),
      },
    );
    return FlutterInspectorShowCommandResponse.fromResponse(response);
  }
}
