import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbDescribeCommandRunner extends VmServiceCommand<FdbDescribeCommandRequest> {
  const FdbDescribeCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbDescribeCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.describe',
      params: {'isolateId': request.isolateId},
    );
    return FdbDescribeCommandResponse.fromResponse(response);
  }
}
