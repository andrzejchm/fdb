import 'package:flutter/material.dart';

/// A screen with GestureDetectors nested inside a Positioned widget inside a
/// Stack, matching the real-world pattern where fdb describe previously missed
/// the inner interactive widgets.
///
/// Expected by task test:describe-nested-gestures in Taskfile.yml.
class NestedGestureDescribeScreen extends StatefulWidget {
  const NestedGestureDescribeScreen({super.key});

  @override
  State<NestedGestureDescribeScreen> createState() =>
      _NestedGestureDescribeScreenState();
}

class _NestedGestureDescribeScreenState
    extends State<NestedGestureDescribeScreen> {
  String _last = 'none';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested Gesture Describe Test')),
      body: Stack(
        children: [
          // Main content
          const Center(child: Text('Main content')),

          // Bottom action bar — Positioned inside Stack.
          // The outer GestureDetector wraps the whole toolbar; the inner
          // GestureDetectors are the individual tap targets.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              // Toolbar root — outer GestureDetector (horizontalDrag only so
              // it does not absorb the inner onTap callbacks).
              onHorizontalDragUpdate: (_) {},
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      key: const ValueKey('nested_gesture_reject'),
                      onTap: () => setState(() => _last = 'reject'),
                      child: const CircleAvatar(
                        radius: 30,
                        child: Icon(Icons.close, semanticLabel: 'reject'),
                      ),
                    ),
                    GestureDetector(
                      key: const ValueKey('nested_gesture_approve'),
                      onTap: () => setState(() => _last = 'approve'),
                      child: const CircleAvatar(
                        radius: 30,
                        child: Icon(Icons.check, semanticLabel: 'approve'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Last tapped: $_last',
          key: const ValueKey('nested_gesture_last_tapped'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
