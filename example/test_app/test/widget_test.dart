import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdb_helper/src/handlers/describe_handler.dart';

import 'package:test_app/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FdbTestApp());

    expect(find.text('Counter: 0'), findsOneWidget);
    expect(find.text('Counter: 1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('Counter: 0'), findsNothing);
    expect(find.text('Counter: 1'), findsOneWidget);
  });

  testWidgets('describe includes visible TextField value in visible text', (tester) async {
    await tester.pumpWidget(const FdbTestApp());
    await tester.enterText(find.byKey(const Key('test_input')), 'hello fdb');
    await tester.pump();

    final response = await handleDescribe('ext.fdb.describe', const {});
    final result = jsonDecode(response.result!) as Map<String, dynamic>;
    final texts = (result['texts'] as List<dynamic>).cast<String>();

    expect(texts, contains('hello fdb'));
  });
}
