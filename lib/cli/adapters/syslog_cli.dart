import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/syslog/syslog.dart';

/// CLI adapter for `fdb syslog`.
///
/// Validates arguments, delegates to [runSyslog], then pipes the resulting
/// [SyslogStream] to stdout.  Handles SIGINT for follow mode by calling
/// [SyslogStream.cancel] so the subprocess is terminated cleanly.
Future<int> runSyslogCli(List<String> args) => runCliAdapter(
      ArgParser()
        ..addOption(
          'since',
          defaultsTo: '5m',
          help: 'Time window (e.g. 30s, 5m, 1h)',
        )
        ..addOption('predicate', help: 'Filter substring')
        ..addOption('last', help: 'Show last N lines')
        ..addFlag('follow', negatable: false, help: 'Stream live logs'),
      args,
      _execute,
    );

Future<int> _execute(ArgResults results) async {
  final follow = results['follow'] as bool;
  final sinceExplicit = results.wasParsed('since');
  final since = results['since'] as String;
  final predicate = results['predicate'] as String?;

  // --last validation
  final lastRaw = results['last'] as String?;
  int? last;
  if (lastRaw != null) {
    last = int.tryParse(lastRaw);
    if (last == null) {
      stderr.writeln('ERROR: Invalid value for --last: $lastRaw');
      return 1;
    }
    if (last <= 0) {
      stderr.writeln('ERROR: --last must be a positive integer');
      return 1;
    }
  }

  // Mutually exclusive flag validation
  if (follow && last != null) {
    stderr.writeln('ERROR: --last is not supported with --follow');
    return 1;
  }

  if (follow && sinceExplicit) {
    stderr.writeln(
      'ERROR: --since is not supported with --follow (log stream always starts from now)',
    );
    return 1;
  }

  // --since format validation
  if (!_isValidSince(since)) {
    stderr.writeln(
      'ERROR: Invalid --since value: $since. '
      'Use a number followed by s, m, or h (e.g. 30s, 5m, 1h)',
    );
    return 1;
  }

  final input = (
    since: since,
    sinceExplicit: sinceExplicit,
    predicate: predicate,
    last: last,
    follow: follow,
  );

  final result = await runSyslog(input);
  return _handle(result, follow: follow);
}

Future<int> _handle(SyslogResult result, {required bool follow}) async {
  switch (result) {
    case SyslogToolMissing(:final tool, :final hint):
      stderr.writeln('ERROR: $tool not found. $hint');
      return 1;

    case SyslogError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;

    case SyslogStream(:final lines, :final exitCode, :final cancel):
      // For follow mode, wire up SIGINT to cancel the stream early.
      // For snapshot mode, cancel is a no-op, so this is harmless.
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

/// Returns true if [s] is a valid duration string (`<positive-int>[smh]`).
bool _isValidSince(String s) {
  if (s.isEmpty) return false;
  final suffix = s[s.length - 1];
  if (!const {'s', 'm', 'h'}.contains(suffix)) return false;
  final n = int.tryParse(s.substring(0, s.length - 1));
  return n != null && n > 0;
}
