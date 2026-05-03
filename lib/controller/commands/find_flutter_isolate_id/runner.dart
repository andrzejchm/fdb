import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/controller_response.dart';
import 'request.dart';
import '../shared/runner.dart';

class FindFlutterIsolateIdCommandRunner extends VmServiceCommand<FindFlutterIsolateIdCommandRequest> {
  const FindFlutterIsolateIdCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FindFlutterIsolateIdCommandRequest request) async {
    final isolateId = await findFlutterIsolateIdForController();
    return ControllerResponse.success({'isolateId': isolateId});
  }
}
