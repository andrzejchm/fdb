/// Response field set by the `checkFdbHelper` controller command when the VM
/// service timed out AND a follow-up `getVM` probe also timed out — i.e. the
/// whole VM is unresponsive, not just the fdb_helper extension.
const vmNotRespondingField = 'vmNotResponding';

/// Thrown by `checkFdbHelper()` when the app process is alive but its VM
/// service does not respond at all. On iOS this almost always means the app
/// was backgrounded (another app brought to the front) and the OS suspended it.
///
/// [toString] is the user-facing message (without the `ERROR: ` prefix), so
/// commands that translate unknown exceptions to `ERROR: $e` get a clear
/// error instead of the misleading "fdb_helper not detected".
class VmNotRespondingException implements Exception {
  const VmNotRespondingException({this.pid});

  /// The app PID that was confirmed alive, or null when unknown.
  final int? pid;

  @override
  String toString() => vmNotRespondingMessage(pid);
}

/// User-facing message for [VmNotRespondingException] (no `ERROR: ` prefix).
String vmNotRespondingMessage(int? pid) {
  final alive = pid != null ? ' (pid $pid is alive)' : '';
  return 'App is not responding to the VM service$alive. It is most likely in '
      'the background and suspended by the OS (another app is in front). '
      'Bring it to the foreground, then retry.';
}
