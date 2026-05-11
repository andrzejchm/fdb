import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FlutterInspectorShowCommandRequest extends IsolateIdCommandRequest {
  const FlutterInspectorShowCommandRequest({
    required super.token,
    required super.isolateId,
    required this.enabled,
  });
  factory FlutterInspectorShowCommandRequest.fromJson(Map<String, Object?> json) => FlutterInspectorShowCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        enabled: ControllerJson.requiredBool(json, 'enabled'),
      );

  final bool enabled;

  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorShow;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'enabled': enabled,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FlutterInspectorShowCommandRunner();
}

class FlutterInspectorShowCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorShowCommandResponse({required this.error});

  factory FlutterInspectorShowCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    if (response.containsKey('error') && response['error'] is String?) {
      return FlutterInspectorShowCommandResponse(error: response['error'] as String?);
    }
    final error = response['error'] as Map<String, dynamic>?;
    return FlutterInspectorShowCommandResponse(
      error: error?['message'] as String?,
    );
  }

  @override
  final String? error;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}

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
