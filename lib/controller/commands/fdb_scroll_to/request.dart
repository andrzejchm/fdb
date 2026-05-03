import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

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
