import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbScrollCommandRunner extends VmServiceCommand<FdbScrollCommandRequest> {
  const FdbScrollCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScrollCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.scroll',
      params: request.toVmParams(),
    );
    return FdbScrollCommandResponse.fromResponse(response);
  }
}
