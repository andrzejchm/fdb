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

class FdbScreenshotCommandRequest extends IsolateIdCommandRequest {
  const FdbScreenshotCommandRequest({required super.token, required super.isolateId});
  factory FdbScreenshotCommandRequest.fromJson(Map<String, Object?> json) => FdbScreenshotCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbScreenshot;

  Map<String, dynamic> toVmParams() => {'isolateId': isolateId};

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbScreenshotCommandRunner();
}

class FdbScreenshotCommandResponse extends VmServiceCommandResponse {
  const FdbScreenshotCommandResponse({
    required this.error,
    required this.screenshot,
  });

  factory FdbScreenshotCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScreenshotCommandResponse(
      error: result?['error'] as String?,
      screenshot: result?['screenshot'] as String?,
    );
  }

  @override
  final String? error;
  final String? screenshot;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'screenshot': screenshot,
      };
}

class FdbScreenshotCommandRunner extends VmServiceCommand<FdbScreenshotCommandRequest> {
  const FdbScreenshotCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScreenshotCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.screenshot',
      params: request.toVmParams(),
    );
    return FdbScreenshotCommandResponse.fromResponse(response);
  }
}
