import 'dart:async';
import 'dart:developer' as developer;

import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'benchmark_screens.dart';
import 'grid_describe_screen.dart';
import 'native_view_test_screen.dart';
import 'overlay_tap_test_screen.dart';
import 'scroll_to_test_screen.dart';

void main() {
  if (!kReleaseMode) {
    FdbBinding.ensureInitialized();
  }
  runApp(const FdbTestApp());
}

class FdbTestApp extends StatelessWidget {
  const FdbTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fdb test app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const FdbTestHomePage(),
      routes: {
        benchmarkRoute: (_) => const BenchmarkMenuPage(),
        benchmarkBaselineRoute: (_) => const BenchmarkBaselinePage(),
        benchmarkMediumRoute: (_) => const BenchmarkMediumPage(),
        benchmarkStressListRoute: (_) => const BenchmarkStressListPage(),
        benchmarkStressGridRoute: (_) => const BenchmarkStressGridPage(),
        benchmarkPathologicalRoute: (_) => const BenchmarkPathologicalPage(),
        '/native-view-test': (_) => const NativeViewTestScreen(),
        '/grid-describe-test': (_) => const GridDescribeScreen(),
        scrollToTestRoute: (_) => const ScrollToTestPage(),
        scrollToTestLazyRoute: (_) => const LazyListScrollToPage(),
        scrollToTestHorizontalRoute: (_) => const HorizontalListScrollToPage(),
        scrollToTestReversedRoute: (_) => const ReversedListScrollToPage(),
        scrollToTestAlreadyVisibleRoute: (_) =>
            const AlreadyVisibleScrollToPage(),
        '/overlay-tap-test': (_) => const OverlayTapTestScreen(),
      },
    );
  }
}

class FdbTestHomePage extends StatefulWidget {
  const FdbTestHomePage({super.key});

  @override
  State<FdbTestHomePage> createState() => _FdbTestHomePageState();
}

class _FdbTestHomePageState extends State<FdbTestHomePage> {
  static const _nativeDialogChannel = MethodChannel('fdb_test/native_dialog');
  int _counter = 0;
  int _doubleTapCount = 0;
  String _nativeAlertResult = 'not shown';
  int _secondaryDoubleTapCount = 0;
  int _indexedDoubleTapPrimaryCount = 0;
  int _indexedDoubleTapSecondaryCount = 0;
  bool _showDelayed = false;
  final _textController = TextEditingController();
  late final Timer _heartbeat;

