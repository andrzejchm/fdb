import 'dart:io';

import 'package:fdb/vm_service.dart';

/// Scrolls the nearest Scrollable until the target widget becomes visible.
///
/// Works for lazy lists (ListView.builder) where off-screen widgets don't
/// exist in the element tree yet.
///
/// Usage:
///   fdb scroll-to --key <key>
///   fdb scroll-to --text <text>
///   fdb scroll-to --type <WidgetType>
///   fdb scroll-to --type <WidgetType> --index 2
Future<int> runScrollTo(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;

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
      default:
        stderr.writeln('ERROR: Unknown flag: ${args[i]}');
        return 1;
    }
  }

  final hasSelector = text != null || key != null || type != null;
  if (!hasSelector) {
    stderr.writeln('ERROR: Provide --text, --key, or --type');
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

    final params = <String, String>{'isolateId': isolateId};
    if (text != null) params['text'] = text;
    if (key != null) params['key'] = key;
    if (type != null) params['type'] = type;
    if (index != null) params['index'] = index.toString();

    final response = await vmServiceCall('ext.fdb.scrollTo', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final widgetType =
            result['widgetType'] as String? ?? key ?? text ?? type ?? 'widget';
        final x = result['x'] as double?;
        final y = result['y'] as double?;
        if (x == null || y == null) {
          stderr.writeln(
            'ERROR: Unexpected response from ext.fdb.scrollTo: missing x or y',
          );
          return 1;
        }
        stdout.writeln('SCROLLED_TO=$widgetType X=$x Y=$y');
        return 0;
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln(
      'ERROR: Unexpected response from ext.fdb.scrollTo: $result',
    );
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
