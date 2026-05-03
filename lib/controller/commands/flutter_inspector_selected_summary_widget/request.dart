import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FlutterInspectorSelectedSummaryWidgetCommandRequest extends ObjectGroupCommandRequest {
  const FlutterInspectorSelectedSummaryWidgetCommandRequest({
    required super.token,
    required super.isolateId,
    required super.objectGroup,
  });
  factory FlutterInspectorSelectedSummaryWidgetCommandRequest.fromJson(Map<String, Object?> json) =>
      FlutterInspectorSelectedSummaryWidgetCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        objectGroup: ControllerJson.requiredString(json, 'objectGroup'),
      );
  @override
  ControllerCommand get command => ControllerCommand.flutterInspectorSelectedSummaryWidget;

  @override
  CommandRunner createRunner(ControllerContext controller) =>
      const FlutterInspectorSelectedSummaryWidgetCommandRunner();
}
