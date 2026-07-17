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

class FdbSwipePathCommandRequest extends IsolateIdCommandRequest {
  const FdbSwipePathCommandRequest({
    required super.token,
    required super.isolateId,
    required this.points,
    this.precision,
  });
  factory FdbSwipePathCommandRequest.fromJson(Map<String, Object?> json) => FdbSwipePathCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        points: ControllerJson.requiredString(json, 'points'),
        precision: double.tryParse(ControllerJson.optionalString(json, 'precision') ?? ''),
      );

  final String points;
  final double? precision;

  @override
  ControllerCommand get command => ControllerCommand.fdbSwipePath;

  Map<String, dynamic> toVmParams() => {
        'isolateId': isolateId,
        'points': points,
        if (precision != null) 'precision': '$precision',
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'points': points,
        if (precision != null) 'precision': '$precision',
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbSwipePathCommandRunner();
}

class FdbSwipePathCommandResponse extends FdbActionCommandResponse {
  const FdbSwipePathCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.pointCount,
  });

  factory FdbSwipePathCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbSwipePathCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      pointCount: result?['pointCount'] as int?,
      unexpected: result ?? response,
    );
  }

  final int? pointCount;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'pointCount': pointCount,
      };
}

class FdbSwipePathCommandRunner extends VmServiceCommand<FdbSwipePathCommandRequest> {
  const FdbSwipePathCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbSwipePathCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.swipePath',
      params: request.toVmParams(),
    );
    return FdbSwipePathCommandResponse.fromResponse(response);
  }
}
