import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbLongPressCommandRunner extends VmServiceCommand<FdbLongPressCommandRequest> {
  const FdbLongPressCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbLongPressCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.longPress',
      params: request.toVmParams(),
    );
    return FdbLongPressCommandResponse.fromResponse(response);
  }
}
