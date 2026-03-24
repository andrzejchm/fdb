import 'dart:io';

import 'package:fdb/vm_service.dart';

Future<int> runTree(List<String> args) async {
  var maxDepth = 10;
  var userOnly = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--depth':
        maxDepth = int.parse(args[++i]);
      case '--user-only':
        userOnly = true;
    }
  }

  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) {
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    }

    final response = await vmServiceCall(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_tree'},
      timeout: const Duration(seconds: 60),
    );

    final tree = unwrapExtensionResult(response);
    if (tree == null || tree is! Map<String, dynamic>) {
      stderr.writeln('ERROR: No widget tree returned');
      return 1;
    }

    _printTree(tree, 0, maxDepth, userOnly);
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: $e');
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
