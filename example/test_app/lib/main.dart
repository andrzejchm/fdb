import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

void main() {
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
  late final Timer _heartbeat;

  @override
  void initState() {
    super.initState();
    developer.log('FdbTestApp initialized', name: 'fdb_test');
    // Periodic log so we can test `fdb logs --tag fdb_test --follow`
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      developer.log('heartbeat counter=$_counter', name: 'fdb_test');
    });
  }

  @override
  void dispose() {
    _heartbeat.cancel();
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
      body: Center(
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
          ],
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
