import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/fdb_widget_action_response.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbTapCommandRequest extends WidgetSelectorCommandRequest {
  const FdbTapCommandRequest({
    required super.token,
    required super.isolateId,
    super.text,
    super.key,
    super.type,
    super.index,
    super.x,
    super.y,
    this.refType,
    this.refKey,
    this.refX,
    this.refY,
  });

  /// Identity of an `fdb describe` entry for `fdb tap @N`: type, key and centre.
  final String? refType;
  final String? refKey;
  final String? refX;
  final String? refY;

  factory FdbTapCommandRequest.fromJson(Map<String, Object?> json) => FdbTapCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
        x: ControllerJson.optionalString(json, 'x'),
        y: ControllerJson.optionalString(json, 'y'),
        refType: ControllerJson.optionalString(json, 'refType'),
        refKey: ControllerJson.optionalString(json, 'refKey'),
        refX: ControllerJson.optionalString(json, 'refX'),
        refY: ControllerJson.optionalString(json, 'refY'),
      );

  Map<String, String> get _refParams => {
        if (refType != null) 'refType': refType!,
        if (refKey != null) 'refKey': refKey!,
        if (refX != null) 'refX': refX!,
        if (refY != null) 'refY': refY!,
      };

  @override
  Map<String, dynamic> toVmParams() => {...super.toVmParams(), ..._refParams};

  @override
  Map<String, Object?> toJson() => {...super.toJson(), ..._refParams};

  @override
  ControllerCommand get command => ControllerCommand.fdbTap;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbTapCommandRunner();
}

class FdbTapCommandResponse extends FdbWidgetActionCommandResponse {
  const FdbTapCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required super.widgetType,
    required super.x,
    required super.y,
    required super.warning,
  });

  factory FdbTapCommandResponse.fromResponse(Map<String, dynamic> response) =>
      widgetActionResult(response, FdbTapCommandResponse.new);
}

class FdbTapCommandRunner extends VmServiceCommand<FdbTapCommandRequest> {
  const FdbTapCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbTapCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.tap',
      params: request.toVmParams(),
    );
    return FdbTapCommandResponse.fromResponse(response);
  }
}
