import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Returns a compact, text-based snapshot of the current screen.
///
/// Interactive elements are assigned stable refs (@1, @2, ...) that can be
/// used directly with `fdb tap @N`.
///
/// Usage:
///   fdb describe
///   fdb describe --device <id>
Future<int> runDescribe(List<String> args) async {
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        // Device flag is consumed by the launcher; ignore here.
        i++;
    }
  }

  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) {
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    }

    final response = await vmServiceCall(
      'ext.fdb.describe',
      params: {'isolateId': isolateId},
    );
    final result = unwrapRawExtensionResult(response);

    if (result is! Map<String, dynamic>) {
      stderr.writeln('ERROR: Unexpected response from ext.fdb.describe');
      return 1;
    }

    final error = result['error'] as String?;
    if (error != null) {
      stderr.writeln('ERROR: $error');
      return 1;
    }

    _printDescribeOutput(result);
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: $e');
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

      // Clean up text: remove leading/trailing separators from fragment joining
      var cleanText = text;
      if (cleanText != null) {
        cleanText = cleanText
            .replaceAll(RegExp(r'(^(\s*·\s*)+|(\s*·\s*)+$)'), '')
            .trim();
        if (cleanText.isEmpty) cleanText = null;
      }

      final buffer = StringBuffer('  @$ref $type');
      if (cleanText != null) buffer.write(' "$cleanText"');
      if (key != null) buffer.write(' key=$key');
      stdout.writeln(buffer.toString());
    }
    stdout.writeln('');
  }

  // Deduplicate texts that are already shown in interactive section
  final interactiveTexts = interactive
      .map((e) => (e as Map<String, dynamic>)['text'] as String?)
      .whereType<String>()
      .toSet();

  final uniqueTexts = texts
      .cast<String>()
      .where((t) => t.trim().isNotEmpty && !interactiveTexts.contains(t))
      .toList();

  if (uniqueTexts.isNotEmpty) {
    stdout.writeln('TEXT:');
    for (final text in uniqueTexts) {
      stdout.writeln('  "$text"');
    }
  }
}
