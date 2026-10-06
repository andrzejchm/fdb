import 'package:fdb/core/commands/describe/describe_models.dart';
import 'package:fdb/core/foreground_check.dart';
import 'package:fdb/core/helper_version_check.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/describe/describe_models.dart';

/// Returns a compact snapshot of the current screen via ext.fdb.describe.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<DescribeResult> describeScreen(DescribeInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const DescribeNoFdbHelper();

    final result = await fdbDescribe(isolateId);

    if (result.snapshot == null) return const DescribeUnexpectedResponse();

    if (result.error != null) return DescribeRelayedError(result.error!);

    final snapshot = result.snapshot!;
    final lifecycleState = snapshot['lifecycleState'];
    final warning = foregroundWarning(lifecycleState is String ? lifecycleState : null);
    final versionWarnings = helperVersionWarnings(
      running: RunningHelperVersion.fromPayload(snapshot),
      resolved: readSessionResolvedHelperVersion(),
    );
    return DescribeSuccess(snapshot, warnings: [if (warning != null) warning, ...versionWarnings]);
  } on VmNotRespondingException catch (e) {
    return DescribeVmNotResponding(pid: e.pid);
  } on AppDiedException catch (e) {
    return DescribeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return DescribeError(e.toString());
  }
}
