import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Swipes in a direction, optionally targeting a specific widget's bounds.
///
/// Usage:
///   fdb swipe left --key "photo_card"
///   fdb swipe right --text "Next"
///   fdb swipe up --type PageView
///   fdb swipe down --at 200,400
///   fdb swipe left --distance 400
Future<int> runSwipe(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'ERROR: Usage: fdb swipe <left|right|up|down> '
      '[--key KEY] [--text TEXT] [--type TYPE] [--at x,y] [--distance PIXELS]',
    );
    return 1;
  }

  final direction = args[0].toLowerCase();
  if (direction != 'up' && direction != 'down' && direction != 'left' && direction != 'right') {
    stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
    return 1;
  }

  String? key;
  String? text;
  String? type;
  String? at;
  int? distance;

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--key':
        key = args[++i];
      case '--text':
        text = args[++i];
      case '--type':
        type = args[++i];
      case '--at':
        at = args[++i];
      case '--distance':
        final rawDistance = args[++i];
        final parsed = int.tryParse(rawDistance);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --distance: $rawDistance');
          return 1;
        }
        distance = parsed;
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

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'direction': direction,
    };
    if (key != null) params['key'] = key;
    if (text != null) params['text'] = text;
    if (type != null) params['type'] = type;
    if (at != null) params['at'] = at;
    if (distance != null) params['distance'] = distance.toString();

    final response = await vmServiceCall('ext.fdb.swipe', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final actualDistance = result['distance'] ?? distance ?? '';
        stdout.writeln(
          'SWIPED=${direction.toUpperCase()} DISTANCE=$actualDistance',
        );
        return 0;
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.swipe: $result');
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
