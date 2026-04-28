import 'dart:io';

import 'package:fdb/process_utils.dart';

Future<int> runStatus(List<String> args) async {
  final pid = readPid();
  final vmUri = readVmUri();

  // Primary check: PID file exists and process is alive.
  var running = pid != null && isProcessAlive(pid);

  // Fallback: the PID file may be absent or stale (e.g. fdb launch was killed
  // by an agent timeout after the Flutter app started but before APP_STARTED
  // was printed, or before --pid-file was written by flutter run). In that
  // case, probe the VM service URI directly. If the WebSocket connects, the
  // app is alive even though the PID check failed.
  if (!running && vmUri != null) {
    running = await isVmServiceReachable(vmUri);
  }

  stdout.writeln('RUNNING=$running');
  if (pid != null) stdout.writeln('PID=$pid');
  if (vmUri != null) stdout.writeln('VM_SERVICE_URI=$vmUri');

  return 0;
}
