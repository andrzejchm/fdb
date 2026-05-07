import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service.dart';

class FdbDoubleTapCommandRequest extends WidgetSelectorCommandRequest {
  const FdbDoubleTapCommandRequest({
    required super.token,
    required super.isolateId,
    super.text,
    super.key,
    super.type,
    super.index,
    super.x,
    super.y,
  });
  factory FdbDoubleTapCommandRequest.fromJson(Map<String, Object?> json) => FdbDoubleTapCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
        x: ControllerJson.optionalString(json, 'x'),
        y: ControllerJson.optionalString(json, 'y'),
      );
  @override
  ControllerCommand get command => ControllerCommand.fdbDoubleTap;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbDoubleTapCommandRunner();
}

class FdbDoubleTapCommandResponse extends FdbWidgetActionCommandResponse {
  const FdbDoubleTapCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required super.widgetType,
    required super.x,
    required super.y,
    required super.warning,
  });

  factory FdbDoubleTapCommandResponse.fromResponse(Map<String, dynamic> response) =>
      widgetActionResult(response, FdbDoubleTapCommandResponse.new);
}

class FdbDoubleTapCommandRunner extends VmServiceCommand<FdbDoubleTapCommandRequest> {
  const FdbDoubleTapCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbDoubleTapCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.doubleTap',
      params: request.toVmParams(),
    );
    return FdbDoubleTapCommandResponse.fromResponse(response);
  }
}
