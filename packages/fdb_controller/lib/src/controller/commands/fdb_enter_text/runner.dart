import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbEnterTextCommandRunner extends VmServiceCommand<FdbEnterTextCommandRequest> {
  const FdbEnterTextCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbEnterTextCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.enterText',
      params: request.toVmParams(),
    );
    return FdbEnterTextCommandResponse.fromResponse(response);
  }
}
