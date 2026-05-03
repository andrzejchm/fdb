import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FlutterInspectorShowCommandRequest extends IsolateIdCommandRequest {
  const FlutterInspectorShowCommandRequest({
    required super.token,
    required super.isolateId,
    required this.enabled,
  });
  factory FlutterInspectorShowCommandRequest.fromJson(Map<String, Object?> json) => FlutterInspectorShowCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        enabled: ControllerJson.requiredBool(json, 'enabled'),
      );

  final bool enabled;

  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorShow;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'enabled': enabled,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FlutterInspectorShowCommandRunner();
}
