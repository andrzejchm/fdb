import 'package:flutter/material.dart';

/// A screen with a [ListTile] that contains an [ElevatedButton] in its
/// [ListTile.trailing] slot. Used by the `task test:describe-listtile-button`
/// smoke test to verify that `fdb describe` surfaces the nested button as its
/// own interactive ref, not just the enclosing [ListTile].
///
/// Expected behaviour:
/// - The [ListTile] appears as one interactive entry (e.g. `@N ListTile …`).
/// - The [ElevatedButton] appears as a **separate** interactive entry with key
///   `perm_request_camera` and its own `@M` ref.
class ListTileDescribeScreen extends StatelessWidget {
  const ListTileDescribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ListTile Describe Test')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('camera'),
            subtitle: const Text('status: granted'),
            trailing: ElevatedButton(
              key: const ValueKey('perm_request_camera'),
              onPressed: () {},
              child: const Text('Request'),
            ),
          ),
        ],
      ),
    );
  }
}
