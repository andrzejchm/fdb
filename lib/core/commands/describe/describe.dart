import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/describe/describe_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/describe/describe_models.dart';

/// Returns a compact snapshot of the current screen via ext.fdb.describe.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<DescribeResult> describeScreen(DescribeInput _) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const DescribeNoFdbHelper();

    final response = await vmServiceCall(
      'ext.fdb.describe',
      params: {'isolateId': isolateId},
    );
    final result = unwrapRawExtensionResult(response);

    if (result is! Map<String, dynamic>) return const DescribeUnexpectedResponse();

    final error = result['error'] as String?;
    if (error != null) return DescribeRelayedError(error);

    return DescribeSuccess(result);
  } on AppDiedException catch (e) {
    return DescribeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return DescribeError(e.toString());
  }
}
