import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/vm_service.dart';

/// Clears the app's cache and data directories via the ext.fdb.clean
/// VM service extension registered by fdb_helper.
///
/// Output on success:
///   CLEANED
///   DIRS=`<comma-separated list of cleaned directories>`
///   DELETED_ENTRIES=`<count>`
Future<int> runClean(List<String> args) async {
  final isolateId = await checkFdbHelper();
  if (isolateId == null) {
    stderr.writeln(
      'ERROR: fdb_helper not found in the running app. '
      'Add FdbBinding.ensureInitialized() to main().',
    );
    return 1;
  }

  final response = await vmServiceCall(
    'ext.fdb.clean',
    params: {'isolateId': isolateId},
  );

  final result = unwrapRawExtensionResult(response);

  if (result is Map && result.containsKey('error')) {
    stderr.writeln('ERROR: ${result['error']}');
    return 1;
  }

  if (result is Map && result['status'] == 'Success') {
    final dirs = (result['dirs'] as List<dynamic>?)?.cast<String>() ?? [];
    final deleted = result['deletedEntries'] as int? ?? 0;
    stdout.writeln('CLEANED');
    stdout.writeln('DIRS=${dirs.join(',')}');
    stdout.writeln('DELETED_ENTRIES=$deleted');
    return 0;
  }

  stderr.writeln('ERROR: unexpected response: ${jsonEncode(result)}');
  return 1;
}
