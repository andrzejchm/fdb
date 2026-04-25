import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleClean(
  String method,
  Map<String, String> params,
) async {
  try {
    final dirs = <Directory>[];

    // Cache dir — getTemporaryDirectory() on iOS/Android.
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}

    // App support dir — persistent but non-user-facing storage.
    try {
      dirs.add(await getApplicationSupportDirectory());
    } catch (_) {}

    // App documents dir — user-facing documents.
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}

    final cleaned = <String>[];
    var totalFiles = 0;

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      final entities = dir.listSync(recursive: false);
      for (final entity in entities) {
        try {
          if (entity is File) {
            entity.deleteSync();
            totalFiles++;
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
            totalFiles++;
          }
        } catch (_) {}
      }
      cleaned.add(dir.path);
    }

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'dirs': cleaned,
        'deletedEntries': totalFiles,
      }),
    );
  } catch (e) {
    return errorResponse('clean failed: $e');
  }
}
