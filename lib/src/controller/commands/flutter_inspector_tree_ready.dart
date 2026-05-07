import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FlutterInspectorTreeReadyCommandRequest extends IsolateIdCommandRequest {
  const FlutterInspectorTreeReadyCommandRequest({required super.token, required super.isolateId});
  factory FlutterInspectorTreeReadyCommandRequest.fromJson(Map<String, Object?> json) =>
      FlutterInspectorTreeReadyCommandRequest(
          token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorWidgetTreeReady;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FlutterInspectorTreeReadyCommandRunner();
}

class FlutterInspectorTreeReadyCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorTreeReadyCommandResponse(this.ready);

  factory FlutterInspectorTreeReadyCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    if (response.containsKey('ready')) {
      return FlutterInspectorTreeReadyCommandResponse(response['ready'] == true);
    }
    return FlutterInspectorTreeReadyCommandResponse(
      response['error'] == null && response['errorCode'] == null && response['errorMessage'] == null,
    );
  }

  final bool ready;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'ready': ready};
}

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
