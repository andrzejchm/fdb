import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Long-presses a widget identified by selector or absolute coordinates.
///
/// Usage:
///   fdb longpress --key "photo_card"
///   fdb longpress --text "Hold me"
///   fdb longpress --type GestureDetector [--index 0]
///   fdb longpress --at 195,842
///   fdb longpress --x 195 --y 842
///   fdb longpress --key "item" --duration 1000
///
/// The only difference from `fdb tap` is the hold duration between PointerDown
/// and PointerUp (default 500 ms). All selector/retry logic is shared via the
/// `ext.fdb.longPress` VM extension, which delegates to the same tap handler.
Future<int> runLongpress(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  double? x;
  double? y;
  var usedAt = false;
  var timeoutSeconds = 5;
  var durationMs = 500;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--text':
        text = args[++i];
      case '--key':
        key = args[++i];
      case '--type':
        type = args[++i];
      case '--index':
        final rawIndex = args[++i];
        index = int.tryParse(rawIndex);
        if (index == null) {
          stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
          return 1;
        }
      case '--x':
        final rawX = args[++i];
        x = double.tryParse(rawX);
        if (x == null) {
          stderr.writeln('ERROR: Invalid value for --x: $rawX');
          return 1;
        }
      case '--y':
        final rawY = args[++i];
        y = double.tryParse(rawY);
        if (y == null) {
          stderr.writeln('ERROR: Invalid value for --y: $rawY');
          return 1;
        }
      case '--at':
        final rawAt = args[++i];
        final parsed = _parseAt(rawAt);
        if (parsed == null) {
          stderr.writeln(
            'ERROR: Invalid --at value: "$rawAt". Expected format: x,y (e.g. 200,400).',
          );
          return 1;
        }
        x = parsed.$1;
        y = parsed.$2;
        usedAt = true;
      case '--duration':
        final rawDuration = args[++i];
        final parsed = int.tryParse(rawDuration);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --duration: $rawDuration');
          return 1;
        }
        if (parsed <= 0) {
          stderr.writeln('ERROR: --duration must be a positive integer');
          return 1;
        }
        durationMs = parsed;
      case '--timeout':
        final rawTimeout = args[++i];
        final parsed = int.tryParse(rawTimeout);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
          return 1;
        }
        timeoutSeconds = parsed;
    }
  }

  final hasCoords = x != null && y != null;
  final hasSelector = text != null || key != null || type != null;

  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together');
    return 1;
  }

  if (usedAt && hasSelector) {
    stderr.writeln('ERROR: --at cannot be combined with --key, --text, or --type.');
    return 1;
  }

  if (!hasSelector && !hasCoords) {
    stderr.writeln('ERROR: Provide --text, --key, --type, --at, or --x/--y');
    return 1;
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

    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (true) {
      final params = <String, dynamic>{
        'isolateId': isolateId,
        'duration': durationMs.toString(),
      };
      if (text != null) params['text'] = text;
      if (key != null) params['key'] = key;
      if (type != null) params['type'] = type;
      if (index != null) params['index'] = index.toString();
      if (x != null) params['x'] = x.toString();
      if (y != null) params['y'] = y.toString();

      final response = await vmServiceCall('ext.fdb.longPress', params: params);
      final result = unwrapRawExtensionResult(response);

      if (result is Map<String, dynamic>) {
        final status = result['status'] as String?;
        final error = result['error'] as String?;

        if (status == 'Success') {
          final pressedType = usedAt ? 'coordinates' : result['widgetType'] as String? ?? type ?? 'widget';
          final pressedX = result['x'] ?? x ?? '';
          final pressedY = result['y'] ?? y ?? '';
          stdout.writeln('LONG_PRESSED=$pressedType X=$pressedX Y=$pressedY');
          return 0;
        }

        if (error != null) {
          final isRetryable = error.contains('not found') || error.contains('No hittable element');
          if (isRetryable && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            continue;
          }
          stderr.writeln('ERROR: $error');
          return 1;
        }
      }

      // Unexpected response shape — surface it
      stderr.writeln(
        'ERROR: Unexpected response from ext.fdb.longPress: $result',
      );
      return 1;
    }
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}

(double, double)? _parseAt(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;

  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  if (x == null || y == null) return null;

  return (x, y);
}
