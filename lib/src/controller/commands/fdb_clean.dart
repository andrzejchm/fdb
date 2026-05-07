import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/fdb_action_response.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbCleanCommandRequest extends IsolateIdCommandRequest {
  const FdbCleanCommandRequest({required super.token, required super.isolateId});
  factory FdbCleanCommandRequest.fromJson(Map<String, Object?> json) => FdbCleanCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbClean;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbCleanCommandRunner();
}

class FdbCleanCommandResponse extends FdbActionCommandResponse {
  const FdbCleanCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.dirs,
    required this.deletedEntries,
  });

  factory FdbCleanCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbCleanCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      dirs: (result?['dirs'] as List<dynamic>?)?.cast<String>() ?? const [],
      deletedEntries: result?['deletedEntries'] as int?,
      unexpected: result ?? response,
    );
  }

  final List<String> dirs;
  final int? deletedEntries;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'dirs': dirs,
        'deletedEntries': deletedEntries,
      };
}

class FdbCleanCommandRunner extends VmServiceCommand<FdbCleanCommandRequest> {
  const FdbCleanCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbCleanCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.clean',
      params: {'isolateId': request.isolateId},
    );
    return FdbCleanCommandResponse.fromResponse(response);
  }
}
