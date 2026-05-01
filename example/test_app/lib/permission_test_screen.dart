import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Screen that checks and requests runtime permissions.
///
/// Each row shows the permission name, current status, and a button to
/// request it. After tapping Request the status refreshes automatically.
/// The ValueKey on each status Text is what fdb tests assert against.
class PermissionTestScreen extends StatefulWidget {
  const PermissionTestScreen({super.key});

  @override
  State<PermissionTestScreen> createState() => _PermissionTestScreenState();
}

class _PermissionTestScreenState extends State<PermissionTestScreen> {
  static const _permissions = [
    (label: 'camera', permission: Permission.camera),
    (label: 'microphone', permission: Permission.microphone),
    (label: 'location', permission: Permission.locationWhenInUse),
    (label: 'photos', permission: Permission.photos),
    (label: 'contacts', permission: Permission.contacts),
  ];

  // initState only checks status — never requests.
  // Request only happens when user explicitly taps the button.
  // This ensures fdb grant-permission can pre-grant before the screen
  // is opened, and the status will reflect granted without any dialog.

  final Map<String, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    for (final entry in _permissions) {
      final status = await entry.permission.status;
      if (mounted) {
        setState(() => _statuses[entry.label] = status);
      }
    }
  }

  Future<void> _request(String label, Permission permission) async {
    await permission.request();
    final status = await permission.status;
    if (mounted) {
      setState(() => _statuses[label] = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission Test')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton(
              key: const ValueKey('refresh_permissions'),
              onPressed: _refreshAll,
              child: const Text('Refresh All'),
            ),
          ),
          ..._permissions.map(
            (entry) => _PermissionRow(
              label: entry.label,
              status: _statuses[entry.label],
              onRequest: () => _request(entry.label, entry.permission),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.status,
    required this.onRequest,
  });

  final String label;
  final PermissionStatus? status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final statusText = status?.name ?? 'unknown';
    return ListTile(
      title: Text(label),
      subtitle: Text(
        key: ValueKey('perm_status_$label'),
        'status: $statusText',
      ),
      trailing: ElevatedButton(
        key: ValueKey('perm_request_$label'),
        onPressed: onRequest,
        child: const Text('Request'),
      ),
    );
  }
}
