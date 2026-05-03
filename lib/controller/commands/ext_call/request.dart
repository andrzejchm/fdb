import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import 'package:fdb/controller/controller_request.dart';
import 'runner.dart';

class ExtCallCommandRequest extends ControllerRequest {
  const ExtCallCommandRequest({
    required super.token,
    required this.method,
    this.extensionParams = const {},
  });
  factory ExtCallCommandRequest.fromJson(Map<String, Object?> json) => ExtCallCommandRequest(
        token: ControllerJson.token(json),
        method: ControllerJson.requiredString(json, 'method'),
        extensionParams: ControllerJson.map(json, 'params'),
      );

  final String method;
  final Map<String, dynamic> extensionParams;

  @override
  ControllerCommand get command => ControllerCommand.extCall;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'method': method,
        'params': extensionParams,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const ExtCallCommandRunner();
}
