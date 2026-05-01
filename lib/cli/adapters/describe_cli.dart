import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/describe/describe.dart';

/// CLI adapter for `fdb describe`. Accepts no flags; emits a compact
/// text snapshot of the current screen:
///
/// ```
///   SCREEN: <screen>                (if present)
///   ROUTE: <route>                  (if present)
///   <blank line>                    (if screen or route was printed)
///   INTERACTIVE:                    (if interactive list non-empty)
///     [<Ancestor> ["text"] [> ...]] (breadcrumb — only if meaningful)
///       @N <type>[(gestures)] ["text"] [key=<key>]
///   <blank line>
///   VISIBLE TEXT:                   (if non-duplicate texts exist)
///     "<text>"
/// ```
Future<int> runDescribeCli(List<String> args) => runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await describeScreen(());
  return _format(result);
}

int _format(DescribeResult result) {
  switch (result) {
    case DescribeSuccess(:final raw):
      _printDescribeOutput(raw);
      return 0;
    case DescribeNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case DescribeUnexpectedResponse():
      stderr.writeln('ERROR: Unexpected response from ext.fdb.describe');
      return 1;
    case DescribeRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case DescribeAppDied(:final logLines, :final reason):
      // Reconstruct and rethrow so bin/fdb.dart's existing _formatAppDied
      // handler produces the byte-identical output.
      throw AppDiedException(logLines: logLines, reason: reason);
    case DescribeError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

void _printDescribeOutput(Map<String, dynamic> result) {
  final screen = result['screen'] as String?;
  final route = result['route'] as String?;
  final interactive = result['interactive'] as List<dynamic>? ?? [];
  final texts = result['texts'] as List<dynamic>? ?? [];

  if (screen != null) stdout.writeln('SCREEN: $screen');
  if (route != null) stdout.writeln('ROUTE: $route');
  if (screen != null || route != null) stdout.writeln('');

  if (interactive.isNotEmpty) {
    stdout.writeln('INTERACTIVE:');
    for (final item in interactive) {
      final entry = item as Map<String, dynamic>;
      final ref = entry['ref'] as int;
      final type = entry['type'] as String;
      final key = entry['key'] as String?;
      final text = entry['text'] as String?;

      // Clean up text: filter empty fragments and icon-only fragments
      // (Flutter Icon codepoints are Unicode PUA chars U+E000-U+F8FF)
      var cleanText = text;
      if (cleanText != null) {
        final parts = cleanText
            .split(' · ')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty && p.runes.any((r) => r < 0xE000 || r > 0xF8FF))
            .toList();
        cleanText = parts.isEmpty ? null : parts.join(' · ');
      }

      final gestures = (entry['gestures'] as List<dynamic>?)?.cast<String>();
      final rawBreadcrumb = entry['breadcrumb'] as List<dynamic>?;

      // Print breadcrumb above the entry (closest ancestor first, reversed
      // to read outermost-first top-down).
      if (rawBreadcrumb != null && rawBreadcrumb.isNotEmpty) {
        final crumbParts = <String>[];
        for (final raw in rawBreadcrumb.reversed) {
          final crumb = raw as Map<String, dynamic>;
          final cType = crumb['type'] as String;
          final cKey = crumb['key'] as String?;
          final cText = crumb['text'] as String?;
          final cb = StringBuffer(cType);
          if (cKey != null) cb.write('(key=$cKey)');
          if (cText != null) cb.write(' "$cText"');
          crumbParts.add(cb.toString());
        }
        stdout.writeln('  ${crumbParts.join(' > ')}');
      }

      final indent = rawBreadcrumb != null && rawBreadcrumb.isNotEmpty ? '    ' : '  ';
      final buffer = StringBuffer('$indent@$ref $type');
      if (gestures != null && gestures.isNotEmpty) {
        buffer.write('(${gestures.join(',')})');
      }
      if (cleanText != null) buffer.write(' "$cleanText"');
      if (key != null) buffer.write(' key=$key');
      stdout.writeln(buffer.toString());
    }
    stdout.writeln('');
  }

  // Deduplicate texts already shown in the interactive section.
  // Split each interactive text on ' · ' to get individual fragments so that
  // e.g. "All Photos · 3999 photos" prevents both "All Photos" and
  // "3999 photos" from appearing in the VISIBLE TEXT section.
  final interactiveFragments = <String>{};
  for (final item in interactive) {
    final text = (item as Map<String, dynamic>)['text'] as String?;
    if (text != null) {
      for (final fragment in text.split(' · ')) {
        final trimmed = fragment.trim();
        if (trimmed.isNotEmpty) interactiveFragments.add(trimmed);
      }
    }
  }

  final uniqueTexts = texts
      .cast<String>()
      .where((t) =>
          t.trim().isNotEmpty &&
          t.runes.any((r) => r < 0xE000 || r > 0xF8FF) &&
          !interactiveFragments.contains(t.trim()))
      .toList();

  if (uniqueTexts.isNotEmpty) {
    stdout.writeln('VISIBLE TEXT:');
    for (final text in uniqueTexts) {
      stdout.writeln('  "$text"');
    }
  }
}
