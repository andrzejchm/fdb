import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbEnterTextCommandRequest extends WidgetSelectorCommandRequest {
  const FdbEnterTextCommandRequest({
    required super.token,
    required super.isolateId,
    required this.input,
    this.focused,
    super.text,
    super.key,
    super.type,
    super.index,
  });
  factory FdbEnterTextCommandRequest.fromJson(Map<String, Object?> json) => FdbEnterTextCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        input: ControllerJson.requiredString(json, 'input'),
        focused: ControllerJson.optionalString(json, 'focused'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
      );

  final String input;
  final String? focused;

  @override
  ControllerCommand get command => ControllerCommand.fdbEnterText;

  @override
  Map<String, dynamic> toVmParams() => {
        ...super.toVmParams(),
        'input': input,
        if (focused != null) 'focused': focused,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'input': input,
        if (focused != null) 'focused': focused,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbEnterTextCommandRunner();
}
