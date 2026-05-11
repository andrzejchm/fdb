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

class FdbScrollToCommandRequest extends WidgetSelectorCommandRequest {
  const FdbScrollToCommandRequest({
    required super.token,
    required super.isolateId,
    super.text,
    super.key,
    super.type,
    super.index,
  });
  factory FdbScrollToCommandRequest.fromJson(Map<String, Object?> json) => FdbScrollToCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
      );
  @override
  ControllerCommand get command => ControllerCommand.fdbScrollTo;

  Map<String, String> toVmStringParams() => {
        for (final entry in toVmParams().entries) entry.key: entry.value.toString(),
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbScrollToCommandRunner();
}

class FdbScrollToCommandResponse extends FdbActionCommandResponse {
  const FdbScrollToCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.widgetType,
    required this.x,
    required this.y,
  });

  factory FdbScrollToCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScrollToCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      widgetType: result?['widgetType'] as String?,
      x: (result?['x'] as num?)?.toDouble(),
      y: (result?['y'] as num?)?.toDouble(),
      unexpected: result ?? response,
    );
  }

  final String? widgetType;
  final double? x;
  final double? y;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widgetType': widgetType,
        'x': x,
        'y': y,
      };
}

class FdbScrollToCommandRunner extends VmServiceCommand<FdbScrollToCommandRequest> {
  const FdbScrollToCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScrollToCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.scrollTo',
      params: Map<String, dynamic>.from(request.toVmStringParams()),
    );
    return FdbScrollToCommandResponse.fromResponse(response);
  }
}
