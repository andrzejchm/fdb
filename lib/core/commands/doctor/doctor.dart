import 'dart:io';

import 'package:fdb/core/commands/doctor/doctor_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/doctor/doctor_models.dart';

/// Runs all 5 diagnostic checks in order and returns a [DoctorResult].
///
/// Check order is part of the contract:
/// `app_running` → `vm_service` → `fdb_helper` → `platform_tools` → `device`
Future<DoctorResult> runDoctor(List<String> args) async {
  final checks = <CheckResult>[];
  var failed = 0;

  // 1. app_running
  final appRunning = _checkAppRunning();
  if (appRunning) {
    checks.add(const CheckResult(name: 'app_running', status: CheckStatus.pass));
  } else {
    failed++;
    checks.add(const CheckResult(
      name: 'app_running',
      status: CheckStatus.fail,
      hint: "Run 'fdb launch --device <id> --project <path>' to start the app",
    ));
  }

  // 2. vm_service
  final vmServiceUri = appRunning ? await _checkVmService() : null;
  if (vmServiceUri != null) {
    checks.add(CheckResult(
      name: 'vm_service',
      status: CheckStatus.pass,
      values: {'VM_SERVICE_URI': vmServiceUri},
    ));
  } else {
    failed++;
    checks.add(CheckResult(
      name: 'vm_service',
      status: CheckStatus.fail,
      hint: appRunning
          ? 'App is running but VM service is unreachable. Check if the app crashed.'
          : "Run 'fdb launch --device <id> --project <path>' to start the app",
    ));
  }

  // 3. fdb_helper
  if (vmServiceUri != null && await _checkFdbHelper()) {
    checks.add(const CheckResult(name: 'fdb_helper', status: CheckStatus.pass));
  } else {
    failed++;
    checks.add(const CheckResult(
      name: 'fdb_helper',
      status: CheckStatus.fail,
      hint: 'Add fdb_helper to pubspec.yaml dev_dependencies and call FdbBinding.ensureInitialized() in main()',
    ));
  }

  // 4. platform_tools
  final tools = await _checkPlatformTools();
  if (tools.missing.isEmpty) {
    checks.add(CheckResult(
      name: 'platform_tools',
      status: CheckStatus.pass,
      values: {'TOOLS': tools.present.join(',')},
    ));
  } else {
    checks.add(CheckResult(
      name: 'platform_tools',
      status: CheckStatus.warn,
      values: {
        'TOOLS': tools.present.join(','),
        'MISSING': tools.missing.join(','),
      },
      hint: _platformToolsHint(tools.missing),
    ));
  }

  // 5. device
  final deviceOk = _checkDevice();
  if (deviceOk) {
    final device = readDevice();
    final platformInfo = readPlatformInfo();
    checks.add(CheckResult(
      name: 'device',
      status: CheckStatus.pass,
      values: {
        'DEVICE_ID': device!,
        'PLATFORM': platformInfo!.platform,
      },
    ));
  } else {
    failed++;
    checks.add(const CheckResult(
      name: 'device',
      status: CheckStatus.fail,
      hint: "Run 'fdb launch --device <id> --project <path>' to store the active device.",
    ));
  }

  return DoctorResult(checks: checks, failedCount: failed);
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
