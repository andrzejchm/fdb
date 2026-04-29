import 'dart:io';

import 'package:args/args.dart';

/// Runs a CLI adapter end-to-end:
///
/// 1. If [args] contains `--help` or `-h`, write [parser.usage] to stdout and
///    return 0.
/// 2. Otherwise parse the args, writing `ERROR: <message>` to stderr and
///    returning 1 on [FormatException] (which [ArgParserException] extends).
/// 3. On successful parse, invoke [execute] with the resulting [ArgResults].
///
/// Centralises all `--help` interception and parser-error formatting so
/// CLI adapter files don't repeat this boilerplate.
Future<int> runCliAdapter(
  ArgParser parser,
  List<String> args,
  Future<int> Function(ArgResults) execute,
) async {
  if (args.contains('--help') || args.contains('-h')) {
    final usage = parser.usage;
    stdout.writeln(usage.isEmpty ? 'No options for this command.' : usage);
    return 0;
  }
  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('ERROR: ${e.message}');
    return 1;
  }
  return execute(results);
}

/// Runs a CLI adapter that accepts no options. Skips ArgParser construction
/// entirely; just intercepts `--help`/`-h` and otherwise calls [execute] with
/// the raw [args] (allowing the executor to inspect positional arguments).
Future<int> runSimpleCliAdapter(
  List<String> args,
  Future<int> Function(List<String>) execute, {
  String helpText = 'No options for this command.',
}) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(helpText);
    return 0;
  }
  return execute(args);
}

/// Parses an `"x,y"` coordinate string into a `(double, double)` tuple, or
/// returns `null` if the input is malformed.
///
/// Used by CLI adapters that accept coordinate flags like `--at`, `--from`,
/// `--to`. The associated error message format is the adapter's responsibility.
(double, double)? parseXY(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0].trim());
  final y = double.tryParse(parts[1].trim());
  if (x == null || y == null) return null;
  return (x, y);
}
