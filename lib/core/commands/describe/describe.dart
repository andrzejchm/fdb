import 'package:fdb/core/commands/describe/describe_models.dart';
import 'package:fdb_controller/fdb_controller.dart';

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

    return DescribeSuccess(result.snapshot!);
  } on AppDiedException catch (e) {
    return DescribeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return DescribeError(e.toString());
  }
}
