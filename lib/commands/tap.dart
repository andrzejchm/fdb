import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Taps a widget identified by selector, absolute coordinates, or a describe ref.
///
/// Usage:
///   fdb tap --text "Submit"
///   fdb tap --key "login_button"
///   fdb tap --type ElevatedButton [--index 2]
///   fdb tap --at 195,842
///   fdb tap --x 195 --y 842
///   fdb tap @3
///   fdb tap --text "Submit" --timeout 5
Future<int> runTap(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  double? x;
  double? y;
  var usedAt = false;
  int? describeRef;
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
      case '--timeout':
        final rawTimeout = args[++i];
        final parsed = int.tryParse(rawTimeout);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
          return 1;
        }
        timeoutSeconds = parsed;
      default:
        // Support @N ref syntax from fdb describe
        final arg = args[i];
        if (arg.startsWith('@')) {
          final refNum = int.tryParse(arg.substring(1));
          if (refNum == null || refNum < 1) {
            stderr.writeln('ERROR: Invalid ref: $arg. Expected @N where N >= 1');
            return 1;
          }
          describeRef = refNum;
        }
    }
  }

  // Resolve @N ref to coordinates via ext.fdb.describe
  if (describeRef != null) {
    return _tapByRef(describeRef, timeoutSeconds);
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
    stderr.writeln('ERROR: Provide --text, --key, --type, --at, --x/--y, or @N ref');
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
      final params = <String, dynamic>{'isolateId': isolateId};
      if (text != null) params['text'] = text;
      if (key != null) params['key'] = key;
      if (type != null) params['type'] = type;
      if (index != null) params['index'] = index.toString();
      if (x != null) params['x'] = x.toString();
      if (y != null) params['y'] = y.toString();

      final response = await vmServiceCall('ext.fdb.tap', params: params);
      final result = unwrapRawExtensionResult(response);

      if (result is Map<String, dynamic>) {
        final status = result['status'] as String?;
        final error = result['error'] as String?;

        if (status == 'Success') {
          final tappedType = usedAt ? 'coordinates' : result['widgetType'] as String? ?? type ?? 'widget';
          final tappedX = result['x'] ?? x ?? '';
          final tappedY = result['y'] ?? y ?? '';
          // The native-tap path may fall back to Flutter's GestureBinding if
          // the platform-channel injection fails (e.g. iOS private API drift).
          // When that happens, native overlays (UIAlertController, WebView)
          // are NOT reached — surface this to callers so agents can detect it.
          final warning = result['warning'] as String?;
          final warningSuffix = warning != null ? ' WARNING=$warning' : '';
          stdout.writeln('TAPPED=$tappedType X=$tappedX Y=$tappedY$warningSuffix');
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
      stderr.writeln('ERROR: Unexpected response from ext.fdb.tap: $result');
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

/// Resolves a describe ref (@N) to coordinates and taps at that position.
Future<int> _tapByRef(int ref, int timeoutSeconds) async {
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

    final describeResponse = await vmServiceCall(
      'ext.fdb.describe',
      params: {'isolateId': isolateId},
    );
    final describeResult = unwrapRawExtensionResult(describeResponse);

    if (describeResult is! Map<String, dynamic>) {
      stderr.writeln('ERROR: Unexpected response from ext.fdb.describe');
      return 1;
    }

    final describeError = describeResult['error'] as String?;
    if (describeError != null) {
      stderr.writeln('ERROR: $describeError');
      return 1;
    }

    final interactive = describeResult['interactive'] as List<dynamic>? ?? [];
    final match = interactive.cast<Map<String, dynamic>>().where(
          (e) => e['ref'] == ref,
        );

    if (match.isEmpty) {
      stderr.writeln(
        'ERROR: No interactive element with ref @$ref. '
        'Run `fdb describe` to see available refs.',
      );
      return 1;
    }

    final element = match.first;
    final cx = (element['x'] as num).toDouble();
    final cy = (element['y'] as num).toDouble();

    final tapParams = <String, dynamic>{
      'isolateId': isolateId,
      'x': cx.toString(),
      'y': cy.toString(),
    };

    final tapResponse = await vmServiceCall('ext.fdb.tap', params: tapParams);
    final tapResult = unwrapRawExtensionResult(tapResponse);

    if (tapResult is Map<String, dynamic>) {
      final status = tapResult['status'] as String?;
      final tapError = tapResult['error'] as String?;

      if (status == 'Success') {
        final type = element['type'] as String? ?? 'widget';
        stdout.writeln('TAPPED=$type X=$cx Y=$cy');
        return 0;
      }

      if (tapError != null) {
        stderr.writeln('ERROR: $tapError');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.tap: $tapResult');
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
