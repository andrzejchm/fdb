import 'dart:async';

import 'package:fdb/src/controller/app_died_exception.dart';
import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/vm_not_responding_exception.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class CheckFdbHelperCommandRequest extends ControllerRequest {
  const CheckFdbHelperCommandRequest({required super.token});
  factory CheckFdbHelperCommandRequest.fromJson(Map<String, Object?> json) =>
      CheckFdbHelperCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.checkFdbHelper;

  @override
  CommandRunner createRunner(ControllerContext controller) => const CheckFdbHelperCommandRunner();
}

class CheckFdbHelperCommandRunner extends VmServiceCommand<CheckFdbHelperCommandRequest> {
  const CheckFdbHelperCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(CheckFdbHelperCommandRequest request) async {
    try {
      final isolateId = await findFlutterIsolateIdForController();
      if (isolateId == null) {
        return ControllerResponse.success({'isolateId': null});
      }
      await callVmServiceMethod(
        'ext.fdb.elements',
        params: {'isolateId': isolateId},
        timeout: const Duration(seconds: 3),
      );
      return ControllerResponse.success({'isolateId': isolateId});
    } on AppDiedException {
      rethrow;
    } on TimeoutException {
      // A timeout alone may just mean ext.fdb.elements is slow or missing.
      // Probe the VM itself: if that also times out, the whole VM is
      // unresponsive (e.g. iOS suspended the backgrounded app).
      return ControllerResponse.success({
        'isolateId': null,
        if (await _isVmUnresponsive()) vmNotRespondingField: true,
      });
    } catch (_) {
      return ControllerResponse.success({'isolateId': null});
    }
  }
}

const _vmProbeTimeout = Duration(seconds: 2);

/// Returns true only when a plain `getVM` call times out. Any other outcome
/// (success, connection error) means the VM is responsive or gone, which the
/// existing "no fdb_helper" / app-died paths already handle.
Future<bool> _isVmUnresponsive() async {
  try {
    await getVm(timeout: _vmProbeTimeout);
    return false;
  } on AppDiedException {
    rethrow;
  } on TimeoutException {
    return true;
  } catch (_) {
    return false;
  }
}
