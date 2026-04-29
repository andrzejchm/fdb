import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/logs.dart';

/// CLI adapter for `fdb logs`.
///
/// Validates arguments, delegates to [runLogs], then pipes the resulting
/// [LogsStream] to stdout. Handles SIGINT for follow mode by calling
/// [LogsStream.cancel] so the stream terminates cleanly.
Future<int> runLogsCli(List<String> args) => runCliAdapter(
      ArgParser()
        ..addOption('tag', help: 'Filter lines containing this string')
        ..addOption('last', defaultsTo: '50', help: 'Show last N lines (snapshot mode)')
        ..addFlag('follow', negatable: false, help: 'Stream live log updates'),
      args,
      _execute,
    );

Future<int> _execute(ArgResults results) async {
  final follow = results['follow'] as bool;
  final tag = results['tag'] as String?;
  final lastRaw = results['last'] as String;

  final last = int.tryParse(lastRaw);
  if (last == null) {
    stderr.writeln('ERROR: Invalid value for --last: $lastRaw');
    return 1;
  }

  final input = (
    tag: tag,
    last: last,
    follow: follow,
    logFilePath: logFile,
  );

  final result = await runLogs(input);
  return _handle(result, follow: follow);
}

Future<int> _handle(LogsResult result, {required bool follow}) async {
  switch (result) {
    case LogsFileNotFound():
      stderr.writeln('ERROR: Log file not found. Is the app running?');
      return 1;

    case LogsStream(:final lines, :final exitCode, :final cancel):
      StreamSubscription<ProcessSignal>? sigintSub;
      if (follow) {
        sigintSub = ProcessSignal.sigint.watch().listen((_) async {
          await cancel();
          await sigintSub?.cancel();
        });
      }

      try {
        await for (final line in lines) {
          stdout.writeln(line);
        }
      } finally {
        await sigintSub?.cancel();
      }

      return exitCode;
  }
}
