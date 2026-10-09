import 'package:flutter/material.dart';

const nestedNavigatorRoute = '/nested-navigator-test';

/// Screen for `task test:back-nested`: a screen that hosts its own nested
/// [Navigator], like a tab shell or an auto_route `AutoRouter`. It forwards
/// system back presses to that navigator with [NavigatorPopHandler], as Flutter
/// recommends, so a real back press (and `fdb back`) pops the nested "details"
/// screen first, then this screen.
class NestedNavigatorScreen extends StatefulWidget {
  const NestedNavigatorScreen({super.key});

  @override
  State<NestedNavigatorScreen> createState() => _NestedNavigatorScreenState();
}

class _NestedNavigatorScreenState extends State<NestedNavigatorScreen> {
  final _nestedKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested Navigator Test')),
      body: NavigatorPopHandler<void>(
        onPopWithResult: (_) => _nestedKey.currentState!.maybePop(),
        child: Navigator(
          key: _nestedKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => switch (settings.name) {
              'details' => const _NestedDetails(),
              _ => const _NestedList(),
            },
          ),
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
