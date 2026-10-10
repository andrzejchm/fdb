import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/deeplink/deeplink.dart';

/// CLI adapter for `fdb deeplink <url> [--device <id>]`.
///
/// Output contract:
///   `DEEPLINK_OPENED=<url>`                                  (success)
///   `ERROR: No URL provided`                                 (no positional arg)
///   `ERROR: No active fdb session found. Run fdb launch first.` (no session and no --device)
///   `ERROR: Deep links are only supported on Android devices and iOS simulators` (unsupported platform)
///   `ERROR: Failed to open deep link: <details>`            (open failed)
///   `ERROR: <message>`                                      (--device unknown, or simulator not booted)
///   `WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator`
///            (written to stderr before DEEPLINK_OPENED for https:// on iOS)
Future<int> runDeeplinkCli(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'device',
      valueHelp: 'id',
      help: "Target iOS simulator UDID or Android serial (default: the fdb session's device)",
    );
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: fdb deeplink <url> [--device <id>]\n\nOptions:\n${parser.usage}');
    return Future.value(0);
  }
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final positional = results.rest;
  if (positional.isEmpty) {
    stderr.writeln('ERROR: No URL provided');
    return 1;
  }

  final url = positional.first;
  final result = await openDeeplink((url: url, deviceOverride: results.option('device')));
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
    case DeeplinkDeviceUnresolved(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
