import 'dart:io';

import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_service.dart';

Future<int> runDoctor(List<String> args) async {
  var failed = 0;
  final appRunning = _checkAppRunning();

  if (appRunning) {
    _printCheck('app_running', 'pass');
  } else {
    failed++;
    _printCheck(
      'app_running',
      'fail',
      hint: "Run 'fdb launch --device <id> --project <path>' to start the app",
    );
  }

  final vmServiceUri = appRunning ? await _checkVmService() : null;
  if (vmServiceUri != null) {
    _printCheck('vm_service', 'pass', values: {'VM_SERVICE_URI': vmServiceUri});
  } else {
    failed++;
    _printCheck(
      'vm_service',
      'fail',
      hint: appRunning
          ? 'App is running but VM service is unreachable. Check if the app crashed.'
          : "Run 'fdb launch --device <id> --project <path>' to start the app",
    );
  }

  if (vmServiceUri != null && await _checkFdbHelper()) {
    _printCheck('fdb_helper', 'pass');
  } else {
    failed++;
    _printCheck(
      'fdb_helper',
      'fail',
      hint: 'Add fdb_helper to pubspec.yaml dev_dependencies and call FdbBinding.ensureInitialized() in main()',
    );
  }

  final tools = await _checkPlatformTools();
  if (tools.missing.isEmpty) {
    _printCheck('platform_tools', 'pass', values: {'TOOLS': tools.present.join(',')});
  } else {
    _printCheck(
      'platform_tools',
      'warn',
      values: {
        'TOOLS': tools.present.join(','),
        'MISSING': tools.missing.join(','),
      },
      hint: _platformToolsHint(tools.missing),
    );
  }

  if (_checkDevice()) {
    final device = readDevice();
    final platformInfo = readPlatformInfo();
    _printCheck(
      'device',
      'pass',
      values: {
        'DEVICE_ID': device!,
        'PLATFORM': platformInfo!.platform,
      },
    );
  } else {
    failed++;
    _printCheck(
      'device',
      'fail',
      hint: "Run 'fdb launch --device <id> --project <path>' to store the active device.",
    );
  }

  final summary = failed == 0 ? 'pass' : 'fail';
  stdout.writeln('DOCTOR_SUMMARY=$summary CHECKS=5 FAILED=$failed');
  return 0;
}

bool _checkAppRunning() {
  final pid = readPid();
  return pid != null && isProcessAlive(pid);
}

Future<String?> _checkVmService() async {
  try {
    final response = await vmServiceCall('getVM', timeout: const Duration(seconds: 3));
    final result = response['result'] as Map<String, dynamic>?;
    if (response['error'] != null || result == null) return null;
    final uri = readVmUri();
    if (uri == null || uri.isEmpty) return null;
    return uri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  } catch (_) {
    return null;
  }
}

Future<bool> _checkFdbHelper() async {
  final isolateId = await checkFdbHelper();
  return isolateId != null;
}

Future<({List<String> present, List<String> missing})> _checkPlatformTools() async {
  final present = <String>[];
  final missing = <String>[];

  for (final tool in ['adb', 'xcrun', 'screencapture']) {
    final result = await Process.run('which', [tool]);
    if (result.exitCode == 0) {
      present.add(tool);
    } else {
      missing.add(tool);
    }
  }

  return (present: present, missing: missing);
}

String _platformToolsHint(List<String> missing) {
  final hints = <String>[];
  if (missing.contains('adb')) {
    hints.add('adb missing — Android screenshots and interactions will fail. Install Android platform-tools.');
  }
  if (missing.contains('xcrun')) {
    hints.add('xcrun missing — iOS simulator screenshots will fail. Install Xcode.');
  }
  if (missing.contains('screencapture')) {
    hints.add('screencapture missing — macOS screenshots will fail. Use a macOS host with screencapture available.');
  }
  return hints.join(' ');
}

bool _checkDevice() {
  final device = readDevice();
  final platformInfo = readPlatformInfo();
  return device != null && platformInfo != null;
}

void _printCheck(
  String name,
  String status, {
  Map<String, String> values = const {},
  String? hint,
}) {
  final parts = [
    'DOCTOR_CHECK=$name',
    'STATUS=$status',
    for (final entry in values.entries)
      if (entry.value.isNotEmpty) '${entry.key}=${entry.value}',
    if (hint != null) 'HINT=$hint',
  ];
  stdout.writeln(parts.join(' '));
}
