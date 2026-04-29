import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tree/tree.dart';

/// CLI adapter for `fdb tree`.
///
/// Flags:
///   --depth `n`    Maximum tree depth to display (default: 10)
///   --user-only    Only show widgets created by the local project
Future<int> runTreeCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('depth', defaultsTo: '10', help: 'Maximum depth to display')
    ..addFlag('user-only', negatable: false, help: 'Show only user-project widgets');
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final maxDepth = int.parse(results['depth'] as String);
  final userOnly = results['user-only'] as bool;

  final result = await getWidgetTree((maxDepth: maxDepth, userOnly: userOnly));
  return _format(result, maxDepth, userOnly);
}

int _format(TreeResult result, int maxDepth, bool userOnly) {
  switch (result) {
    case TreeNoIsolate():
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    case TreeNoWidgetTree():
      stderr.writeln('ERROR: No widget tree returned');
      return 1;
    case TreeReceived(:final rootNode):
      _printTree(rootNode, 0, maxDepth, userOnly);
      return 0;
    case TreeAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case TreeError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

void _printTree(
  Map<String, dynamic> node,
  int depth,
  int maxDepth,
  bool userOnly,
) {
  if (depth >= maxDepth) return;

  final description = node['description'] as String? ?? 'Unknown';
  final creationLocation = node['creationLocation'] as Map<String, dynamic>?;
  final createdByLocal = node['createdByLocalProject'] as bool? ?? false;

  if (userOnly && !createdByLocal) {
    // Still recurse into children to find user widgets
    final children = node['children'] as List<dynamic>?;
    if (children != null) {
      for (final child in children) {
        _printTree(child as Map<String, dynamic>, depth, maxDepth, userOnly);
      }
    }
    return;
  }

  final indent = '  ' * depth;
  final location = _formatLocation(creationLocation);
  final locationSuffix = location.isNotEmpty ? ' ($location)' : '';

  stdout.writeln('$indent$description$locationSuffix');

  final children = node['children'] as List<dynamic>?;
  if (children != null) {
    for (final child in children) {
      _printTree(child as Map<String, dynamic>, depth + 1, maxDepth, userOnly);
    }
  }
}

String _formatLocation(Map<String, dynamic>? location) {
  if (location == null) return '';
  final file = location['file'] as String? ?? '';
  final line = location['line'] as int?;

  // Extract just the filename from the full path
  final fileName = file.split('/').last;
  if (fileName.isEmpty) return '';
  if (line != null) return '$fileName:$line';
  return fileName;
}
