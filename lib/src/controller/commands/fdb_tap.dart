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
    super.ref,
    super.x,
    super.y,
    this.expectText,
    this.expectType,
  });

  /// With [ref]: fail unless the widget still shows this text / has this type.
  final String? expectText;
  final String? expectType;

  factory FdbTapCommandRequest.fromJson(Map<String, Object?> json) => FdbTapCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
        ref: ControllerJson.optionalString(json, 'ref'),
        x: ControllerJson.optionalString(json, 'x'),
        y: ControllerJson.optionalString(json, 'y'),
        expectText: ControllerJson.optionalString(json, 'expectText'),
        expectType: ControllerJson.optionalString(json, 'expectType'),
      );

  Map<String, String> get _expectParams => {
        if (expectText != null) 'expectText': expectText!,
        if (expectType != null) 'expectType': expectType!,
      };

  @override
  Map<String, dynamic> toVmParams() => {...super.toVmParams(), ..._expectParams};

  @override
  Map<String, Object?> toJson() => {...super.toJson(), ..._expectParams};

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
    this.text,
  });

  /// For a ref tap: the text `fdb describe` shows for the tapped widget.
  final String? text;

  factory FdbTapCommandResponse.fromResponse(Map<String, dynamic> response) {
    final base = widgetActionResult(response, FdbTapCommandResponse.new);
    final text = extensionResultAsMap(response)?['text'];
    return FdbTapCommandResponse(
      status: base.status,
      error: base.error,
      unexpected: base.unexpected,
      widgetType: base.widgetType,
      x: base.x,
      y: base.y,
      warning: base.warning,
      text: text is String ? text : null,
    );
  }

  @override
  Map<String, Object?> toJson() => {...super.toJson(), if (text != null) 'text': text};
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
