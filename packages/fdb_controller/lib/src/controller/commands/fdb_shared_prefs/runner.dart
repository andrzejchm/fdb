import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbSharedPrefsCommandRunner extends VmServiceCommand<FdbSharedPrefsCommandRequest> {
  const FdbSharedPrefsCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbSharedPrefsCommandRequest request) async {
    final response = await callVmServiceMethod(
      request.method,
      params: request.sharedPrefsParams,
    );
    return FdbSharedPrefsCommandResponse.fromResponse(response);
  }
}
