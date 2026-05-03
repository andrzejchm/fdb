import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

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
