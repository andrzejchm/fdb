import 'dart:io';

import 'package:fdb/process_utils.dart';

Future<int> runStatus(List<String> args) async {
  final pid = readPid();
  final vmUri = readVmUri();
  final running = pid != null && isProcessAlive(pid);

  stdout.writeln('RUNNING=$running');
  if (pid != null) stdout.writeln('PID=$pid');
  if (vmUri != null) stdout.writeln('VM_SERVICE_URI=$vmUri');

  return 0;
}
