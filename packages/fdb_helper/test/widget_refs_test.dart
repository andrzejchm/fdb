import 'dart:convert';

import 'package:fdb_helper/src/handlers/input_handler.dart';
import 'package:fdb_helper/src/handlers/tap_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'describe_refs.dart';

void main() {
  late Map<String, int> taps;
  setUp(() => taps = {});

  /// A ListView of keyed buttons, one per label. Tapping one counts it in [taps].
  Widget list(List<String> labels) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final label in labels)
                ElevatedButton(
                  key: ValueKey(label),
                  onPressed: () => taps[label] = (taps[label] ?? 0) + 1,
                  child: Text(label),
                ),
            ],
          ),
        ),
      );
  final items = [for (var i = 0; i < 50; i++) 'Item $i'];

  Future<int> refOf(WidgetTester tester, String label) async =>
      (await describeEntry(tester, 'ElevatedButton', label))['ref'] as int;

  testWidgets('a widget keeps its ref across rebuilds and scrolling while it stays mounted', (tester) async {
    await tester.pumpWidget(list(items));
    final ref = await refOf(tester, 'Item 3');

    await tester.pumpWidget(list([...items]));
    expect(await refOf(tester, 'Item 3'), ref, reason: 'rebuilt with new widget instances');

    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(await refOf(tester, 'Item 3'), ref, reason: 'scrolled');
  });

  testWidgets('a ref tapped after the list scrolled taps the same widget', (tester) async {
    await tester.pumpWidget(list(items));
    final entry = await describeEntry(tester, 'ElevatedButton', 'Item 5');

    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    final result = await _tap(tester, refParams(entry));

    expect(result['status'], 'Success', reason: '$result');
    expect(result['text'], 'Item 5');
    expect(taps, {'Item 5': 1});
  });

  testWidgets('a removed widget leaves a stale ref that is never reused and taps nothing', (tester) async {
    await tester.pumpWidget(list(items));
    final before = await describe(tester);
    final removed = await refOf(tester, 'Item 2');

    await tester.pumpWidget(list(items.where((label) => label != 'Item 2').toList()));
    final after = await describe(tester);
    await tester.pumpWidget(list([...items.where((label) => label != 'Item 2'), 'New item']));
    final added = await refOf(tester, 'New item');

    final refsBefore = (before['interactive'] as List).map((e) => e['ref'] as int);
    final kept = (before['interactive'] as List).firstWhere((e) => e['text'] == 'Item 0')['ref'];
    expect(after['removedRefs'], allOf(contains(removed), isNot(contains(kept))));
    expect((after['interactive'] as List).map((e) => e['ref']), isNot(contains(removed)));
    expect(added, greaterThan(refsBefore.reduce((a, b) => a > b ? a : b)));

    final result = await _tap(tester, {'ref': '$removed'});
    expect(result['error'], '@$removed is stale: the widget was removed or rebuilt. Run fdb describe again.');
    expect(taps, isEmpty);
  });

  testWidgets('a list child that is not built keeps its ref once it scrolls into view', (tester) async {
    await tester.pumpWidget(list(items));
    final entry = await describeEntry(tester, 'ElevatedButton', 'Item 40');
    expect(entry['built'], false);
    final ref = entry['ref'] as int;

    final notBuilt = await _tap(tester, {'ref': '$ref'});
    expect(notBuilt['error'], '@$ref is not built on screen. Bring it into view with fdb scroll-to @$ref first');

    await tester.scrollUntilVisible(find.text('Item 40'), 200);
    await tester.pumpAndSettle();
    expect(await refOf(tester, 'Item 40'), ref);
    expect((await _tap(tester, {'ref': '$ref'}))['status'], 'Success');
    expect(taps, {'Item 40': 1});
  });

  testWidgets('a ref to a list child that is not built goes stale when the list no longer has it', (tester) async {
    await tester.pumpWidget(list(items));
    final ref = await refOf(tester, 'Item 40');

    await tester.pumpWidget(list([...items]));

    expect((await _tap(tester, {'ref': '$ref'}))['error'], contains('@$ref is stale'));
    expect(await refOf(tester, 'Item 40'), greaterThan(ref));
  });

  testWidgets('--expect-text fails without tapping when the widget behind the ref changed its text', (tester) async {
    final label = ValueNotifier('Follow');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder(
            valueListenable: label,
            builder: (_, text, __) => ElevatedButton(onPressed: () => taps[text] = 1, child: Text(text)),
          ),
        ),
      ),
    );
    final ref = await refOf(tester, 'Follow');
    expect((await _tap(tester, {'ref': '$ref', 'expectText': 'Follow'}))['status'], 'Success');
    taps.clear();
    label.value = 'Unfollow';
    await tester.pump();

    final result = await _tap(tester, {'ref': '$ref', 'expectText': 'Follow', 'expectType': 'ElevatedButton'});

    expect(
      result['error'],
      '@$ref is now ElevatedButton "Unfollow", not ElevatedButton "Follow". Nothing was tapped. Run fdb describe again.',
    );
    expect(taps, isEmpty);
  });

  testWidgets('fdb input types into the field behind a ref', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const TextField(key: ValueKey('first')),
            TextField(key: const ValueKey('second'), controller: controller)
          ]),
        ),
      ),
    );
    final interactive = ((await describe(tester))['interactive'] as List).cast<Map<String, dynamic>>();
    final ref = interactive.singleWhere((e) => e['key'] == 'second')['ref'];

    final response = await handleEnterText('ext.fdb.enterText', {'ref': '$ref', 'input': 'hello'});

    expect(jsonDecode(response.result!)['status'], 'Success');
    expect(controller.text, 'hello');
  });
}

Future<Map<String, dynamic>> _tap(WidgetTester tester, Map<String, String> params) async {
  final response = await tester.runAsync(() => handleTap('ext.fdb.tap', params));
  return jsonDecode(response!.result ?? response.errorDetail!) as Map<String, dynamic>;
}
