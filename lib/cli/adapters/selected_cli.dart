import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/selected/selected.dart';

/// CLI adapter for `fdb selected`. Accepts no flags; emits one of:
///
/// ```
///   NO_WIDGET_SELECTED                          (no widget selected)
///   SELECTED: <desc> (<file>:<line>)            (widget with location + line)
///   SELECTED: <desc> (<file>)                   (widget with location, no line)
///   SELECTED: <desc>                            (widget, no location)
///   ERROR: No Flutter isolate found             (no isolate)
///   ERROR: <message>                            (generic error)
/// ```
Future<int> runSelectedCli(List<String> args) =>
    runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await getSelected(());
  return _format(result);
}

int _format(SelectedResult result) {
  switch (result) {
    case SelectedNoIsolate():
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    case SelectedNone():
      stdout.writeln('NO_WIDGET_SELECTED');
      return 0;
    case SelectedWidget():
      if (result.location != null) {
        stdout.writeln('SELECTED: ${result.description} (${result.location})');
      } else {
        stdout.writeln('SELECTED: ${result.description}');
      }
      return 0;
    case SelectedAppDied():
      throw AppDiedException(logLines: result.logLines, reason: result.reason);
    case SelectedError():
      stderr.writeln('ERROR: ${result.message}');
      return 1;
  }
}
