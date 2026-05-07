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

class FlutterInspectorTreeCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorTreeCommandResponse({required this.tree});

  factory FlutterInspectorTreeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final tree = response['tree'];
    if (tree is Map<String, dynamic>) {
      return FlutterInspectorTreeCommandResponse(tree: tree);
    }
    final result = unwrapExtensionResult(response);
    return FlutterInspectorTreeCommandResponse(
      tree: result ?? _directTree(response['result']) ?? _directTree(response),
    );
  }

  final Map<String, dynamic>? tree;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'tree': tree,
      };
}

Map<String, dynamic>? _directTree(Object? value) {
  if (value is Map<String, dynamic> && value['description'] is String && value['children'] is List) {
    return value;
  }
  return null;
}

class FlutterInspectorRootWidgetSummaryTreeCommandRunner
    extends VmServiceCommand<FlutterInspectorRootWidgetSummaryTreeCommandRequest> {
  const FlutterInspectorRootWidgetSummaryTreeCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(
    FlutterInspectorRootWidgetSummaryTreeCommandRequest request,
  ) async {
    final response = await callVmServiceMethod(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      params: {
        'isolateId': request.isolateId,
        'objectGroup': request.objectGroup,
      },
      timeout: const Duration(seconds: 60),
    );
    return FlutterInspectorTreeCommandResponse.fromResponse(response);
  }
}
