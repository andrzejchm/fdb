import 'dart:async';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/vm_service/vm.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

Future<VM?> getVm({Duration timeout = const Duration(seconds: 3)}) async {
  final service = await _connectToVMService(timeout: timeout);
  try {
    final vm = await service.getVM().timeout(timeout);
    return _vmFromService(vm);
  } finally {
    await service.dispose();
  }
}

Future<VM?> getVmFromUri(
  String wsUri, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final service = await vm_service_io.vmServiceConnectUri(wsUri).timeout(timeout);
  try {
    final vm = await service.getVM().timeout(timeout);
    return _vmFromService(vm);
  } finally {
    await service.dispose();
  }
}

Future<Map<String, dynamic>> callVmServiceMethod(
  String method, {
  Map<String, dynamic> params = const {},
  Duration timeout = const Duration(seconds: 30),
}) {
  return _vmServiceCall(method, params: params, timeout: timeout);
}

/// Calls a VM service method through `package:vm_service`.
/// Returns the normalized extension payload map.
/// Throws [AppDiedException] when the app process is detected as dead,
/// or on connection failure / timeout.
Future<Map<String, dynamic>> _vmServiceCall(
  String method, {
  Map<String, dynamic> params = const {},
  Duration timeout = const Duration(seconds: 30),
}) async {
  var uri = readVmUri();
  if (uri == null || uri.isEmpty) {
    uri = await _refreshVmUriFromController();
  }
  if (uri == null || uri.isEmpty) {
    throw StateError('VM service URI not found. Is the app running?');
  }

  // Pre-check: if the process is dead, short-circuit immediately without
  // even attempting a WebSocket connection.
  if (_isMacOsTarget()) {
    final pid = readAppPid() ?? readPid();
    if (pid != null && !isProcessAlive(pid)) {
      throw await buildAppDiedException(pid: pid);
    }
  }

  final service = await _connectToVMService(uri: uri);

  try {
    final response = await service.callMethod(method, args: params).timeout(timeout);
    return vmServiceResponseAsMap(response);
  } on TimeoutException {
    await service.dispose();
    if (_isMacOsTarget()) {
      final currentPid = readAppPid() ?? readPid();
      if (currentPid != null && !isProcessAlive(currentPid)) {
        throw await buildAppDiedException(pid: currentPid);
      }
    }
    rethrow;
  } on AppDiedException {
    try {
      await service.dispose();
    } catch (_) {}
    rethrow;
  } on vm_service.RPCError catch (error) {
    if (_isDisposedConnectionError(error)) {
      throw await _buildDeadAppError();
    }
    return vmServiceRpcErrorAsMap(error);
  } finally {
    await service.dispose();
  }
}

Future<vm_service.VmService> _connectToVMService({
  String? uri,
  Duration timeout = const Duration(seconds: 5),
}) async {
  var vmUri = uri ?? readVmUri();
  if (vmUri == null || vmUri.isEmpty) {
    vmUri = await _refreshVmUriFromController();
  }
  if (vmUri == null || vmUri.isEmpty) {
    throw StateError('VM service URI not found. Is the app running?');
  }

  return _connectToVM(vmUri, timeout: timeout);
}

/// Connects to the VM service at [uri], with a single retry if the connection
/// fails due to a missing/changed URI or connection refused (app not running).
Future<vm_service.VmService> _connectToVM(
  String uri, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  late vm_service.VmService service;
  bool retry = true;
  while (retry) {
    final wsUri = uri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

    try {
      service = await vm_service_io.vmServiceConnectUri(wsUri).timeout(timeout);
      return service;
    } on TimeoutException {
      if (_isMacOsTarget()) {
        final currentPid = readAppPid() ?? readPid();
        if (currentPid != null && !isProcessAlive(currentPid)) {
          throw await buildAppDiedException(pid: currentPid);
        }
      }
      if (retry) {
        final recovered = await _refreshVmUriFromController();
        if (recovered != null && recovered.isNotEmpty && recovered != uri) {
          uri = recovered;
          retry = false;
          continue;
        }
      }
      rethrow;
    } catch (e) {
      if (_isConnectionRefused(e) || _isDisposedConnectionError(e)) {
        if (retry) {
          final recovered = await _refreshVmUriFromController();
          if (recovered != null && recovered.isNotEmpty && recovered != uri) {
            uri = recovered;
            retry = false;
            continue;
          }
        }
        if (isAndroidTarget()) {
          final appPid = readAppPid();
          if (appPid != null && isAndroidAppPidAlive(appPid)) {
            rethrow;
          }
        }
        final pid = _isMacOsTarget() ? (readAppPid() ?? readPid()) : readPid();
        throw await buildAppDiedException(pid: pid);
      }
      if (_isMacOsTarget()) {
        final currentPid = readAppPid() ?? readPid();
        if (currentPid != null && !isProcessAlive(currentPid)) {
          throw await buildAppDiedException(pid: currentPid);
        }
      }
      rethrow;
    }
  }
  throw StateError('VM service connection failed.');
}

Future<String?> _refreshVmUriFromController() async {
  return readVmUri();
}

/// Builds an [AppDiedException] after a mid-call connection drop.
/// Uses the app PID on a macOS target (host-visible); on Android/iOS the
/// app PID lives in the device namespace and is not host-visible, so the
/// flutter-tools PID is the only useful value.
Future<AppDiedException> _buildDeadAppError() async {
  if (isAndroidTarget()) {
    final appPid = readAppPid();
    if (appPid != null && isAndroidAppPidAlive(appPid)) {
      throw StateError(
        'VM service connection closed while Android app PID is still alive',
      );
    }
  }
  final pid = _isMacOsTarget() ? (readAppPid() ?? readPid()) : readPid();
  return buildAppDiedException(pid: pid);
}

/// Returns true when the *target* device for this session is macOS desktop.
///
/// `Platform.isMacOS` checks the HOST OS (always macOS in fdb's supported
/// configurations), not the target. Reading the platform from the session file
/// is required to distinguish a macOS target from an Android or iOS target
/// when fdb itself runs on macOS. Returns false if the platform file is
/// missing (no session) — callers should treat this conservatively.
bool _isMacOsTarget() {
  final info = readPlatformInfo();
  if (info == null) return false;
  final p = info.platform.toLowerCase();
  return p == 'darwin' || p == 'macos';
}

/// Returns true when [error] indicates the OS refused the TCP connection,
/// which is the reliable signal that the VM service is no longer running.
bool _isConnectionRefused(Object error) {
  if (error is SocketException) {
    // errno 61 = ECONNREFUSED on macOS/Linux
    final errno = error.osError?.errorCode;
    return errno == 61 || errno == 111;
  }
  if (error is WebSocketException) {
    final message = error.toString().toLowerCase();
    return message.contains('connection refused') || message.contains('errno = 61') || message.contains('errno = 111');
  }
  return false;
}

bool _isDisposedConnectionError(Object error) {
  return error is vm_service.RPCError && error.message == 'Service connection disposed';
}

VM _vmFromService(vm_service.VM vm) {
  return VM(
    name: vm.name,
    pid: vm.pid,
    isolates: vm.isolates?.map((isolate) => isolate.id).whereType<String>().toList() ?? const [],
  );
}
