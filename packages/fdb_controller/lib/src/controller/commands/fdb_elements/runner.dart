import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbElementsCommandRunner extends VmServiceCommand<FdbElementsCommandRequest> {
  const FdbElementsCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbElementsCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.elements',
      params: {'isolateId': request.isolateId},
      timeout: const Duration(seconds: 3),
    );
    return FdbElementsCommandResponse.fromResponse(response);
  }
}
