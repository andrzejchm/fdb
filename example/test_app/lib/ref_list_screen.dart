import 'package:flutter/material.dart';

const refListRoute = '/ref-list-test';

/// Screen for `task test:tap-ref`: a list of rows with a tap counter per row.
/// The counter line sits outside the list, so the test can check which row a
/// `fdb tap @N` reached after the list scrolled.
class RefListScreen extends StatefulWidget {
  const RefListScreen({super.key});

  @override
  State<RefListScreen> createState() => _RefListScreenState();
}

class _RefListScreenState extends State<RefListScreen> {
  final _taps = <int, int>{};

  @override
  Widget build(BuildContext context) {
    final counts = _taps.entries.map((e) => 'row${e.key}=${e.value}').join(' ');
    return Scaffold(
      appBar: AppBar(title: const Text('Ref List Test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('taps: ${counts.isEmpty ? 'none' : counts}', key: const Key('ref_list_counter')),
          ),
          Expanded(
            child: ListView(
              key: const Key('ref_list'),
              children: [
                for (var i = 0; i < 40; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ElevatedButton(
                      key: Key('ref_row_$i'),
                      onPressed: () => setState(() => _taps[i] = (_taps[i] ?? 0) + 1),
                      child: Text('Row $i'),
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
