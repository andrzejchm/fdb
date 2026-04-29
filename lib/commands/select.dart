import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/vm_service.dart';

Future<int> runSelect(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  final mode = args[0].toLowerCase();
  if (mode != 'on' && mode != 'off') {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  final enabled = mode == 'on';

  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) {
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    }

    await vmServiceCall(
      'ext.flutter.inspector.show',
      params: {'isolateId': isolateId, 'enabled': enabled.toString()},
    );

    stdout.writeln('SELECTION_MODE=${enabled ? "ON" : "OFF"}');
    return 0;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
