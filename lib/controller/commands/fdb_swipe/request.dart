import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbSwipeCommandRequest extends IsolateIdCommandRequest {
  const FdbSwipeCommandRequest({
    required super.token,
    required super.isolateId,
    required this.direction,
    this.key,
    this.text,
    this.type,
    this.at,
    this.distance,
  });
  factory FdbSwipeCommandRequest.fromJson(Map<String, Object?> json) => FdbSwipeCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        direction: ControllerJson.requiredString(json, 'direction'),
        key: ControllerJson.optionalString(json, 'key'),
        text: ControllerJson.optionalString(json, 'text'),
        type: ControllerJson.optionalString(json, 'type'),
        at: ControllerJson.optionalString(json, 'at'),
        distance: ControllerJson.optionalString(json, 'distance'),
      );

  final String direction;
  final String? key;
  final String? text;
  final String? type;
  final String? at;
  final String? distance;

  @override
  ControllerCommand get command => ControllerCommand.fdbSwipe;

  Map<String, dynamic> toVmParams() => {
        'isolateId': isolateId,
        'direction': direction,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (type != null) 'type': type,
        if (at != null) 'at': at,
        if (distance != null) 'distance': distance,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'direction': direction,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (type != null) 'type': type,
        if (at != null) 'at': at,
        if (distance != null) 'distance': distance,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbSwipeCommandRunner();
}
