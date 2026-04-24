import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Benchmark screens for fdb describe performance testing
// ---------------------------------------------------------------------------

/// Routes for the benchmark screens.
const benchmarkRoute = '/benchmark';
const benchmarkBaselineRoute = '/benchmark/baseline';
const benchmarkMediumRoute = '/benchmark/medium';
const benchmarkStressListRoute = '/benchmark/stress_list';
const benchmarkStressGridRoute = '/benchmark/stress_grid';
const benchmarkPathologicalRoute = '/benchmark/pathological';

/// Menu screen — navigate to individual benchmark scenarios.
class BenchmarkMenuPage extends StatelessWidget {
  const BenchmarkMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    const scenarios = [
      ('Baseline (~8 interactable)', benchmarkBaselineRoute),
      ('Medium (~50 interactable)', benchmarkMediumRoute),
      (
        'Stress List (200 ListTiles, mostly off-screen)',
        benchmarkStressListRoute,
      ),
      (
        'Stress Grid (100 cards × 2 buttons, all visible)',
        benchmarkStressGridRoute,
      ),
      (
        'Pathological (300+ interactable, all visible)',
        benchmarkPathologicalRoute,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmarks')),
      body: ListView(
        children: [
          for (final (label, route) in scenarios)
            ListTile(
              key: Key('bench_${route.split('/').last}'),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, route),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCENARIO 1: baseline — realistic mobile screen
// ~100-150 total widgets, ~8 interactable
// ---------------------------------------------------------------------------

class BenchmarkBaselinePage extends StatefulWidget {
  const BenchmarkBaselinePage({super.key});

  @override
  State<BenchmarkBaselinePage> createState() => _BenchmarkBaselinePageState();
}

class _BenchmarkBaselinePageState extends State<BenchmarkBaselinePage> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  double _volume = 0.5;
  final _nameController = TextEditingController(text: 'John Doe');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Padding + Card + Column nesting adds ~80-100 extra widget nodes
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baseline Screen'),
        actions: [
          IconButton(
            key: const Key('baseline_info'),
            icon: const Icon(Icons.info_outline),
            onPressed: () {},
            tooltip: 'Info',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Structural text / padding adds node count without being interactive
            _sectionHeader('Profile'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      key: const Key('baseline_name'),
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const TextField(
                      key: Key('baseline_email'),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Preferences'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('baseline_notifications'),
                    title: const Text('Notifications'),
                    subtitle: const Text('Receive push notifications'),
                    value: _notificationsEnabled,
                    onChanged: (v) => setState(() => _notificationsEnabled = v),
                  ),
                  SwitchListTile(
                    key: const Key('baseline_dark_mode'),
                    title: const Text('Dark Mode'),
                    value: _darkMode,
                    onChanged: (v) => setState(() => _darkMode = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Volume'),
            Slider(
              key: const Key('baseline_volume'),
              value: _volume,
              onChanged: (v) => setState(() => _volume = v),
            ),
            const SizedBox(height: 24),
            // Add padding widgets, text labels, dividers to inflate node count
            for (var i = 0; i < 12; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Info line ${i + 1} — static, non-interactive'),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('baseline_save'),
                onPressed: () {},
                child: const Text('Save Changes'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('baseline_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCENARIO 2: medium — settings-style screen, ~50 interactable
// ---------------------------------------------------------------------------

class BenchmarkMediumPage extends StatefulWidget {
  const BenchmarkMediumPage({super.key});

  @override
  State<BenchmarkMediumPage> createState() => _BenchmarkMediumPageState();
}

class _BenchmarkMediumPageState extends State<BenchmarkMediumPage> {
  final _switches = List<bool>.filled(20, false);
  final _radios = List<int>.filled(6, 0);
  final _checkboxes = List<bool>.filled(12, false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medium Screen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
            tooltip: 'Filter',
          ),
        ],
      ),
      body: ListView(
        children: [
          // 20 SwitchListTiles
          _buildSectionHeader('Toggles (20)'),
          for (var i = 0; i < 20; i++)
            SwitchListTile(
              key: Key('medium_switch_$i'),
              title: Text('Setting ${i + 1}'),
              subtitle: Text('Toggle option ${i + 1}'),
              value: _switches[i],
              onChanged: (v) => setState(() => _switches[i] = v),
            ),
          _buildSectionHeader('Radio Groups (6 groups × 3 options = 18)'),
          for (var g = 0; g < 6; g++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Group ${g + 1}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            RadioGroup<int>(
              groupValue: _radios[g],
              onChanged: (v) => setState(() => _radios[g] = v!),
              child: Column(
                children: [
                  for (var opt = 0; opt < 3; opt++)
                    RadioListTile<int>(
                      key: Key('medium_radio_${g}_$opt'),
                      title: Text('Option $opt'),
                      value: opt,
                    ),
                ],
              ),
            ),
          ],
          _buildSectionHeader('Checkboxes (12)'),
          for (var i = 0; i < 12; i++)
            CheckboxListTile(
              key: Key('medium_checkbox_$i'),
              title: Text('Checkbox item ${i + 1}'),
              value: _checkboxes[i],
              onChanged: (v) => setState(() => _checkboxes[i] = v!),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

// ---------------------------------------------------------------------------
// SCENARIO 3: stress_list — ListView.builder with 200 ListTiles
// Each tile has IconButton + Switch. Most off-screen (viewport-clipped).
// ---------------------------------------------------------------------------

class BenchmarkStressListPage extends StatefulWidget {
  const BenchmarkStressListPage({super.key});

  @override
  State<BenchmarkStressListPage> createState() =>
      _BenchmarkStressListPageState();
}

class _BenchmarkStressListPageState extends State<BenchmarkStressListPage> {
  final _switches = List<bool>.filled(200, false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stress List')),
      body: ListView.builder(
        itemCount: 200,
        itemBuilder: (context, index) {
          return ListTile(
            key: Key('stress_list_tile_$index'),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text('Item ${index + 1}'),
            subtitle: Text('Subtitle for item ${index + 1}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('stress_list_icon_$index'),
                  icon: const Icon(Icons.star_border),
                  tooltip: 'Favourite item ${index + 1}',
                  onPressed: () {},
                ),
                Switch(
                  key: Key('stress_list_switch_$index'),
                  value: _switches[index],
                  onChanged: (v) => setState(() => _switches[index] = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCENARIO 4: stress_grid — GridView with 100 Cards, 2 IconButtons each
// All rendered inside the viewport (2-column, short items).
// ---------------------------------------------------------------------------

class BenchmarkStressGridPage extends StatelessWidget {
  const BenchmarkStressGridPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stress Grid')),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.6,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: 100,
        padding: const EdgeInsets.all(4),
        itemBuilder: (context, index) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Card ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: Key('grid_like_$index'),
                        icon: const Icon(Icons.thumb_up_outlined, size: 18),
                        onPressed: () {},
                        tooltip: 'Like card ${index + 1}',
                        iconSize: 18,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        key: Key('grid_share_$index'),
                        icon: const Icon(Icons.share, size: 18),
                        onPressed: () {},
                        tooltip: 'Share card ${index + 1}',
                        iconSize: 18,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCENARIO 5: pathological — Wrap with 300+ chips + GestureDetectors
// Deeply nested, all visible on screen via scrollable Wrap
// ---------------------------------------------------------------------------

class BenchmarkPathologicalPage extends StatefulWidget {
  const BenchmarkPathologicalPage({super.key});

  @override
  State<BenchmarkPathologicalPage> createState() =>
      _BenchmarkPathologicalPageState();
}

class _BenchmarkPathologicalPageState extends State<BenchmarkPathologicalPage> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pathological Screen')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '300 FilterChips + 50 GestureDetector tiles',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // 300 FilterChips in a Wrap — creates 1000+ widget nodes
            // Each FilterChip is: FilterChip > RawChip > InkWell + Stack + ...
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < 300; i++)
                  FilterChip(
                    key: Key('path_chip_$i'),
                    label: Text('Tag ${i + 1}'),
                    selected: _selected.contains(i),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selected.add(i);
                      } else {
                        _selected.remove(i);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'GestureDetector rows',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // 50 GestureDetectors with text labels
            for (var i = 0; i < 50; i++)
              GestureDetector(
                key: Key('path_gesture_$i'),
                onTap: () {},
                onLongPress: () {},
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 8,
                  ),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_handle, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('Gesture item ${i + 1}'),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
