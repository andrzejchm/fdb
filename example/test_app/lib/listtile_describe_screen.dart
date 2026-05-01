import 'package:flutter/material.dart';

/// Screen used by describe-listtile scenarios (S24–S26) and the
/// `task test:describe-listtile-button` smoke test.
///
/// Three tiles cover the distinct cases that the describe walker must handle:
///
/// 1. **Tile with trailing button** (`perm_request_camera`) — the tile has no
///    `onTap`; only the `ElevatedButton` in the trailing slot is interactive.
///    Expected: button surfaces as its own ref; tile body does NOT appear.
///
/// 2. **Tappable tile** (`tappable_tile`) — plain `ListTile` with `onTap`; no
///    interactive children. Expected: tile surfaces as one interactive ref.
///
/// 3. **Display-only tile** (`display_tile`) — no `onTap`, no interactive
///    children. Expected: does NOT appear in INTERACTIVE at all.
class ListTileDescribeScreen extends StatelessWidget {
  const ListTileDescribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ListTile Describe Test')),
      body: ListView(
        children: [
          // Case 1: tile with interactive trailing — only the button is tappable.
          ListTile(
            title: const Text('camera'),
            subtitle: const Text('status: granted'),
            trailing: ElevatedButton(
              key: const ValueKey('perm_request_camera'),
              onPressed: () {},
              child: const Text('Request'),
            ),
          ),
          // Case 2: plain tappable tile.
          ListTile(
            key: const ValueKey('tappable_tile'),
            title: const Text('Tappable tile'),
            subtitle: const Text('tap me'),
            onTap: () {},
          ),
          // Case 3: display-only tile — no gesture handler, no interactive children.
          const ListTile(
            key: ValueKey('display_tile'),
            title: Text('Display only'),
            subtitle: Text('not tappable'),
          ),
        ],
      ),
    );
  }
}
