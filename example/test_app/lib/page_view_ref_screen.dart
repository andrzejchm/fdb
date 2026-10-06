import 'package:flutter/material.dart';

const pageViewRefRoute = '/page-view-ref-test';

/// Screen for `task test:tap-ref`: a PageView that keeps the next page built
/// off screen. `fdb describe` lists that page's button with an x outside the
/// screen; `fdb tap @N` on it must fail and tap nothing.
class PageViewRefScreen extends StatefulWidget {
  const PageViewRefScreen({super.key});

  @override
  State<PageViewRefScreen> createState() => _PageViewRefScreenState();
}

class _PageViewRefScreenState extends State<PageViewRefScreen> {
  final _taps = [0, 0];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PageView Ref Test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'page0=${_taps[0]} page1=${_taps[1]}',
              key: const Key('page_view_ref_counter'),
            ),
          ),
          Expanded(
            child: PageView(
              allowImplicitScrolling: true,
              children: [
                for (var i = 0; i < 2; i++)
                  Center(
                    child: ElevatedButton(
                      key: Key('page_button_$i'),
                      onPressed: () => setState(() => _taps[i]++),
                      child: Text('Page $i button'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
