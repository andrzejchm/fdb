import 'package:flutter/material.dart';

const inputLabelScopeRoute = '/input-label-scope-test';

/// Screen for `task test:input-label-scope`: two fields inside a screen-level
/// keyboard-dismissing GestureDetector, with a standalone "Notes" label above
/// the second one. `fdb input --text Notes` must not type into the first
/// field; `fdb input --text "Notes hint"` must type into the second.
class InputLabelScopeScreen extends StatefulWidget {
  const InputLabelScopeScreen({super.key});

  @override
  State<InputLabelScopeScreen> createState() => _InputLabelScopeScreenState();
}

class _InputLabelScopeScreenState extends State<InputLabelScopeScreen> {
  final _first = TextEditingController();
  final _second = TextEditingController();

  @override
  void initState() {
    super.initState();
    _first.addListener(_refresh);
    _second.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Input Label Scope Test')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('label_scope_first'),
                controller: _first,
              ),
              const SizedBox(height: 24),
              const Text('Notes'),
              TextField(
                key: const Key('label_scope_second'),
                controller: _second,
                decoration: const InputDecoration(hintText: 'Notes hint'),
              ),
              const SizedBox(height: 24),
              Text(
                'first=[${_first.text}] second=[${_second.text}]',
                key: const Key('label_scope_status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
