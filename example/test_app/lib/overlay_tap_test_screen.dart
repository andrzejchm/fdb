import 'dart:developer' as developer;

import 'package:flutter/material.dart';

/// Reproduces the PhotoActionsToolbar tap problem:
///
/// - A full-screen [GestureDetector] (photo area) with [onTap] toggles
///   [_overlayVisible].
/// - When visible, the toolbar buttons are wrapped in
///   [IgnorePointer(ignoring: false)] — so they ARE hittable.
/// - But the outer GestureDetector also covers the same area, so a synthetic
///   tap dispatched by fdb at the button's center coordinates may be consumed
///   by the outer GD instead of (or in addition to) the inner button GD.
///
/// Keys used in fdb tests:
///   photo_area         — the full-screen toggle tap target
///   overlay_visible    — Text showing current overlay state
///   approve_btn        — approve button (GestureDetector)
///   reject_btn         — reject button (GestureDetector)
///   undo_btn           — undo button (GestureDetector)
///   approve_count      — Text showing how many times approve fired
///   reject_count       — Text showing how many times reject fired
///   overlay_tap_count  — Text showing how many times photo area was tapped
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
    setState(() {
      _overlayVisible = !_overlayVisible;
    });
    developer.log(
      'photo_area onTap fired: overlayVisible=$_overlayVisible overlayTapCount=$_overlayTapCount',
      name: 'fdb_test',
    );
  }

  void _onApprove() {
    _approveCount++;
    setState(() {});
    developer.log('approve_btn onTap fired: approveCount=$_approveCount', name: 'fdb_test');
  }

  void _onReject() {
    _rejectCount++;
    setState(() {});
    developer.log('reject_btn onTap fired: rejectCount=$_rejectCount', name: 'fdb_test');
  }

  @override
  Widget build(BuildContext context) {
    // Mirrors PhotoActionsToolbar exactly:
    // - Outer GestureDetector covers the full area (photo + toolbar)
    // - IgnorePointer controls whether toolbar buttons receive hits
    // - When overlayVisible, IgnorePointer.ignoring = false (buttons are hittable)
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Overlay Tap Test'),
      ),
      body: GestureDetector(
        key: const Key('photo_area'),
        onTap: _toggleOverlay,
        // opaque = ancestor GestureDetector absorbs ALL hits, including those
        // at button coordinates. This is what PhotoActionsToolbar uses when
        // _swipeEnabled=true (showSwipeHint && enabled). This is the failure mode.
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // "Photo area" background
            Container(
              color: Colors.blueGrey.shade900,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Photo Area — tap to toggle overlay',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'overlay: ${_overlayVisible ? "VISIBLE" : "HIDDEN"}',
                    key: const Key('overlay_visible'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
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

            // Toolbar at the bottom — exactly mirrors PhotoActionsToolbar structure:
            // IgnorePointer wraps the button row; ignoring flips with overlayVisible.
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
                        onTap: () {
                          developer.log('undo_btn tapped', name: 'fdb_test');
                        },
                        child: _CircleButton(icon: Icons.undo, color: Colors.grey, size: 48),
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        key: const Key('approve_btn'),
                        onTap: _onApprove,
                        child: _CircleButton(icon: Icons.check, color: Colors.green, size: 80),
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        key: const Key('reject_btn'),
                        onTap: _onReject,
                        child: _CircleButton(icon: Icons.close, color: Colors.red, size: 80),
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
