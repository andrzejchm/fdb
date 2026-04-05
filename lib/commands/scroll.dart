import 'dart:io';

import 'package:fdb/vm_service.dart';

const _directions = ['up', 'down', 'left', 'right'];

/// Scrolls in a direction on the device screen, or performs a raw drag gesture.
///
/// Direction mode:
///   fdb scroll down
///   fdb scroll up
///   fdb scroll left
///   fdb scroll right
///   fdb scroll down --at 200,400
///   fdb scroll down --distance 500
///
/// Raw coordinate mode:
///   fdb scroll --from 100,400 --to 300,100
Future<int> runScroll(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'ERROR: Usage:\n'
      '  fdb scroll <up|down|left|right> [--at x,y] [--distance pixels]\n'
      '  fdb scroll --from x,y --to x,y',
    );
    return 1;
  }

  // Detect mode: raw coordinate mode when --from or --to appear in args
  final isRawMode = args.contains('--from') || args.contains('--to');

  String? at;
  var distance = 200;
  String? from;
  String? to;
  String? direction;

  if (isRawMode) {
    // Raw coordinate mode — parse all args as flags
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--from':
          from = args[++i];
        case '--to':
          to = args[++i];
        default:
          if (_directions.contains(args[i])) {
            stderr.writeln(
              'ERROR: --from/--to cannot be combined with a direction argument. '
              'Use either "fdb scroll <direction>" or "fdb scroll --from x,y --to x,y".',
            );
          } else {
            stderr.writeln('ERROR: Unknown flag: ${args[i]}');
          }
          return 1;
      }
    }
  } else {
    // Direction mode — first positional arg is the direction
    direction = args[0].toLowerCase();
    if (!_directions.contains(direction)) {
      stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
      return 1;
    }

    for (var i = 1; i < args.length; i++) {
      switch (args[i]) {
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
          stderr.writeln('ERROR: Unknown flag: ${args[i]}');
          return 1;
      }
    }
  }

  // Validate raw coordinate mode inputs
  List<double>? fromCoords;
  List<double>? toCoords;
  if (isRawMode) {
    if (from == null || to == null) {
      stderr.writeln(
          'ERROR: --from and --to are both required in raw coordinate mode.');
      return 1;
    }
    fromCoords = _parseCoords(from);
    if (fromCoords == null) {
      stderr.writeln(
          'ERROR: Invalid --from value: "$from". Expected format: x,y (e.g. 100,400).');
      return 1;
    }
    toCoords = _parseCoords(to);
    if (toCoords == null) {
      stderr.writeln(
          'ERROR: Invalid --to value: "$to". Expected format: x,y (e.g. 300,100).');
      return 1;
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

    final Map<String, dynamic> params;
    if (isRawMode) {
      params = {
        'isolateId': isolateId,
        'startX': fromCoords![0].toString(),
        'startY': fromCoords[1].toString(),
        'endX': toCoords![0].toString(),
        'endY': toCoords[1].toString(),
      };
    } else {
      params = {
        'isolateId': isolateId,
        'direction': direction,
        'distance': distance.toString(),
      };
      if (at != null) params['at'] = at;
    }

    final response = await vmServiceCall('ext.fdb.scroll', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        if (isRawMode) {
          stdout.writeln('SCROLLED=RAW');
          stdout.writeln(
              'FROM=${fromCoords![0].toInt()},${fromCoords[1].toInt()}');
          stdout.writeln('TO=${toCoords![0].toInt()},${toCoords[1].toInt()}');
        } else {
          stdout.writeln('SCROLLED=${direction!.toUpperCase()}');
          stdout.writeln('DISTANCE=$distance');
        }
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

/// Parses a coordinate string of the form "x,y" into a list [x, y].
/// Returns null if the string is not a valid coordinate pair.
List<double>? _parseCoords(String value) {
  final parts = value.split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0].trim());
  final y = double.tryParse(parts[1].trim());
  if (x == null || y == null) return null;
  return [x, y];
}
