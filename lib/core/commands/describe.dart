import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [describeScreen]. Empty record because `fdb describe`
/// takes no arguments.
typedef DescribeInput = ();

/// Result of a [describeScreen] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class DescribeResult extends CommandResult {
  const DescribeResult();
}

/// ext.fdb.describe responded with a valid payload.
class DescribeSuccess extends DescribeResult {
  const DescribeSuccess(this.raw);

  /// The raw map returned by ext.fdb.describe (screen, route, interactive, texts).
  final Map<String, dynamic> raw;
}

/// fdb_helper was not detected in the running app.
class DescribeNoFdbHelper extends DescribeResult {
  const DescribeNoFdbHelper();
}

/// The VM service returned a response that is not a `Map<String, dynamic>`.
class DescribeUnexpectedResponse extends DescribeResult {
  const DescribeUnexpectedResponse();
}

/// The extension returned an error string in the `error` field.
class DescribeRelayedError extends DescribeResult {
  const DescribeRelayedError(this.message);
  final String message;
}

/// The app process died while fdb was communicating with it.
class DescribeAppDied extends DescribeResult {
  const DescribeAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class DescribeError extends DescribeResult {
  const DescribeError(this.message);
  final String message;
}

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
