import 'package:fdb/core/commands/describe/describe_models.dart';
import 'package:fdb/core/foreground_check.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/describe/describe_models.dart';

/// The text `fdb describe` shows for an interactive entry: its ` · `-separated
/// parts without empty and icon-only ones (Flutter icon codepoints are in the
/// Unicode private use area U+E000-U+F8FF). Null when nothing is left.
String? describeEntryText(String? text) {
  if (text == null) return null;
  final parts = text
      .split(' · ')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && p.runes.any((r) => r < 0xE000 || r > 0xF8FF))
      .toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

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
    return DescribeSuccess(snapshot, warnings: [if (warning != null) warning]);
  } on VmNotRespondingException catch (e) {
    return DescribeVmNotResponding(pid: e.pid);
  } on AppDiedException catch (e) {
    return DescribeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return DescribeError(e.toString());
  }
}
