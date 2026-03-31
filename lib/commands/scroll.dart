import 'dart:io';

import 'package:fdb/process_utils.dart';
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
  String? deviceId;
  String? direction;
  String? at;
  var distance = 200;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
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
      default:
        if (!args[i].startsWith('--')) {
          direction = args[i].toLowerCase();
        }
    }
  }

  if (direction == null) {
    stderr.writeln(
        'ERROR: Usage: fdb scroll <up|down|left|right> [--at x,y] [--distance pixels]');
    return 1;
  }

  if (direction != 'up' &&
      direction != 'down' &&
      direction != 'left' &&
      direction != 'right') {
    stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
    return 1;
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;

  final vmUri = session['vmServiceUri'] as String?;
  if (vmUri == null) {
    stderr.writeln('ERROR: No VM service URI in session. Is the app running?');
    return 1;
  }

  try {
    final isolateId = await checkFdbHelper(vmUri);
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
      'distance': distance.toString(),
    };
    if (at != null) params['at'] = at;

    final response =
        await vmServiceCall(vmUri, 'ext.fdb.scroll', params: params);
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
