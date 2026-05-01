import 'package:flutter/material.dart';

/// Screen used by describe-listtile scenarios (S24–S27) and the
/// `task test:describe-listtile-button` smoke test.
///
/// Cases:
///
/// 1. **Tile with trailing button** (`perm_request_camera`) — tile has no
///    `onTap`; only the `ElevatedButton` in trailing is interactive.
///    Breadcrumb: the tile text "camera · status: granted" should appear above.
///
/// 2. **Tappable tile** (`tappable_tile`) — plain `ListTile` with `onTap`.
///    No breadcrumb needed (the tile itself is the interactive element).
///
/// 3. **Display-only tile** (`display_tile`) — no `onTap`, no interactive
///    children. Does NOT appear in INTERACTIVE at all.
///
/// 4. **Card wrapping a tile with trailing buttons** — tests deeper nesting.
///    Two buttons inside a tile inside a keyed Card. Breadcrumb should show
///    both the Card and the ListTile as ancestors.
///
/// 5. **Bare button with no meaningful ancestors** — an ElevatedButton sitting
///    directly in the ListView. No breadcrumb expected.
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
          // Case 4: Card > ListTile > two trailing buttons — deeper nesting.
          Card(
            key: const ValueKey('contact_card'),
            child: ListTile(
              title: const Text('John Doe'),
              subtitle: const Text('+1 555-0123'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('call_john'),
                    icon: const Icon(Icons.phone),
                    onPressed: () {},
                  ),
                  IconButton(
                    key: const ValueKey('delete_john'),
                    icon: const Icon(Icons.delete),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          // Case 5: bare button — no meaningful parent context.
          ElevatedButton(
            key: const ValueKey('bare_button'),
            onPressed: () {},
            child: const Text('Bare Button'),
          ),
        ],
      ),
    );
  }
}
