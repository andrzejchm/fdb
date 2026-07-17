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
    this.precision,
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
        precision: double.tryParse(ControllerJson.optionalString(json, 'precision') ?? ''),
      );

  final String direction;
  final String? key;
  final String? text;
  final String? type;
  final String? at;
  final String? distance;
  final double? precision;

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
        if (precision != null) 'precision': '$precision',
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
        if (precision != null) 'precision': '$precision',
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbSwipeCommandRunner();
}

class FdbSwipeCommandResponse extends FdbActionCommandResponse {
  const FdbSwipeCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.distance,
  });

  factory FdbSwipeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbSwipeCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      distance: result?['distance'],
      unexpected: result ?? response,
    );
  }

  final Object? distance;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'distance': distance,
      };
}

class FdbSwipeCommandRunner extends VmServiceCommand<FdbSwipeCommandRequest> {
  const FdbSwipeCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbSwipeCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.swipe',
      params: request.toVmParams(),
    );
    return FdbSwipeCommandResponse.fromResponse(response);
  }
}
