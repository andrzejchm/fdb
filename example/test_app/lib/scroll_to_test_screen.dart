import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

const scrollToTestRoute = '/scroll-to-test';
const scrollToTestLazyRoute = '/scroll-to-test/lazy-list';
const scrollToTestHorizontalRoute = '/scroll-to-test/horizontal';
const scrollToTestReversedRoute = '/scroll-to-test/reversed';
const scrollToTestAlreadyVisibleRoute = '/scroll-to-test/already-visible';

// ---------------------------------------------------------------------------
// Screen A — router / menu
// ---------------------------------------------------------------------------

class ScrollToTestPage extends StatelessWidget {
  const ScrollToTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('scroll_to_test_home'),
      appBar: AppBar(title: const Text('Scroll-To Tests')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('go_to_lazy_list'),
            title: const Text('Lazy List (100 items)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, scrollToTestLazyRoute),
          ),
          ListTile(
            key: const Key('go_to_horizontal'),
            title: const Text('Horizontal List (50 items)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.pushNamed(context, scrollToTestHorizontalRoute),
          ),
          ListTile(
            key: const Key('go_to_reversed'),
            title: const Text('Reversed List (60 items)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.pushNamed(context, scrollToTestReversedRoute),
          ),
          ListTile(
            key: const Key('go_to_already_visible'),
            title: const Text('Already Visible (5 items)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.pushNamed(context, scrollToTestAlreadyVisibleRoute),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen B — lazy vertical list (100 items)
// ---------------------------------------------------------------------------

class LazyListScrollToPage extends StatelessWidget {
  const LazyListScrollToPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lazy List')),
      body: ListView.builder(
        itemCount: 100,
        itemBuilder: (context, index) {
          return ListTile(
            key: Key('lazy_item_$index'),
            title: Text('Lazy item $index'),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen C — horizontal list (50 items)
// ---------------------------------------------------------------------------

class HorizontalListScrollToPage extends StatelessWidget {
  const HorizontalListScrollToPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Horizontal List')),
      body: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 50,
        itemBuilder: (context, index) {
          return Container(
            key: Key('h_item_$index'),
            width: 120,
            color: Colors.primaries[index % Colors.primaries.length].withValues(
              alpha: 0.3,
            ),
            alignment: Alignment.center,
            child: Text('H-item $index'),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen D — reversed list (60 items)
// ---------------------------------------------------------------------------

class ReversedListScrollToPage extends StatelessWidget {
  const ReversedListScrollToPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reversed List')),
      body: ListView.builder(
        reverse: true,
        itemCount: 60,
        itemBuilder: (context, index) {
          return ListTile(
            key: Key('rev_item_$index'),
            title: Text('Rev item $index'),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen E — already-visible list (5 items, all on screen)
// ---------------------------------------------------------------------------

class AlreadyVisibleScrollToPage extends StatelessWidget {
  const AlreadyVisibleScrollToPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Already Visible')),
      body: ListView.builder(
        itemCount: 5,
        itemBuilder: (context, index) {
          return ListTile(
            key: Key('visible_item_$index'),
            title: Text('Visible item $index'),
          );
        },
      ),
    );
  }
}
