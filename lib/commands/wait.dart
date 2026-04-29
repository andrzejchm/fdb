import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/vm_service.dart';

Future<int> runWait(List<String> args) async {
  String? text;
  String? key;
  String? type;
  String? route;
  String? condition;
  var timeoutMs = 10000;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--text':
        if (i + 1 >= args.length) {
          stderr.writeln('ERROR: Missing value for --text');
          return 1;
        }
        text = args[++i];
      case '--key':
        if (i + 1 >= args.length) {
          stderr.writeln('ERROR: Missing value for --key');
          return 1;
        }
        key = args[++i];
      case '--type':
        if (i + 1 >= args.length) {
          stderr.writeln('ERROR: Missing value for --type');
          return 1;
        }
        type = args[++i];
      case '--route':
        if (i + 1 >= args.length) {
          stderr.writeln('ERROR: Missing value for --route');
          return 1;
        }
        route = args[++i];
      case '--present':
        condition = condition == null ? 'present' : 'invalid';
      case '--absent':
        condition = condition == null ? 'absent' : 'invalid';
      case '--timeout':
        if (i + 1 >= args.length) {
          stderr.writeln('ERROR: Missing value for --timeout');
          return 1;
        }
        final rawTimeout = args[++i];
        final parsed = int.tryParse(rawTimeout);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
          return 1;
        }
        timeoutMs = parsed;
      default:
        stderr.writeln('ERROR: Unknown flag: ${args[i]}');
        return 1;
    }
  }

  if (condition == null || condition == 'invalid') {
    stderr.writeln('ERROR: Missing required flag: --present or --absent');
    return 1;
  }

  final selectorCount = [key, text, type, route].where((value) => value != null).length;
  if (selectorCount != 1) {
    stderr.writeln('ERROR: Missing selector: use --key, --text, --type, or --route');
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

    final params = <String, String>{
      'isolateId': isolateId,
      'condition': condition,
      'timeout': timeoutMs.toString(),
    };
    if (text != null) params['text'] = text;
    if (key != null) params['key'] = key;
    if (type != null) params['type'] = type;
    if (route != null) params['route'] = route;

    final response = await vmServiceCall(
      'ext.fdb.waitFor',
      params: params,
      timeout: Duration(milliseconds: timeoutMs + 5000),
    );
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        stdout.writeln('CONDITION_MET=$condition ${_selectorToken(key, text, type, route)}');
        return 0;
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.waitFor: $result');
    return 1;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}

String _selectorToken(String? key, String? text, String? type, String? route) {
  if (key != null) return 'KEY=$key';
  if (text != null) return 'TEXT=$text';
  if (type != null) return 'TYPE=$type';
  return 'ROUTE=$route';
}
