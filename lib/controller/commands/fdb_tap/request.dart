import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

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
  });
  factory FdbTapCommandRequest.fromJson(Map<String, Object?> json) => FdbTapCommandRequest(
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
  ControllerCommand get command => ControllerCommand.fdbTap;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbTapCommandRunner();
}
