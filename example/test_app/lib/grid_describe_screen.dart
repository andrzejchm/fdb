import 'package:flutter/material.dart';

/// A screen with two scrollable sections used by the `task test:describe-grid`
/// smoke test to verify that `fdb describe` returns off-screen children:
///
/// 1. A [SliverGrid] section (50 items, keys `grid_item_N`) — exercises the
///    [SliverChildListDelegate] path in `_collectUnbuiltDelegateWidgets`.
/// 2. A [SliverList] section (200 items, keys `list_item_N`) — exercises the
///    same delegate path for a list-style sliver so both kinds of adaptors are
///    covered by a single describe call.
///
/// Item-cap arithmetic (maxInteractive = 200):
///   50 grid items + 150 list items (0–149) = 200 total → list items 120–149
///   are within cap and reliably appear in `fdb describe` output.
class GridDescribeScreen extends StatelessWidget {
  const GridDescribeScreen({super.key});

  static const int gridItemCount = 50;
  static const int listItemCount = 200;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grid Describe Test')),
      body: CustomScrollView(
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
            ),
            delegate: SliverChildListDelegate([
              for (var i = 0; i < gridItemCount; i++)
                ElevatedButton(
                  key: Key('grid_item_$i'),
                  onPressed: () {},
                  child: Text('Item $i'),
                ),
            ]),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              for (var i = 0; i < listItemCount; i++)
                ElevatedButton(
                  key: Key('list_item_$i'),
                  onPressed: () {},
                  child: Text('List Item $i'),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
