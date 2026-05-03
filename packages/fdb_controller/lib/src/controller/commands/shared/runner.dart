import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'package:fdb_controller/src/controller/controller_response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import 'package:fdb_controller/src/app_died_exception.dart';
import '../flutter_inspector_tree_ready/response.dart';

class VmServiceCommand<T extends ControllerRequest> implements CommandRunner {
  const VmServiceCommand(this.executeVmCommand);

  final Future<CommandResponse> Function(T request) executeVmCommand;

  @override
  Future<CommandResponse> execute(ControllerRequest request) async {
    try {
      return executeVmCommand(request as T);
    } on AppDiedException catch (e) {
      return ControllerResponse.appDied(logLines: e.logLines, reason: e.reason);
    }
  }
}

Future<String?> findFlutterIsolateIdForController() async {
  final vm = await getVm();
  final ids = vm?.isolates ?? const <String>[];
  for (final id in ids) {
    try {
      final response = await callVmServiceMethod(
        'ext.flutter.inspector.isWidgetTreeReady',
        params: {'isolateId': id},
        timeout: const Duration(seconds: 5),
      );
      final result = FlutterInspectorTreeReadyCommandResponse.fromResponse(
        response,
      );
      if (result.ready) return id;
    } on AppDiedException {
      rethrow;
    } catch (_) {
      // This isolate doesn't have Flutter inspector, try next.
    }
  }
  return ids.isNotEmpty ? ids.last : null;
}
