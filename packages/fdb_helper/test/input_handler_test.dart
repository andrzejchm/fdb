import 'dart:convert';

import 'package:fdb_helper/src/handlers/describe_handler.dart';
import 'package:fdb_helper/src/handlers/input_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _enterText(Map<String, String> params) async {
  final response = await handleEnterText('ext.fdb.enterText', params);
  return jsonDecode(response.result ?? response.errorDetail!) as Map<String, dynamic>;
}

/// No-op implementations of the optional [TextInputClient] members.
mixin _ClientDefaults {
  void insertContent(KeyboardInsertedContent content) {}
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}
  void insertTextPlaceholder(Size size) {}
  void removeTextPlaceholder() {}
  bool onFocusReceived() => false;
  void performSelector(String selectorName) {}
  void showToolbar() {}
}

/// Minimal stand-in for flutter_quill's QuillRawEditorState: implements
/// [TextInputClient] directly, never builds an [EditableText], keeps a
/// mandatory trailing '\n', and — like Quill — null-asserts its last known
/// remote value in [updateEditingValue].
class FakeRichEditor extends StatefulWidget {
  const FakeRichEditor({
    super.key,
    required this.document,
    required this.focusNode,
    this.connected = true,
    this.onAction,
  });

  final ValueNotifier<String> document;
  final FocusNode focusNode;
  final bool connected;
  final ValueChanged<TextInputAction>? onAction;

  @override
  State<FakeRichEditor> createState() => FakeRichEditorState();
}

class FakeRichEditorState extends State<FakeRichEditor> with _ClientDefaults implements TextInputClient {
  TextEditingValue? _remote;

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      _remote = TextEditingValue(
        text: widget.document.value,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  @override
  TextEditingValue? get currentTextEditingValue => _remote;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // Mirrors Quill: crashes when no connection was ever opened.
    _remote!;
    _remote = value;
    widget.document.value = value.text;
  }

  @override
  void performAction(TextInputAction action) => widget.onAction?.call(action);

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: SizedBox(
        height: 48,
        child: ValueListenableBuilder<String>(
          valueListenable: widget.document,
          builder: (context, doc, _) => Text(doc.trim().isEmpty ? 'Type...' : doc.trim()),
        ),
      ),
    );
  }
}

