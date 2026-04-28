import 'dart:io';

import 'package:fdb/app_died_exception.dart';
import 'package:fdb/vm_service.dart';

/// Enters text into a field identified by selector or the currently focused field.
///
/// Usage:
///   fdb input "hello@example.com"
///   fdb input --text "Email" "hello@example.com"
///   fdb input --key "email_field" "hello@example.com"
///   fdb input --type TextField "hello@example.com"
Future<int> runInput(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  String? textToEnter;

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
        // Last positional argument is the text to enter
        if (!args[i].startsWith('--')) {
          textToEnter = args[i];
        }
    }
  }

  if (textToEnter == null) {
    stderr.writeln('ERROR: No input text provided');
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

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'input': textToEnter,
    };

    final hasSelector = text != null || key != null || type != null;
    if (!hasSelector) {
      params['focused'] = 'true';
    }
    if (text != null) params['text'] = text;
    if (key != null) params['key'] = key;
    if (type != null) params['type'] = type;
    if (index != null) params['index'] = index.toString();

    final response = await vmServiceCall('ext.fdb.enterText', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final fieldType = result['widgetType'] as String? ?? type ?? 'field';
        stdout.writeln('INPUT=$fieldType VALUE=$textToEnter');
        return 0;
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.enterText: $result');
    return 1;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
