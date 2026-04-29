import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/wait/wait.dart';

/// CLI adapter for `fdb wait`. Accepts:
///
///   --present           wait until the selector is present
///   --absent            wait until the selector is absent
///   --key VALUE         select by ValueKey label
///   --text VALUE        select by visible text
///   --type VALUE        select by widget type name
///   --route VALUE       select by route name
///   --timeout MS        override timeout in milliseconds (default 10000)
Future<int> runWaitCli(List<String> args) {
  final parser = ArgParser()
    ..addFlag('present', negatable: false, help: 'Wait until selector is present')
    ..addFlag('absent', negatable: false, help: 'Wait until selector is absent')
    ..addOption('key', help: 'Select by ValueKey label')
    ..addOption('text', help: 'Select by visible text')
    ..addOption('type', help: 'Select by widget type name')
    ..addOption('route', help: 'Select by route name')
    ..addOption('timeout', help: 'Timeout in milliseconds (default 10000)');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  // Validate condition flags.
  final isPresent = results['present'] as bool;
  final isAbsent = results['absent'] as bool;

  if (!isPresent && !isAbsent || isPresent && isAbsent) {
    stderr.writeln('ERROR: Missing required flag: --present or --absent');
    return 1;
  }

  // Validate --timeout.
  final timeoutRaw = results['timeout'] as String?;
  int timeoutMs = 10000;
  if (timeoutRaw != null) {
    final parsed = int.tryParse(timeoutRaw);
    if (parsed == null) {
      stderr.writeln('ERROR: Invalid value for --timeout: $timeoutRaw');
      return 1;
    }
    timeoutMs = parsed;
  }

  // Validate exactly one selector.
  final key = results['key'] as String?;
  final text = results['text'] as String?;
  final type = results['type'] as String?;
  final route = results['route'] as String?;

  final selectorCount = [key, text, type, route].where((v) => v != null).length;
  if (selectorCount != 1) {
    stderr.writeln('ERROR: Missing selector: use --key, --text, --type, or --route');
    return 1;
  }

  final condition = isPresent ? WaitCondition.present : WaitCondition.absent;

  final result = await waitForWidget((
    text: text,
    key: key,
    type: type,
    route: route,
    condition: condition,
    timeoutMs: timeoutMs,
  ));

  return _format(result);
}

int _format(WaitResult result) {
  switch (result) {
    case WaitConditionMet(:final condition, :final selectorToken):
      stdout.writeln('CONDITION_MET=${condition.name} $selectorToken');
      return 0;
    case WaitNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case WaitRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case WaitUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.waitFor: $raw');
      return 1;
    case WaitAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case WaitError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
