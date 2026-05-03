import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/core/commands/status/status_models.dart';
import 'package:fdb/controller/controller_client.dart';

export 'package:fdb/core/commands/status/status_models.dart';

/// Checks whether the Flutter app session is running.
///
/// Never throws. Returns a [StatusResult] with [StatusResult.running] set to
/// `false` when there is no active session.
Future<StatusResult> getStatus(StatusInput _) async {
  try {
    final response = await sendControllerCommand(
      ControllerCommand.status,
      timeout: const Duration(seconds: 3),
    );
    final running = response.field('running') == true;
    return StatusResult(
      running: running,
      pid: response.field('pid') as int?,
      vmServiceUri: running ? response.field('vmServiceUri') as String? : null,
    );
  } on ControllerCommandFailed {
    return const StatusResult(running: false);
  } on ControllerUnavailable {
    return const StatusResult(running: false);
  }
}
