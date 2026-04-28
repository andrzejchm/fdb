import 'package:flutter/material.dart';

/// A screen with a GridView.count that has more items than fit on screen.
/// Used by the `task test:describe-grid` smoke test to verify that
/// `fdb describe` returns off-screen grid children.
class GridDescribeScreen extends StatelessWidget {
  const GridDescribeScreen({super.key});

  static const int itemCount = 30;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grid Describe Test'),
      ),
      body: GridView.count(
        crossAxisCount: 3,
        children: [
          for (var i = 0; i < itemCount; i++)
            ElevatedButton(
              key: Key('grid_item_$i'),
              onPressed: () {},
              child: Text('Item $i'),
            ),
        ],
      ),
    );
  }
}
