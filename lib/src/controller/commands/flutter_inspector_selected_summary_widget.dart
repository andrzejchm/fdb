import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

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

class FlutterInspectorSelectedWidgetCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorSelectedWidgetCommandResponse({required this.widget});

  factory FlutterInspectorSelectedWidgetCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    final widget = response['widget'];
    if (widget is Map<String, dynamic>) {
      return FlutterInspectorSelectedWidgetCommandResponse(widget: widget);
    }
    final result = unwrapExtensionResult(response);
    return FlutterInspectorSelectedWidgetCommandResponse(
      widget: result is Map<String, dynamic> ? result : null,
    );
  }

  final Map<String, dynamic>? widget;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widget': widget,
      };
}

class FlutterInspectorSelectedSummaryWidgetCommandRunner
    extends VmServiceCommand<FlutterInspectorSelectedSummaryWidgetCommandRequest> {
  const FlutterInspectorSelectedSummaryWidgetCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(
    FlutterInspectorSelectedSummaryWidgetCommandRequest request,
  ) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {
        'isolateId': request.isolateId,
        'objectGroup': request.objectGroup,
      },
    );
    return FlutterInspectorSelectedWidgetCommandResponse.fromResponse(response);
  }
}
