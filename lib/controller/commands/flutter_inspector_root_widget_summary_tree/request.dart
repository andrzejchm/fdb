import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FlutterInspectorRootWidgetSummaryTreeCommandRequest extends ObjectGroupCommandRequest {
  const FlutterInspectorRootWidgetSummaryTreeCommandRequest({
    required super.token,
    required super.isolateId,
    required super.objectGroup,
  });
  factory FlutterInspectorRootWidgetSummaryTreeCommandRequest.fromJson(Map<String, Object?> json) =>
      FlutterInspectorRootWidgetSummaryTreeCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        objectGroup: ControllerJson.requiredString(json, 'objectGroup'),
      );
  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorRootWidgetSummaryTree;

  @override
  CommandRunner createRunner(ControllerContext controller) =>
      const FlutterInspectorRootWidgetSummaryTreeCommandRunner();
}
