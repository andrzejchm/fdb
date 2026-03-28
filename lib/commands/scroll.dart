import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Scrolls in a direction on the device screen.
///
/// Usage:
///   fdb scroll down
///   fdb scroll up
///   fdb scroll left
///   fdb scroll right
///   fdb scroll down --at 200,400
///   fdb scroll down --distance 500
Future<int> runScroll(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'ERROR: Usage: fdb scroll <up|down|left|right> [--at x,y] [--distance pixels]');
    return 1;
  }

  final direction = args[0].toLowerCase();
  if (direction != 'up' &&
      direction != 'down' &&
      direction != 'left' &&
      direction != 'right') {
    stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
    return 1;
  }

  String? at;
  var distance = 200;

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--at':
        at = args[++i];
      case '--distance':
        distance = int.parse(args[++i]);
    }
  }

  try {
    final helperAvailable = await isFdbHelperAvailable();
    if (!helperAvailable) {
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    }

    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) {
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    }

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'direction': direction,
      'distance': distance.toString(),
    };
    if (at != null) params['at'] = at;

    final response = await vmServiceCall('ext.fdb.scroll', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        stdout
            .writeln('SCROLLED=${direction.toUpperCase()} DISTANCE=$distance');
        return 0;
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.scroll: $result');
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
