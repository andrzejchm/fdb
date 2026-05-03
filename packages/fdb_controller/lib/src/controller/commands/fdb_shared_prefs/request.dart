import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

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