  @override
  void initState() {
    super.initState();
    developer.log('FdbTestApp initialized', name: 'fdb_test');
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      developer.log('heartbeat counter=$_counter', name: 'fdb_test');
    });
  }

  @override
  void dispose() {
    _heartbeat.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _increment() {
    setState(() {
      _counter++;
    });
    developer.log('counter incremented to $_counter', name: 'fdb_test');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('fdb test app'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('fdb integration test target'),
              const SizedBox(height: 16),
              Text(
                'Counter: $_counter',
                key: const Key('counter_text'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: TextField(
                  key: const Key('test_input'),
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'Test input',
                    hintText: 'Type something...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('submit_button'),
                onPressed: () {
                  developer.log(
                    'submitted: ${_textController.text}',
                    name: 'fdb_test',
                  );
                },
                child: const Text('Submit'),
              ),
              const SizedBox(height: 16),
              // Navigation buttons
              ElevatedButton(
                key: const Key('go_to_details'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DetailPage()),
                  );
                },
                child: const Text('Go to Details'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('show_dialog'),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Test Dialog'),
                      content: const Text('This is a test dialog.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
              const SizedBox(height: 16),
              // Two Save buttons for --index testing
              ElevatedButton(
                key: const Key('save_button_0'),
                onPressed: () {
                  developer.log('save_button_0 pressed', name: 'fdb_test');
                },
                child: const Text('Save'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('save_button_1'),
                onPressed: () {
                  developer.log('save_button_1 pressed', name: 'fdb_test');
                },
                child: const Text('Save'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('go_to_benchmarks'),
                onPressed: () => Navigator.pushNamed(context, benchmarkRoute),
                child: const Text('Benchmarks'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('go_to_scroll_to_test'),
                onPressed: () =>
                    Navigator.pushNamed(context, scrollToTestRoute),
                child: const Text('Scroll-To Tests'),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('go_to_native_view_test'),
                onPressed: () =>
                    Navigator.pushNamed(context, '/native-view-test'),
                child: const Text('Native View Test'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('go_to_grid_describe_test'),
                onPressed: () =>
                    Navigator.pushNamed(context, '/grid-describe-test'),
                child: const Text('Grid Describe Test'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('go_to_overlay_tap_test'),
                onPressed: () =>
                    Navigator.pushNamed(context, '/overlay-tap-test'),
                child: const Text('Overlay Tap Test'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('show_native_alert'),
                onPressed: () async {
                  try {
                    final result = await _nativeDialogChannel
                        .invokeMethod<String>('showNativeAlert');
                    if (mounted) {
                      setState(() => _nativeAlertResult = result ?? 'null');
                    }
                    developer.log(
                      'native alert result: $result',
                      name: 'fdb_test',
                    );
                  } catch (e) {
                    if (mounted) {
                      setState(() => _nativeAlertResult = 'ERROR: $e');
                    }
                  }
                },
                child: const Text('Show Native Alert'),
              ),
              Text(
                'Native alert: $_nativeAlertResult',
                key: const Key('native_alert_result'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('show_delayed'),
                onPressed: () async {
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (mounted) {
                    setState(() {
                      _showDelayed = true;
                    });
                  }
                },
                child: const Text('Show Delayed'),
              ),
              if (_showDelayed)
                ElevatedButton(
                  key: const Key('delayed_button'),
                  onPressed: () {},
                  child: const Text('I was delayed'),
                ),
              const SizedBox(height: 16),
              Text(
                'Double tap summary: primary=$_doubleTapCount secondary=$_secondaryDoubleTapCount',
                key: const Key('double_tap_summary'),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const Key('double_tap_target'),
                onDoubleTap: () {
                  setState(() {
                    _doubleTapCount++;
                  });
                  developer.log(
                    'double_tap_target triggered count=$_doubleTapCount',
                    name: 'fdb_test',
                  );
                },
                child: Container(
                  width: 200,
                  height: 60,
                  color: Colors.purple.shade100,
                  alignment: Alignment.center,
                  child: const Text('Double Tap Target'),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const Key('double_tap_target_secondary'),
                onDoubleTap: () {
                  setState(() {
                    _secondaryDoubleTapCount++;
                  });
                  developer.log(
                    'double_tap_target_secondary triggered count=$_secondaryDoubleTapCount',
                    name: 'fdb_test',
                  );
                },
                child: Container(
                  width: 200,
                  height: 60,
                  color: Colors.purple.shade50,
                  alignment: Alignment.center,
                  child: const Text('Double Tap Target'),
                ),
              ),
              const SizedBox(height: 16),
              // GestureDetector for long-press testing
              GestureDetector(
                key: const Key('longpress_target'),
                onLongPress: () {
                  developer.log('longpress_target triggered', name: 'fdb_test');
                },
                child: Container(
                  width: 200,
                  height: 60,
                  color: Colors.teal.shade100,
                  alignment: Alignment.center,
                  child: const Text('Long Press Me'),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const Key('indexed_double_tap_target_primary'),
                onDoubleTap: () {
                  setState(() {
                    _indexedDoubleTapPrimaryCount++;
                  });
                  developer.log(
                    'indexed_double_tap_target_primary triggered count=$_indexedDoubleTapPrimaryCount',
                    name: 'fdb_test',
                  );
                },
                child: Container(
                  width: 200,
                  height: 60,
                  color: Colors.deepPurple.shade100,
                  alignment: Alignment.center,
                  child: const Text('Indexed Double Tap Target'),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const Key('indexed_double_tap_target_secondary'),
                onDoubleTap: () {
                  setState(() {
                    _indexedDoubleTapSecondaryCount++;
                  });
                  developer.log(
                    'indexed_double_tap_target_secondary triggered count=$_indexedDoubleTapSecondaryCount',
                    name: 'fdb_test',
                  );
                },
                child: Container(
                  width: 200,
                  height: 60,
                  color: Colors.deepPurple.shade50,
                  alignment: Alignment.center,
                  child: const Text('Indexed Double Tap Target'),
                ),
              ),
              const SizedBox(height: 16),
              // PageView for swipe testing
              SizedBox(
                height: 200,
                child: PageView(
                  key: const Key('page_view'),
                  children: [
                    Container(
                      color: Colors.blue.shade100,
                      alignment: Alignment.center,
                      child: const Text('Page 1'),
                    ),
                    Container(
                      color: Colors.green.shade100,
                      alignment: Alignment.center,
                      child: const Text('Page 2'),
                    ),
                    Container(
                      color: Colors.orange.shade100,
                      alignment: Alignment.center,
                      child: const Text('Page 3'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Extra items to make the body scrollable
              for (var i = 1; i <= 10; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('Extra item $i'),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('increment_button'),
        onPressed: _increment,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Detail Page'),
      ),
      body: const Center(child: Text('Detail Page Content')),
    );
  }
}
