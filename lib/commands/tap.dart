import 'dart:async';
import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Taps a widget identified by selector or absolute coordinates.
///
/// Usage:
///   fdb tap --text "Submit"
///   fdb tap --key "login_button"
///   fdb tap --type ElevatedButton [--index 2]
///   fdb tap --x 195 --y 842
///   fdb tap --text "Submit" --timeout 5
Future<int> runTap(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  int? x;
  int? y;
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
        index = int.parse(args[++i]);
      case '--x':
        x = int.parse(args[++i]);
      case '--y':
        y = int.parse(args[++i]);
      case '--timeout':
        timeoutSeconds = int.parse(args[++i]);
    }
  }

  final hasCoords = x != null && y != null;
  final hasSelector = text != null || key != null || type != null;

  if (!hasSelector && !hasCoords) {
    stderr.writeln('ERROR: Provide --text, --key, --type, or --x/--y');
    return 1;
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
          final tappedType = result['type'] as String? ?? type ?? 'widget';
          final tappedX = result['x'] ?? x ?? '';
          final tappedY = result['y'] ?? y ?? '';
          stdout.writeln('TAPPED=$tappedType X=$tappedX Y=$tappedY');
          return 0;
        }

        if (error != null) {
          if (DateTime.now().isBefore(deadline)) {
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
