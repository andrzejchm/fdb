import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/deeplink/deeplink.dart';

/// CLI adapter for `fdb deeplink <url>`.
///
/// Output contract:
///   `DEEPLINK_OPENED=<url>`                                  (success)
///   `ERROR: No URL provided`                                 (no positional arg)
///   `ERROR: No active fdb session found. Run fdb launch first.` (no session)
///   `ERROR: Deep links are only supported on Android devices and iOS simulators` (unsupported platform)
///   `ERROR: Failed to open deep link: <details>`            (open failed)
///   `WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator`
///            (written to stderr BEFORE open attempt for https:// on iOS)
Future<int> runDeeplinkCli(List<String> args) => runSimpleCliAdapter(
      args,
      _execute,
      helpText: 'Usage: fdb deeplink <url>',
    );

Future<int> _execute(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.isEmpty) {
    stderr.writeln('ERROR: No URL provided');
    return 1;
  }

  final url = positional.first;
  final result = await openDeeplink((url: url));
  return _format(result);
}

int _format(DeeplinkResult result) {
  switch (result) {
    case DeeplinkOpened(:final url, :final warning):
      if (warning != null) {
        stderr.writeln(warning);
      }
      stdout.writeln('DEEPLINK_OPENED=$url');
      return 0;
    case DeeplinkNoSession():
      stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
      return 1;
    case DeeplinkUnsupportedPlatform():
      stderr.writeln('ERROR: Deep links are only supported on Android devices and iOS simulators');
      return 1;
    case DeeplinkFailed(:final details):
      stderr.writeln('ERROR: Failed to open deep link: $details');
      return 1;
  }
}
