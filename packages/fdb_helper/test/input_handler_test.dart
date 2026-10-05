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

/// Pumps the widget built by [build] and gives its [FocusNode] primary focus.
Future<void> _pumpFocused(WidgetTester tester, Widget Function(FocusNode focusNode) build) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: build(focusNode))));
  focusNode.requestFocus();
  await tester.pump();
}

/// No-op implementations of the [TextInputClient] members the fakes don't use.
mixin _ClientDefaults {
  AutofillScope? get currentAutofillScope => null;
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  void showAutocorrectionPromptRect(int start, int end) {}
  void connectionClosed() {}
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  void insertContent(KeyboardInsertedContent content) {}
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}
  void insertTextPlaceholder(Size size) {}
  void removeTextPlaceholder() {}
  bool onFocusReceived() => false;
  void performSelector(String selectorName) {}
  void showToolbar() {}
}

abstract class FakeEditor extends StatefulWidget {
  const FakeEditor({super.key, required this.focusNode});

  final FocusNode focusNode;
}

/// Shared build for the fake editors: a focusable box showing [label].
abstract class FakeClientState<W extends FakeEditor> extends State<W> with _ClientDefaults {
  String get label;

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focusNode, child: SizedBox(height: 48, child: Text(label)));
}

class FakeRichEditor extends FakeEditor {
  const FakeRichEditor({super.key, required super.focusNode, required this.document, required this.connected});

  final ValueNotifier<String> document;
  final bool connected;

  @override
  State<FakeRichEditor> createState() => FakeRichEditorState();
}

/// Stand-in for flutter_quill's QuillRawEditorState: implements
/// [TextInputClient] directly, never builds an [EditableText], keeps a
/// mandatory trailing '\n', and, like Quill, null-asserts its last known
/// remote value in [updateEditingValue].
class FakeRichEditorState extends FakeClientState<FakeRichEditor> implements TextInputClient {
  final actions = <TextInputAction>[];
  TextEditingValue? _remote;

  @override
  void initState() {
    super.initState();
    if (widget.connected) _remote = TextEditingValue(text: widget.document.value);
  }

  @override
  String get label => widget.document.value.trim().isEmpty ? 'Type...' : widget.document.value.trim();

  @override
  TextEditingValue? get currentTextEditingValue => _remote;

  @override
  void updateEditingValue(TextEditingValue value) {
    _remote!; // Like Quill: throws when no connection was ever opened.
    setState(() => _remote = value);
    widget.document.value = value.text;
  }

  @override
  void performAction(TextInputAction action) => actions.add(action);
}

class FakeDeltaEditor extends FakeEditor {
  const FakeDeltaEditor({super.key, required super.focusNode});

  @override
  State<FakeDeltaEditor> createState() => FakeDeltaEditorState();
}

/// A [DeltaTextInputClient] that records how each update path was used.
class FakeDeltaEditorState extends FakeClientState<FakeDeltaEditor> implements DeltaTextInputClient {
  TextEditingValue value = const TextEditingValue(text: 'old');
  final deltas = <TextEditingDelta>[];
  int fullUpdates = 0;

  @override
  String get label => 'delta';

  @override
  TextEditingValue? get currentTextEditingValue => value;

  @override
  void updateEditingValue(TextEditingValue newValue) {
    fullUpdates++;
    value = newValue;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    deltas.addAll(textEditingDeltas);
    value = textEditingDeltas.fold(value, (v, d) => d.apply(v));
  }

  @override
  void performAction(TextInputAction action) {}
}

