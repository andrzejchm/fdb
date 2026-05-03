import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

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
