import 'package:fdb/core/commands/status/status_models.dart';
import 'package:fdb/core/controller_client.dart';

export 'package:fdb/core/commands/status/status_models.dart';

/// Checks whether the Flutter app session is running.
///
/// Never throws. Returns a [StatusResult] with [StatusResult.running] set to
/// `false` when there is no active session.
Future<StatusResult> getStatus(StatusInput _) async {
  try {
    final response = await sendControllerCommand(
      'status',
      timeout: const Duration(seconds: 3),
    );
    final running = response['running'] == true;
    return StatusResult(
      running: running,
      pid: response['pid'] as int?,
      vmServiceUri: running ? response['vmServiceUri'] as String? : null,
    );
  } on ControllerUnavailable {
    return const StatusResult(running: false);
  }
}
