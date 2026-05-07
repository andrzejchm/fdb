import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbDescribeCommandRequest extends IsolateIdCommandRequest {
  const FdbDescribeCommandRequest({required super.token, required super.isolateId});
  factory FdbDescribeCommandRequest.fromJson(Map<String, Object?> json) => FdbDescribeCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbDescribe;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbDescribeCommandRunner();
}

class FdbDescribeCommandResponse extends VmServiceCommandResponse {
  const FdbDescribeCommandResponse({
    required this.error,
    required this.snapshot,
    required this.unexpected,
  });

  factory FdbDescribeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final snapshot = response['snapshot'];
    if (response.containsKey('snapshot')) {
      return FdbDescribeCommandResponse(
        error: response['error'] as String?,
        snapshot: snapshot is Map<String, dynamic> ? snapshot : null,
        unexpected: response['unexpected'],
      );
    }
    final result = extensionResultAsMap(response);
    return FdbDescribeCommandResponse(
      error: result?['error'] as String?,
      snapshot: result,
      unexpected: result ?? response,
    );
  }

  @override
  final String? error;
  final Map<String, dynamic>? snapshot;
  final Object? unexpected;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'snapshot': snapshot,
        'unexpected': unexpected,
      };
}

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
