import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class GetAllocationProfileCommandRequest extends IsolateIdCommandRequest {
  const GetAllocationProfileCommandRequest({
    required super.token,
    required super.isolateId,
    this.gc,
    this.reset,
  });
  factory GetAllocationProfileCommandRequest.fromJson(Map<String, Object?> json) => GetAllocationProfileCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        gc: ControllerJson.optionalBool(json, 'gc'),
        reset: ControllerJson.optionalBool(json, 'reset'),
      );

  final bool? gc;
  final bool? reset;

  @override
  ControllerCommand get command => ControllerCommand.getAllocationProfile;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (gc != null) 'gc': gc,
        if (reset != null) 'reset': reset,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetAllocationProfileCommandRunner();
}
