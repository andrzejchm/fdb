import 'dart:io';

import 'package:fdb/vm_service.dart';

Future<int> runSelected(List<String> args) async {
  try {
    final isolateId = await findMainIsolateId();
    if (isolateId == null) {
      stderr.writeln('ERROR: No isolate found');
      return 1;
    }

    final response = await vmServiceCall(
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_selected'},
    );

    final result = response['result'] as Map<String, dynamic>?;
    if (result == null || result.isEmpty) {
      stdout.writeln('NO_WIDGET_SELECTED');
      return 0;
    }

    final description = result['description'] as String? ?? 'Unknown';
    final creationLocation =
        result['creationLocation'] as Map<String, dynamic>?;

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
