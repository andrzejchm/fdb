import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/doctor/doctor.dart';

/// CLI adapter for `fdb doctor`.
///
/// Runs all 5 diagnostic checks in order, emitting one `DOCTOR_CHECK=...`
/// line per check followed by a `DOCTOR_SUMMARY=...` line. Exit code is
/// always 0.
Future<int> runDoctorCli(List<String> args) => runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await runDoctor([]);
  _format(result);
  return 0;
}

void _format(DoctorResult result) {
  for (final check in result.checks) {
    _printCheck(check.name, check.status.name, values: check.values, hint: check.hint);
  }
  final summary = result.failedCount == 0 ? 'pass' : 'fail';
  stdout.writeln('DOCTOR_SUMMARY=$summary CHECKS=5 FAILED=${result.failedCount}');
}

void _printCheck(
  String name,
  String status, {
  Map<String, String> values = const {},
  String? hint,
}) {
  final parts = [
    'DOCTOR_CHECK=$name',
    'STATUS=$status',
    for (final entry in values.entries)
      if (entry.value.isNotEmpty) '${entry.key}=${entry.value}',
    if (hint != null) 'HINT=$hint',
  ];
  stdout.writeln(parts.join(' '));
}
