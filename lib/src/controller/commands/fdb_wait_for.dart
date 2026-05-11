import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/fdb_action_response.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbWaitForCommandRequest extends IsolateIdCommandRequest {
  const FdbWaitForCommandRequest({
    required super.token,
    required super.isolateId,
    required this.condition,
    required this.timeoutMilliseconds,
    this.text,
    this.key,
    this.type,
    this.route,
  });
  factory FdbWaitForCommandRequest.fromJson(Map<String, Object?> json) => FdbWaitForCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        condition: ControllerJson.requiredString(json, 'condition'),
        timeoutMilliseconds: ControllerJson.requiredInt(json, 'timeout'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        route: ControllerJson.optionalString(json, 'route'),
      );

  final String condition;
  final int timeoutMilliseconds;
  final String? text;
  final String? key;
  final String? type;
  final String? route;

  @override
  ControllerCommand get command => ControllerCommand.fdbWaitFor;

  Map<String, String> toVmStringParams() => {
        'isolateId': isolateId,
        'condition': condition,
        'timeout': timeoutMilliseconds.toString(),
        if (text != null) 'text': text!,
        if (key != null) 'key': key!,
        if (type != null) 'type': type!,
        if (route != null) 'route': route!,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'condition': condition,
        'timeout': timeoutMilliseconds,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (type != null) 'type': type,
        if (route != null) 'route': route,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbWaitForCommandRunner();
}

class FdbWaitForCommandResponse extends FdbActionCommandResponse {
  const FdbWaitForCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
  });

  factory FdbWaitForCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbWaitForCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      unexpected: result ?? response,
    );
  }
}

class FdbWaitForCommandRunner extends VmServiceCommand<FdbWaitForCommandRequest> {
  const FdbWaitForCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbWaitForCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.waitFor',
      params: Map<String, dynamic>.from(request.toVmStringParams()),
      timeout: Duration(milliseconds: request.timeoutMilliseconds + 5000),
    );
    return FdbWaitForCommandResponse.fromResponse(response);
  }
}
