import 'dart:io';

import 'package:fdb/app_died_exception.dart';
import 'package:fdb/vm_service.dart';

/// Double-taps a widget identified by selector or absolute coordinates.
///
/// Usage:
///   fdb double-tap --key "map_widget"
///   fdb double-tap --text "Zoom here"
///   fdb double-tap --type InteractiveViewer [--index 0]
///   fdb double-tap --x 195 --y 842
///   fdb double-tap --at 195,842
Future<int> runDoubleTap(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  double? x;
  double? y;
  var timeoutSeconds = 5;

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
        final coords = _parseCoords(rawAt);
        if (coords == null) {
          stderr.writeln('ERROR: Invalid value for --at: $rawAt. Expected format: x,y');
          return 1;
        }
        x = coords.$1;
        y = coords.$2;
      case '--timeout':
        final rawTimeout = args[++i];
        final parsed = int.tryParse(rawTimeout);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
          return 1;
        }
        timeoutSeconds = parsed;
      default:
        stderr.writeln('ERROR: Unknown flag: ${args[i]}');
        return 1;
    }
  }

  final hasCoords = x != null && y != null;
  final hasSelector = text != null || key != null || type != null;
  final selectorCount = [text, key, type].where((value) => value != null).length;

  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together');
    return 1;
  }

  if (selectorCount > 1) {
    stderr.writeln('ERROR: Provide exactly one target: --text, --key, --type, --x/--y, or --at');
    return 1;
  }

  if (hasSelector == hasCoords) {
    stderr.writeln('ERROR: Provide exactly one target: --text, --key, --type, --x/--y, or --at');
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

    final params = <String, dynamic>{'isolateId': isolateId};
    if (text != null) params['text'] = text;
    if (key != null) params['key'] = key;
    if (type != null) params['type'] = type;
    if (index != null) params['index'] = index.toString();
    if (x != null) params['x'] = x.toString();
    if (y != null) params['y'] = y.toString();

    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (true) {
      final response = await vmServiceCall('ext.fdb.doubleTap', params: params);
      final result = unwrapRawExtensionResult(response);

      if (result is Map<String, dynamic>) {
        final status = result['status'] as String?;
        final error = result['error'] as String?;

        if (status == 'Success') {
          final tappedType = result['widgetType'] as String? ?? type ?? 'widget';
          final tappedX = result['x'] ?? x ?? '';
          final tappedY = result['y'] ?? y ?? '';
          stdout.writeln('DOUBLE_TAPPED=$tappedType X=$tappedX Y=$tappedY');
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

      stderr.writeln('ERROR: Unexpected response from ext.fdb.doubleTap: $result');
      return 1;
    }
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}

(double, double)? _parseCoords(String value) {
  final parts = value.split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0].trim());
  final y = double.tryParse(parts[1].trim());
  if (x == null || y == null) return null;
  return (x, y);
}
