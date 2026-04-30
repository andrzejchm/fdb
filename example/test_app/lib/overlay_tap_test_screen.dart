import 'dart:developer' as developer;

import 'package:flutter/material.dart';

/// Reproduction screen for the opaque-ancestor GestureDetector tap problem.
///
/// Layout:
///   - Full-screen GestureDetector (photo_area, HitTestBehavior.opaque)
///     whose onTap toggles _overlayVisible.
///   - IgnorePointer wraps the bottom toolbar; ignoring=!_overlayVisible.
///   - When overlay is visible, buttons are fully hittable.
///
/// Counters shown on screen (and in logs) let us verify which callbacks fired:
///   overlayTapCount  — how many times photo_area.onTap fired
///   approveCount     — how many times approve_btn.onTap fired
///   rejectCount      — how many times reject_btn.onTap fired
class OverlayTapTestScreen extends StatefulWidget {
  const OverlayTapTestScreen({super.key});

  @override
  State<OverlayTapTestScreen> createState() => _OverlayTapTestScreenState();
}

class _OverlayTapTestScreenState extends State<OverlayTapTestScreen> {
  bool _overlayVisible = false;
  int _approveCount = 0;
  int _rejectCount = 0;
  int _overlayTapCount = 0;

  void _toggleOverlay() {
    _overlayTapCount++;
    setState(() => _overlayVisible = !_overlayVisible);
    developer.log(
      'photo_area onTap: overlayVisible=$_overlayVisible overlayTapCount=$_overlayTapCount',
      name: 'fdb_test',
    );
  }

  void _onApprove() {
    _approveCount++;
    setState(() {});
    developer.log('approve_btn onTap: approveCount=$_approveCount', name: 'fdb_test');
  }

  void _onReject() {
    _rejectCount++;
    setState(() {});
    developer.log('reject_btn onTap: rejectCount=$_rejectCount', name: 'fdb_test');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Overlay Tap Test'),
      ),
      body: GestureDetector(
        key: const Key('photo_area'),
        onTap: _toggleOverlay,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background "photo" area
            Container(
              color: Colors.blueGrey.shade900,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap anywhere here to toggle overlay',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'overlay: ${_overlayVisible ? "VISIBLE ✓" : "HIDDEN"}',
                    key: const Key('overlay_visible'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _overlayVisible ? Colors.greenAccent : Colors.white38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'overlayTapCount: $_overlayTapCount',
                    key: const Key('overlay_tap_count'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'approveCount: $_approveCount',
                    key: const Key('approve_count'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'rejectCount: $_rejectCount',
                    key: const Key('reject_count'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                  ),
                ],
              ),
            ),

            // Toolbar — IgnorePointer-gated, mirrors PhotoActionsToolbar
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_overlayVisible,
                child: Opacity(
                  opacity: _overlayVisible ? 1.0 : 0.3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        key: const Key('undo_btn'),
                        onTap: () => developer.log('undo_btn onTap', name: 'fdb_test'),
                        child: const _CircleButton(icon: Icons.undo, color: Colors.grey, size: 48),
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        key: const Key('approve_btn'),
                        onTap: _onApprove,
                        child: const _CircleButton(icon: Icons.check, color: Colors.green, size: 80),
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        key: const Key('reject_btn'),
                        onTap: _onReject,
                        child: const _CircleButton(icon: Icons.close, color: Colors.red, size: 80),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.color, required this.size});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.85),
        border: Border.all(color: Colors.white38, width: 1.5),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    );
  }
}
