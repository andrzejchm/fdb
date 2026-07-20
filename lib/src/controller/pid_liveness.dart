import 'dart:io';

/// Returns true if a process with [pid] is currently running.
///
/// Dart has no portable "is PID alive" API, so this shells out to a
/// platform-specific tool: `kill -0` on POSIX (macOS/Linux) and `tasklist`
/// on Windows. Never throws — any failure to invoke the tool is treated as
/// "not alive".
bool isProcessAlive(int pid) {
  return Platform.isWindows ? _isProcessAliveWindows(pid) : _isProcessAlivePosix(pid);
}

bool _isProcessAlivePosix(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// `tasklist` has no POSIX `kill -0` equivalent, so this filters by PID and
/// checks whether the CSV output contains a matching row. With no matching
/// process, `tasklist` still exits 0 but prints an "INFO: No tasks..."
/// message instead of a CSV row.
bool _isProcessAliveWindows(int pid) {
  try {
    final result = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
    if (result.exitCode != 0) return false;
    return tasklistOutputHasPid(result.stdout as String, pid);
  } catch (_) {
    return false;
  }
}

/// Returns true if [output] — `tasklist`'s CSV output filtered to a single
/// PID — contains a matching row for [pid].
///
/// Split out from [_isProcessAliveWindows] so the parsing logic can be
/// unit-tested against captured `tasklist` output without requiring an
/// actual Windows host.
bool tasklistOutputHasPid(String output, int pid) {
  final trimmed = output.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.toUpperCase().contains('NO TASKS')) return false;
  return trimmed.contains('"$pid"');
}