/// A [DeltaTextInputClient] that counts how each update path was used.
class FakeDeltaEditor extends StatefulWidget {
  const FakeDeltaEditor({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  State<FakeDeltaEditor> createState() => FakeDeltaEditorState();
}

class FakeDeltaEditorState extends State<FakeDeltaEditor> with _ClientDefaults implements DeltaTextInputClient {
  TextEditingValue value = const TextEditingValue(text: 'old');
  final deltas = <TextEditingDelta>[];
  int fullUpdates = 0;

  @override
  TextEditingValue? get currentTextEditingValue => value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue newValue) {
    fullUpdates++;
    value = newValue;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    deltas.addAll(textEditingDeltas);
    for (final d in textEditingDeltas) {
      value = d.apply(value);
    }
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focusNode, child: const SizedBox(height: 48, child: Text('delta')));
}

void main() {
  group('EditableText (unchanged path)', () {
    testWidgets('focused TextField receives text through its controller', (tester) async {
      final controller = TextEditingController(text: 'before');
      final changes = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(key: const ValueKey('field'), controller: controller, onChanged: changes.add),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final result = await _enterText({'input': 'hello', 'focused': 'true'});

      expect(result['status'], 'Success');
      expect(result['widgetType'], 'EditableText');
      expect(result['clientKind'], 'EditableText');
      expect(controller.text, 'hello');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(changes, ['hello']);
    });

    testWidgets('TextFormField selected by key reports the selector widget type', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TextFormField(key: const ValueKey('form_field'), controller: controller)),
      ));

      final result = await _enterText({'input': 'typed', 'key': 'form_field'});

      expect(result['status'], 'Success');
      expect(result['widgetType'], 'TextFormField');
      expect(controller.text, 'typed');
    });
  });

  group('TextInputClient-only editor (flutter_quill shape)', () {
    late ValueNotifier<String> document;
    late FocusNode focusNode;
    late List<TextInputAction> actions;

    Future<void> pumpEditor(WidgetTester tester, {bool connected = true}) async {
      document = ValueNotifier<String>('\n');
      focusNode = FocusNode();
      actions = [];
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FakeRichEditor(
              document: document,
              focusNode: focusNode,
              connected: connected,
              onAction: actions.add,
            ),
          ]),
        ),
      ));
      focusNode.requestFocus();
      await tester.pump();
    }

    testWidgets('focused editor receives text, keeps trailing newline, notifies listeners', (tester) async {
      await pumpEditor(tester);
      final seen = <String>[];
      document.addListener(() => seen.add(document.value));

      final result = await _enterText({'input': 'QA test', 'focused': 'true'});

      expect(result['status'], 'Success', reason: '$result');
      expect(result['widgetType'], 'FakeRichEditor');
      expect(result['clientType'], 'FakeRichEditorState');
      expect(result['clientKind'], 'TextInputClient');
      expect(document.value, 'QA test\n');
      expect(seen, ['QA test\n']);
    });

    testWidgets('replaces existing content', (tester) async {
      await pumpEditor(tester);
      await _enterText({'input': 'first', 'focused': 'true'});
      await _enterText({'input': 'second', 'focused': 'true'});
      expect(document.value, 'second\n');
    });

    testWidgets('--action send calls performAction on the same client', (tester) async {
      await pumpEditor(tester);

      final result = await _enterText({'input': 'QA test', 'action': 'send', 'focused': 'true'});

      expect(result['action'], 'send');
      expect(document.value, 'QA test\n');
      expect(actions, [TextInputAction.send]);
    });

    testWidgets('action alone (no input) works', (tester) async {
      await pumpEditor(tester);

      final result = await _enterText({'action': 'newline', 'focused': 'true'});

      expect(result['status'], 'Success');
      expect(result.containsKey('input'), isFalse);
      expect(actions, [TextInputAction.newline]);
      expect(document.value, '\n');
    });

    testWidgets('unknown action is rejected with the valid list', (tester) async {
      await pumpEditor(tester);
      final result = await _enterText({'action': 'bogus', 'focused': 'true'});
      expect(result['error'], contains('Unknown text input action "bogus"'));
      expect(result['error'], contains('send'));
    });

    testWidgets('selector on placeholder text resolves the enclosing editor', (tester) async {
      await pumpEditor(tester);

      final result = await _enterText({'input': 'via text', 'text': 'Type...'});

      expect(result['status'], 'Success', reason: '$result');
      expect(result['clientType'], 'FakeRichEditorState');
      expect(document.value, 'via text\n');
    });

    testWidgets('selector by --type on the editor widget works', (tester) async {
      await pumpEditor(tester);
      final result = await _enterText({'input': 'by type', 'type': 'FakeRichEditor'});
      expect(result['status'], 'Success', reason: '$result');
      expect(document.value, 'by type\n');
    });

    testWidgets('no connection: error names the widget and the reason', (tester) async {
      await pumpEditor(tester, connected: false);

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(result['error'], contains('FakeRichEditor (FakeRichEditorState)'));
      expect(result['error'], contains('no active text input connection'));
      expect(document.value, '\n');
    });

    testWidgets('describe flags the editor as editable', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEditor(tester);
      await _enterText({'input': 'hello', 'focused': 'true'});
      await tester.pump();

      final response = await handleDescribe('ext.fdb.describe', const {});
      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      final entries = (json['interactive'] as List).cast<Map<String, dynamic>>();
      final editor = entries.singleWhere((e) => e['type'] == 'FakeRichEditor');

      expect(editor['editable'], isTrue);
      expect(editor['inputClient'], 'FakeRichEditorState');
      expect(editor['text'], 'hello');
      expect(json['lifecycleState'], 'resumed');
    });

    testWidgets('describe keeps an empty editor (no text, no key)', (tester) async {
      await pumpEditor(tester);
      final response = await handleDescribe('ext.fdb.describe', const {});
      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      final entries = (json['interactive'] as List).cast<Map<String, dynamic>>();
      expect(entries.where((e) => e['type'] == 'FakeRichEditor'), hasLength(1));
    });
  });

  group('DeltaTextInputClient', () {
    testWidgets('receives a single replacement delta and no full update', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FakeDeltaEditor(focusNode: focusNode))));
      focusNode.requestFocus();
      await tester.pump();

      final result = await _enterText({'input': 'new text', 'focused': 'true'});
      final state = tester.state<FakeDeltaEditorState>(find.byType(FakeDeltaEditor));

      expect(result['clientKind'], 'DeltaTextInputClient');
      expect(state.deltas, hasLength(1));
      expect(state.deltas.single, isA<TextEditingDeltaReplacement>());
      expect(state.fullUpdates, 0);
      expect(state.value.text, 'new text');
      expect(state.value.selection, const TextSelection.collapsed(offset: 8));
    });
  });

  group('rejections', () {
    testWidgets('nothing focused: refuses instead of typing into the first field', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: controller))));
      await tester.pump();

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(result['error'], startsWith('No focused element found'));
      expect(result['error'], contains('focus scope'));
      expect(controller.text, isEmpty);
    });

    testWidgets('focused non-text widget: error names its type', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ElevatedButton(focusNode: focusNode, onPressed: () {}, child: const Text('Go'))),
      ));
      focusNode.requestFocus();
      await tester.pump();

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(result['error'], startsWith('Focused element is not an editable text field: '));
      expect(result['error'], contains('is not a text input'));
      expect(result['error'], contains('TextInputClient'));
    });

    testWidgets('selector on a non-text widget: error names its type', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Text('Plain label')))));

      final result = await _enterText({'input': 'x', 'text': 'Plain label'});

      expect(result['error'], startsWith('enterText failed: '));
      expect(result['error'], contains('is not a text input'));
      expect(result['error'], isNot(contains('No EditableText found')));
    });
  });
}
