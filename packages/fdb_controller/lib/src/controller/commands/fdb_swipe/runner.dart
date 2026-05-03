import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbSwipeCommandRunner extends VmServiceCommand<FdbSwipeCommandRequest> {
  const FdbSwipeCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbSwipeCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.swipe',
      params: request.toVmParams(),
    );
    return FdbSwipeCommandResponse.fromResponse(response);
  }
}
