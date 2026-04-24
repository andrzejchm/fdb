import 'dart:async';
import 'dart:developer' as developer;

import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'benchmark_screens.dart';

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
  int _counter = 0;
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