void main() {
  group('EditableText', () {
    testWidgets('focused TextField receives text through its controller', (tester) async {
      final controller = TextEditingController(text: 'before');
      final changes = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TextField(controller: controller, onChanged: changes.add)),
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
    late FakeRichEditorState editor;

    Future<void> pumpEditor(WidgetTester tester, {bool connected = true}) async {
      document = ValueNotifier<String>('\n');
      await _pumpFocused(
        tester,
        (focusNode) => FakeRichEditor(focusNode: focusNode, document: document, connected: connected),
      );
      editor = tester.state(find.byType(FakeRichEditor));
    }

    testWidgets('focused editor: content is replaced, trailing newline kept, listeners run', (tester) async {
      await pumpEditor(tester);
      final seen = <String>[];
      document.addListener(() => seen.add(document.value));

      await _enterText({'input': 'first', 'focused': 'true'});
      final result = await _enterText({'input': 'QA test', 'focused': 'true'});

      expect(result['status'], 'Success', reason: '$result');
      expect(result['widgetType'], 'FakeRichEditor');
      expect(result['clientType'], 'FakeRichEditorState');
      expect(result['clientKind'], 'TextInputClient');
      expect(result['resultingText'], 'QA test\n');
      expect(document.value, 'QA test\n');
      expect(seen, ['first\n', 'QA test\n']);
      expect(editor.actions, isEmpty);
    });

    testWidgets('--action after text calls performAction on the same client', (tester) async {
      await pumpEditor(tester);

      final result = await _enterText({'input': 'QA test', 'action': 'send', 'focused': 'true'});

      expect(result['action'], 'send');
      expect(document.value, 'QA test\n');
      expect(editor.actions, [TextInputAction.send]);
    });

    testWidgets('--action alone sends the action and leaves the text untouched', (tester) async {
      await pumpEditor(tester);

      final result = await _enterText({'action': 'newline', 'focused': 'true'});

      expect(result['status'], 'Success');
      expect(result.containsKey('input'), isFalse);
      expect(editor.actions, [TextInputAction.newline]);
      expect(document.value, '\n');
    });

    testWidgets('--text on the placeholder and --type on the widget both resolve the editor', (tester) async {
      await pumpEditor(tester);

      final byText = await _enterText({'input': 'via text', 'text': 'Type...'});
      expect(byText['clientType'], 'FakeRichEditorState', reason: '$byText');
      expect(document.value, 'via text\n');

      final byType = await _enterText({'input': 'by type', 'type': 'FakeRichEditor'});
      expect(byType['widgetType'], 'FakeRichEditor', reason: '$byType');
      expect(document.value, 'by type\n');
    });

    testWidgets('no connection: error names the widget and nothing is applied', (tester) async {
      await pumpEditor(tester, connected: false);

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(result['error'], contains('FakeRichEditor (FakeRichEditorState) has no active text input connection'));
      expect(document.value, '\n');
    });

    testWidgets('describe lists the editor as editable, both empty and after input', (tester) async {
      Future<Map<String, dynamic>> describeEditor() async {
        final response = await handleDescribe('ext.fdb.describe', const {});
        final json = jsonDecode(response.result!) as Map<String, dynamic>;
        final entries = (json['interactive'] as List).cast<Map<String, dynamic>>();
        return entries.singleWhere((e) => e['type'] == 'FakeRichEditor');
      }

      await pumpEditor(tester);
      // No text and no key, but still listed because it is editable.
      final empty = await describeEditor();
      expect(empty['editable'], isTrue);
      expect(empty['text'], isNull);

      await _enterText({'input': 'hello', 'focused': 'true'});
      await tester.pump();
      final filled = await describeEditor();
      expect(filled['editable'], isTrue);
      expect(filled['inputClient'], 'FakeRichEditorState');
      expect(filled['text'], 'hello');
    });
  });

  testWidgets('DeltaTextInputClient receives a single replacement delta and no full update', (tester) async {
    await _pumpFocused(tester, (focusNode) => FakeDeltaEditor(focusNode: focusNode));

    final result = await _enterText({'input': 'new text', 'focused': 'true'});
    final state = tester.state<FakeDeltaEditorState>(find.byType(FakeDeltaEditor));

    expect(result['clientKind'], 'DeltaTextInputClient');
    expect(state.deltas.single, isA<TextEditingDeltaReplacement>());
    expect(state.fullUpdates, 0);
    expect(state.value.text, 'new text');
    expect(state.value.selection, const TextSelection.collapsed(offset: 8));
  });

  group('rejections', () {
    testWidgets('nothing focused: refuses instead of typing into the first field', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: controller))));

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(result['error'], startsWith('No focused element found: focus is on a focus scope'));
      expect(controller.text, isEmpty);
    });

    testWidgets('focused non-text widget: error names its type', (tester) async {
      await _pumpFocused(
        tester,
        (focusNode) => ElevatedButton(focusNode: focusNode, onPressed: () {}, child: const Text('Go')),
      );

      final result = await _enterText({'input': 'x', 'focused': 'true'});

      expect(
        result['error'],
        startsWith('Focused element is not an editable text field: Focus is not a text input'),
      );
    });

    testWidgets('selector on a non-text widget: error names its type', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Text('Plain label')))));

      final result = await _enterText({'input': 'x', 'text': 'Plain label'});

      expect(result['error'], startsWith('enterText failed: Text is not a text input'));
    });
  });
}
