import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
