import 'dart:io';

import 'package:fdb/app_died_exception.dart';
import 'package:fdb/vm_service.dart';

/// Triggers Navigator.maybePop() in the running Flutter app.
///
/// Usage:
///   fdb back
Future<int> runBack(List<String> args) async {
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

    final response = await vmServiceCall(
      'ext.fdb.back',
      params: {'isolateId': isolateId},
    );
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final popped = result['popped'] as bool? ?? false;
        if (popped) {
          stdout.writeln('POPPED');
          return 0;
        } else {
          stderr.writeln('ERROR: Navigator could not pop — already at root');
          return 1;
        }
      }

      if (error != null) {
        stderr.writeln('ERROR: $error');
        return 1;
      }
    }

    stderr.writeln('ERROR: Unexpected response from ext.fdb.back: $result');
    return 1;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}
