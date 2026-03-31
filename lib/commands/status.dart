import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Reports whether the Flutter app is running for a given device.
///
/// Unlike other commands, this intentionally does NOT use [resolveSession].
/// Status must never error — it always reports RUNNING=true or RUNNING=false,
/// even when no session exists or multiple sessions are active. Using
/// [resolveSession] would write errors to stderr and return null for those
/// cases, which would break callers that poll status to detect app state.
Future<int> runStatus(List<String> args) async {
  String? deviceId;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
    }
  }

  final Map<String, dynamic>? session;
  if (deviceId != null) {
    // Specific device requested — read that session directly (may be null).
    session = readSession(deviceId);
  } else {
    // No device specified — pick the single active session, if any.
    final active = findActiveSessions();
    session = active.length == 1 ? active.first : null;
  }

  if (session == null) {
    // No session found — app is not running.
    stdout.writeln('RUNNING=false');
    return 0;
  }

  final pidRaw = session['pid'];
  final pid =
      pidRaw is int ? pidRaw : (pidRaw is String ? int.tryParse(pidRaw) : null);
  final vmUri = session['vmServiceUri'] as String?;
  final running = pid != null && isProcessAlive(pid);

  stdout.writeln('RUNNING=$running');
  if (pid != null) stdout.writeln('PID=$pid');
  if (vmUri != null) stdout.writeln('VM_SERVICE_URI=$vmUri');

  return 0;
}
