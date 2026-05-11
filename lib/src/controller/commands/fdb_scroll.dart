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

class FdbScrollCommandRequest extends IsolateIdCommandRequest {
  const FdbScrollCommandRequest({
    required super.token,
    required super.isolateId,
    this.direction,
    this.distance,
    this.at,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
  });
  factory FdbScrollCommandRequest.fromJson(Map<String, Object?> json) => FdbScrollCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        direction: ControllerJson.optionalString(json, 'direction'),
        distance: ControllerJson.optionalString(json, 'distance'),
        at: ControllerJson.optionalString(json, 'at'),
        startX: ControllerJson.optionalString(json, 'startX'),
        startY: ControllerJson.optionalString(json, 'startY'),
        endX: ControllerJson.optionalString(json, 'endX'),
        endY: ControllerJson.optionalString(json, 'endY'),
      );

  final String? direction;
  final String? distance;
  final String? at;
  final String? startX;
  final String? startY;
  final String? endX;
  final String? endY;

  @override
  ControllerCommand get command => ControllerCommand.fdbScroll;

  Map<String, dynamic> toVmParams() => {
        'isolateId': isolateId,
        if (direction != null) 'direction': direction,
        if (distance != null) 'distance': distance,
        if (at != null) 'at': at,
        if (startX != null) 'startX': startX,
        if (startY != null) 'startY': startY,
        if (endX != null) 'endX': endX,
        if (endY != null) 'endY': endY,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (direction != null) 'direction': direction,
        if (distance != null) 'distance': distance,
        if (at != null) 'at': at,
        if (startX != null) 'startX': startX,
        if (startY != null) 'startY': startY,
        if (endX != null) 'endX': endX,
        if (endY != null) 'endY': endY,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbScrollCommandRunner();
}

class FdbScrollCommandResponse extends FdbActionCommandResponse {
  const FdbScrollCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
  });

  factory FdbScrollCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScrollCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      unexpected: result ?? response,
    );
  }
}

class FdbScrollCommandRunner extends VmServiceCommand<FdbScrollCommandRequest> {
  const FdbScrollCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScrollCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.scroll',
      params: request.toVmParams(),
    );
    return FdbScrollCommandResponse.fromResponse(response);
  }
}
