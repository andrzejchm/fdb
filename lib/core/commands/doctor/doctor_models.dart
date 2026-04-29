import 'package:fdb/core/models/command_result.dart';

/// Status of a single doctor check.
enum CheckStatus { pass, warn, fail }

/// Result of one diagnostic check.
class CheckResult {
  final String name;
  final CheckStatus status;
  final Map<String, String> values;
  final String? hint;

  const CheckResult({
    required this.name,
    required this.status,
    this.values = const {},
    this.hint,
  });
}

/// Result of the full doctor diagnostic run.
///
/// [checks] is ordered: app_running, vm_service, fdb_helper, platform_tools, device.
/// [failedCount] is the number of checks with [CheckStatus.fail].
class DoctorResult extends CommandResult {
  final List<CheckResult> checks;
  final int failedCount;

  const DoctorResult({required this.checks, required this.failedCount});
}
