import 'dart:convert';

import 'package:fdb_helper/src/handlers/describe_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `ext.fdb.describe` response for the current screen.
Future<Map<String, dynamic>> describe(WidgetTester tester) async {
  final response = await tester.runAsync(() => handleDescribe('ext.fdb.describe', const {}));
  return jsonDecode(response!.result!) as Map<String, dynamic>;
}

/// The `fdb describe` entry for the [type] widget showing [text].
Future<Map<String, dynamic>> describeEntry(WidgetTester tester, String type, String text) async {
  final interactive = ((await describe(tester))['interactive'] as List<dynamic>).cast<Map<String, dynamic>>();
  return interactive.singleWhere((e) => e['type'] == type && e['text'] == text,
      orElse: () => fail('no "$text" in $interactive'));
}

/// The params fdb sends for `@N` on [entry].
Map<String, String> refParams(Map<String, dynamic> entry) => {'ref': '${entry['ref']}'};
