import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FlutterInspectorTreeReadyCommandRequest extends IsolateIdCommandRequest {
  const FlutterInspectorTreeReadyCommandRequest({required super.token, required super.isolateId});
  factory FlutterInspectorTreeReadyCommandRequest.fromJson(Map<String, Object?> json) =>
      FlutterInspectorTreeReadyCommandRequest(
          token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorWidgetTreeReady;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FlutterInspectorTreeReadyCommandRunner();
}
