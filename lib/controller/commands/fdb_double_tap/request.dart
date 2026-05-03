import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

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
