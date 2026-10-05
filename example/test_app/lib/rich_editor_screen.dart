import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

const richEditorRoute = '/rich-editor';

/// Hosts a flutter_quill editor (a `TextInputClient` that does not use
/// `EditableText`) next to a plain `TextField`, so `fdb input` and
/// `fdb input --action` can be verified against both kinds of text input.
class RichEditorScreen extends StatefulWidget {
  const RichEditorScreen({super.key});

  @override
  State<RichEditorScreen> createState() => _RichEditorScreenState();
}

class _RichEditorScreenState extends State<RichEditorScreen> {
  final _controller = QuillController.basic();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  String _sent = '';
  String _submitted = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.document.toPlainText().trim();
    developer.log('rich editor sent: $text', name: 'fdb_test');
    setState(() => _sent = text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rich Editor')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 160,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: QuillEditor(
                key: const Key('quill_editor'),
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                config: QuillEditorConfig(
                  placeholder: 'Type...',
                  textInputAction: TextInputAction.send,
                  onPerformAction: (action) {
                    if (action == TextInputAction.send) _send();
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Sent: $_sent', key: const Key('sent_label')),
            const SizedBox(height: 24),
            TextField(
              key: const Key('plain_field'),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Plain field'),
              onSubmitted: (v) => setState(() => _submitted = v),
            ),
            const SizedBox(height: 8),
            Text('Submitted: $_submitted', key: const Key('submitted_label')),
          ],
        ),
      ),
    );
  }
}
