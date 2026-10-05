import 'dart:async';

import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

/// Upper bound for [queryLifecycleState] so a hung VM never stalls a command.
const lifecycleQueryTimeout = Duration(seconds: 2);

/// Warning emitted when the lifecycle query times out while the app PID is
/// alive — the VM is unresponsive, most likely because the OS suspended the
/// backgrounded app.
const vmNotRespondingWarning = 'WARNING: App is not responding to the VM service; it is most likely in the '
    'background (suspended by the OS). The screenshot shows whatever is on screen, '
    'which may be another app.';

/// Outcome of [queryLifecycleState].
sealed class LifecycleQueryResult {
  const LifecycleQueryResult();
}

/// fdb_helper reported an `AppLifecycleState.name` (null if the engine has
/// not reported one yet).
class LifecycleReported extends LifecycleQueryResult {
  const LifecycleReported(this.state);
  final String? state;
}

/// The lifecycle could not be determined for a benign reason: no session,
/// no fdb_helper, an older fdb_helper without `ext.fdb.lifecycle`, app died,
/// or any other non-timeout failure. Callers stay silent.
class LifecycleUnavailable extends LifecycleQueryResult {
  const LifecycleUnavailable();
}

/// The query timed out while the app PID is alive: the VM is unresponsive.
class LifecycleVmNotResponding extends LifecycleQueryResult {
  const LifecycleVmNotResponding();
}

/// Returns a `WARNING: ...` line when [lifecycleState] (an
/// `AppLifecycleState.name` reported by fdb_helper) means the app is not the
/// visible foreground app, or null when it is (`resumed`) or unknown (null,
/// e.g. an older fdb_helper that does not report lifecycle).
String? foregroundWarning(String? lifecycleState) {
  switch (lifecycleState) {
    case null:
    case 'resumed':
      return null;
    case 'inactive':
      return 'WARNING: App is inactive (lifecycle=inactive). A system dialog, '
          'Control Center, or the app switcher may be covering it; output may '
          'not match what is on screen.';
    default:
      return 'WARNING: App is not in the foreground (lifecycle=$lifecycleState). '
          'Another app or the home screen is covering it; output reflects this '
          "app's last frame, not what is on screen. Bring it to the front "
          '(e.g. fdb deeplink, or relaunch) before trusting describe/screenshot.';
  }
}

/// Maps a [LifecycleQueryResult] to the warning line to emit, or null.
String? lifecycleQueryWarning(LifecycleQueryResult result) => switch (result) {
      LifecycleReported(:final state) => foregroundWarning(state),
      LifecycleUnavailable() => null,
      LifecycleVmNotResponding() => vmNotRespondingWarning,
    };

/// Classifies a failure of the lifecycle query. Only a timeout (or an explicit
/// [VmNotRespondingException]) with the app still alive counts as
/// "not responding"; everything else is [LifecycleUnavailable].
LifecycleQueryResult classifyLifecycleQueryError(Object error, {required bool appAlive}) {
  final timedOut = error is TimeoutException || error is VmNotRespondingException;
  return timedOut && appAlive ? const LifecycleVmNotResponding() : const LifecycleUnavailable();
}

/// Best-effort query of the app's lifecycle state via `ext.fdb.lifecycle`.
///
/// Never throws. Bounded by [timeout]. Uses `findFlutterIsolateId` rather
/// than `checkFdbHelper` because the latter walks the whole element tree,
/// which can be slow enough on big screens to blow the budget.
Future<LifecycleQueryResult> queryLifecycleState({Duration timeout = lifecycleQueryTimeout}) async {
  try {
    return await _queryLifecycleState().timeout(timeout);
  } catch (e) {
    // Foreground detection is advisory — never fail the calling command.
    return classifyLifecycleQueryError(e, appAlive: _isAppAlive());
  }
}

Future<LifecycleQueryResult> _queryLifecycleState() async {
  final isolateId = await findFlutterIsolateId();
  if (isolateId == null) return const LifecycleUnavailable();

  final response = await extCall('ext.fdb.lifecycle', params: {'isolateId': isolateId});
  // e.g. -32601 MethodNotFound on an older fdb_helper.
  if (response.errorCode != null) return const LifecycleUnavailable();

  // Through the controller the extension payload arrives one level down,
  // as `{result: {status, lifecycleState}}`.
  final payload = response.extensionResult;
  final inner = payload?['result'];
  final state = (inner is Map ? inner : payload)?['lifecycleState'];
  return LifecycleReported(state is String ? state : null);
}

/// True when the session's app PID is known and alive. Unknown PID counts as
/// alive (physical iOS reports alive too) — the timeout itself is the signal.
bool _isAppAlive() {
  try {
    final pid = readAppPid();
    return pid == null || isAppPidAlive(pid);
  } catch (_) {
    return false;
  }
}
