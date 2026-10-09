import 'package:flutter/material.dart';

const nestedNavigatorRoute = '/nested-navigator-test';

/// Screen for `task test:back-nested`: a screen that hosts its own nested
/// [Navigator], like a tab shell or an auto_route `AutoRouter`. `fdb back` must
/// pop the nested "details" screen first, not the root route hosting it.
class NestedNavigatorScreen extends StatelessWidget {
  const NestedNavigatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested Navigator Test')),
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => switch (settings.name) {
            'details' => const _NestedDetails(),
            _ => const _NestedList(),
          },
        ),
      ),
    );
  }
}

class _NestedList extends StatelessWidget {
  const _NestedList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nested List Content'),
          ElevatedButton(
            key: const Key('nested_open_details'),
            onPressed: () => Navigator.of(context).pushNamed('details'),
            child: const Text('Open nested details'),
          ),
        ],
      ),
    );
  }
}

class _NestedDetails extends StatelessWidget {
  const _NestedDetails();

  @override
  Widget build(BuildContext context) {
    // No back arrow: the only way out is `fdb back`.
    return const Scaffold(body: Center(child: Text('Nested Details Content')));
  }
}
