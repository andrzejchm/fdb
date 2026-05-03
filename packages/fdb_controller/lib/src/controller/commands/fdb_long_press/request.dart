import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbLongPressCommandRequest extends WidgetSelectorCommandRequest {
  const FdbLongPressCommandRequest({
    required super.token,
    required super.isolateId,
    required this.duration,
    super.text,
    super.key,
    super.type,
    super.index,
    super.x,
    super.y,
  });
  factory FdbLongPressCommandRequest.fromJson(Map<String, Object?> json) => FdbLongPressCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        duration: ControllerJson.requiredString(json, 'duration'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
        x: ControllerJson.optionalString(json, 'x'),
        y: ControllerJson.optionalString(json, 'y'),
      );

  final String duration;

  @override
  ControllerCommand get command => ControllerCommand.fdbLongPress;

  @override
  Map<String, dynamic> toVmParams() => {
        ...super.toVmParams(),
        'duration': duration,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'duration': duration,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbLongPressCommandRunner();
}
