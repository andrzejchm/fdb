import 'dart:io';

import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_service.dart';

Future<int> runSelected(List<String> args) async {
  String? deviceId;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
    }
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;

  final vmUri = session['vmServiceUri'] as String?;
  if (vmUri == null) {
    stderr.writeln('ERROR: No VM service URI in session. Is the app running?');
    return 1;
  }

  try {
    final isolateId = await findFlutterIsolateId(vmUri);
    if (isolateId == null) {
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    }

    final response = await vmServiceCall(
      vmUri,
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_selected'},
    );

    final widget = unwrapExtensionResult(response);
    if (widget == null || widget is! Map<String, dynamic>) {
      stdout.writeln('NO_WIDGET_SELECTED');
      return 0;
    }

    final description = widget['description'] as String? ?? 'Unknown';
    final creationLocation =
        widget['creationLocation'] as Map<String, dynamic>?;

    if (creationLocation != null) {
      final file = (creationLocation['file'] as String? ?? '').split('/').last;
      final line = creationLocation['line'] as int?;
      final location = line != null ? '$file:$line' : file;
      stdout.writeln('SELECTED: $description ($location)');
    } else {
      stdout.writeln('SELECTED: $description');
    }

    return 0;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
