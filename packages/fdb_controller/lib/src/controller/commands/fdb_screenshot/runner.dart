import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbScreenshotCommandRunner extends VmServiceCommand<FdbScreenshotCommandRequest> {
  const FdbScreenshotCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScreenshotCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.screenshot',
      params: request.toVmParams(),
    );
    return FdbScreenshotCommandResponse.fromResponse(response);
  }
}
