import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/vm_service.dart';

Future<int> runSelected(List<String> args) async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) {
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    }

    final response = await vmServiceCall(
      'ext.flutter.inspector.getSelectedSummaryWidget',
      params: {'isolateId': isolateId, 'objectGroup': 'fdb_selected'},
    );

    final widget = unwrapExtensionResult(response);
    if (widget == null || widget is! Map<String, dynamic>) {
      stdout.writeln('NO_WIDGET_SELECTED');
      return 0;
    }

    final description = widget['description'] as String? ?? 'Unknown';
    final creationLocation = widget['creationLocation'] as Map<String, dynamic>?;

    if (creationLocation != null) {
      final file = (creationLocation['file'] as String? ?? '').split('/').last;
      final line = creationLocation['line'] as int?;
      final location = line != null ? '$file:$line' : file;
      stdout.writeln('SELECTED: $description ($location)');
    } else {
      stdout.writeln('SELECTED: $description');
    }

    return 0;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
