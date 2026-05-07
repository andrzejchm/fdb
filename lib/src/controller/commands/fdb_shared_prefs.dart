import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbSharedPrefsCommandRequest extends ControllerRequest {
  const FdbSharedPrefsCommandRequest({
    required super.token,
    required this.method,
    this.sharedPrefsParams = const {},
  });
  factory FdbSharedPrefsCommandRequest.fromJson(Map<String, Object?> json) => FdbSharedPrefsCommandRequest(
        token: ControllerJson.token(json),
        method: ControllerJson.requiredString(json, 'method'),
        sharedPrefsParams: ControllerJson.map(json, 'params'),
      );

  final String method;
  final Map<String, dynamic> sharedPrefsParams;

  @override
  ControllerCommand get command => ControllerCommand.fdbSharedPrefs;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'method': method,
        'params': sharedPrefsParams,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbSharedPrefsCommandRunner();
}

class FdbSharedPrefsCommandResponse extends VmServiceCommandResponse {
  const FdbSharedPrefsCommandResponse({
    required this.error,
    required this.exists,
    required this.value,
    required this.values,
  });

  factory FdbSharedPrefsCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbSharedPrefsCommandResponse(
      error: result?['error'] as String?,
      exists: result?['exists'] as bool?,
      value: result?['value'],
      values: result?['values'] as Map<String, dynamic>?,
    );
  }

  @override
  final String? error;
  final bool? exists;
  final Object? value;
  final Map<String, dynamic>? values;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'exists': exists,
        'value': value,
        'values': values,
      };
}

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
