import 'dart:io';

import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_service.dart';

Future<int> runSelect(List<String> args) async {
  String? deviceId;
  String? mode;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
      default:
        if (!args[i].startsWith('--')) {
          mode = args[i].toLowerCase();
        }
    }
  }

  if (mode == null) {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  if (mode != 'on' && mode != 'off') {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  final enabled = mode == 'on';

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

    await vmServiceCall(
      vmUri,
      'ext.flutter.inspector.show',
      params: {'isolateId': isolateId, 'enabled': enabled.toString()},
    );

    stdout.writeln('SELECTION_MODE=${enabled ? "ON" : "OFF"}');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
