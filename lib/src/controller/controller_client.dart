import 'dart:async';
import 'dart:io';

import 'package:fdb/src/controller/commands/requests.dart';
import 'package:fdb/src/controller/commands/responses.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_transport.dart';
import 'package:fdb/src/controller/app_died_exception.dart';
import 'package:fdb/src/controller/process_utils.dart';

class ControllerUnavailable implements Exception {
  const ControllerUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class ControllerCommandFailed implements Exception {
  const ControllerCommandFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// @Throwing(AppDiedException)
/// @Throwing(ArgumentError)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<ControllerResponse> sendControllerCommand(
  ControllerCommand command, {
  Duration timeout = const Duration(seconds: 30),
}) {
  final requestFactory = _noPayloadRequestFactories[command];
  if (requestFactory == null) {
    throw ArgumentError.value(command, 'command', 'Command requires a typed request.');
  }
  return _sendControllerRequest(
    requestFactory,
    timeout: timeout,
  );
}

typedef _ClientRequestFactory = ControllerRequest Function(String token);

final _noPayloadRequestFactories = <ControllerCommand, _ClientRequestFactory>{
  ControllerCommand.status: (token) => StatusCommandRequest(token: token),
  ControllerCommand.reload: (token) => ReloadCommandRequest(token: token),
  ControllerCommand.restart: (token) => RestartCommandRequest(token: token),
  ControllerCommand.kill: (token) => KillCommandRequest(token: token),
  ControllerCommand.checkFdbHelper: (token) => CheckFdbHelperCommandRequest(token: token),
  ControllerCommand.findAllIsolateIds: (token) => FindAllIsolateIdsCommandRequest(token: token),
  ControllerCommand.findFlutterIsolateId: (token) => FindFlutterIsolateIdCommandRequest(token: token),
};

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<ControllerResponse> _sendControllerRequest(
  ControllerRequest Function(String token) createRequest, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final port = readControllerPort();
  final token = readControllerToken();
  if (port == null || token == null) {
    await _throwAppDiedIfPersistedAppStopped();
    throw const ControllerUnavailable('Controller metadata not found.');
  }

  late final Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 3),
    );
  } catch (e) {
    await _throwAppDiedIfPersistedAppStopped();
    throw ControllerUnavailable('Controller socket unavailable: $e');
  }

  await writeControllerRequest(socket, createRequest(token));

  try {
    final response = await readControllerResponse(socket, timeout: timeout);
    if (!response.ok) {
      if (response.appDied) {
        throw AppDiedException(
          logLines: response.logLines,
          reason: response.reason,
        );
      }
      throw ControllerCommandFailed(
        response.error ?? 'Controller command failed.',
      );
    }
    return response;
  } finally {
    await socket.close();
  }
}

Future<void> _throwAppDiedIfPersistedAppStopped() async {
  final appPid = readAppPid();
  if (appPid == null || isAppPidAlive(appPid)) return;

  throw await buildAppDiedException(pid: appPid);
}

/// @Throwing(AppDiedException)
/// @Throwing(ArgumentError)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<String?> checkFdbHelper() async {
  final response = await sendControllerCommand(ControllerCommand.checkFdbHelper);
  return response.field('isolateId') as String?;
}

/// @Throwing(AppDiedException)
/// @Throwing(ArgumentError)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<List<String>> findAllIsolateIds() async {
  final response = await sendControllerCommand(ControllerCommand.findAllIsolateIds);
  return (response.field('isolates') as List<dynamic>?)?.cast<String>() ?? const [];
}

/// @Throwing(AppDiedException)
/// @Throwing(ArgumentError)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<String?> findFlutterIsolateId() async {
  final response = await sendControllerCommand(ControllerCommand.findFlutterIsolateId);
  return response.field('isolateId') as String?;
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FdbBackCommandResponse> fdbBack(String isolateId) async {
  final response = await _sendControllerRequest(
    (token) => FdbBackCommandRequest(token: token, isolateId: isolateId),
  );
  return FdbBackCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FdbCleanCommandResponse> fdbClean(String isolateId) async {
  final response = await _sendControllerRequest(
    (token) => FdbCleanCommandRequest(token: token, isolateId: isolateId),
  );
  return FdbCleanCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FdbDescribeCommandResponse> fdbDescribe(String isolateId) async {
  final response = await _sendControllerRequest(
    (token) => FdbDescribeCommandRequest(token: token, isolateId: isolateId),
  );
  return FdbDescribeCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbDoubleTapCommandResponse> fdbDoubleTap(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbDoubleTapCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      index: _optionalString(params, 'index'),
      x: _optionalString(params, 'x'),
      y: _optionalString(params, 'y'),
    ),
  );
  return FdbDoubleTapCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbEnterTextCommandResponse> fdbEnterText(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbEnterTextCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      input: _string(params, 'input'),
      focused: _optionalString(params, 'focused'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      index: _optionalString(params, 'index'),
    ),
  );
  return FdbEnterTextCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbLongPressCommandResponse> fdbLongPress(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbLongPressCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      duration: _string(params, 'duration'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      index: _optionalString(params, 'index'),
      x: _optionalString(params, 'x'),
      y: _optionalString(params, 'y'),
    ),
  );
  return FdbLongPressCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbScrollCommandResponse> fdbScroll(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbScrollCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      direction: _optionalString(params, 'direction'),
      distance: _optionalString(params, 'distance'),
      at: _optionalString(params, 'at'),
      startX: _optionalString(params, 'startX'),
      startY: _optionalString(params, 'startY'),
      endX: _optionalString(params, 'endX'),
      endY: _optionalString(params, 'endY'),
    ),
  );
  return FdbScrollCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbScrollToCommandResponse> fdbScrollTo(Map<String, String> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbScrollToCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      index: _optionalString(params, 'index'),
    ),
  );
  return FdbScrollToCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbSwipeCommandResponse> fdbSwipe(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbSwipeCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      direction: _string(params, 'direction'),
      key: _optionalString(params, 'key'),
      text: _optionalString(params, 'text'),
      type: _optionalString(params, 'type'),
      at: _optionalString(params, 'at'),
      distance: _optionalString(params, 'distance'),
    ),
  );
  return FdbSwipeCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbTapCommandResponse> fdbTap(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbTapCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      index: _optionalString(params, 'index'),
      x: _optionalString(params, 'x'),
      y: _optionalString(params, 'y'),
    ),
  );
  return FdbTapCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbWaitForCommandResponse> fdbWaitFor(
  Map<String, String> params, {
  required Duration timeout,
}) async {
  final response = await _sendControllerRequest(
    (token) => FdbWaitForCommandRequest(
      token: token,
      isolateId: _string(params, 'isolateId'),
      condition: _string(params, 'condition'),
      timeoutMilliseconds: _int(params, 'timeout'),
      text: _optionalString(params, 'text'),
      key: _optionalString(params, 'key'),
      type: _optionalString(params, 'type'),
      route: _optionalString(params, 'route'),
    ),
    timeout: timeout + const Duration(seconds: 5),
  );
  return FdbWaitForCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FdbElementsCommandResponse> fdbElements(
  String isolateId, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final response = await _sendControllerRequest(
    (token) => FdbElementsCommandRequest(token: token, isolateId: isolateId),
    timeout: timeout + const Duration(seconds: 5),
  );
  return FdbElementsCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
/// @Throwing(FormatException)
Future<FdbScreenshotCommandResponse> fdbScreenshot(Map<String, dynamic> params) async {
  final response = await _sendControllerRequest(
    (token) => FdbScreenshotCommandRequest(token: token, isolateId: _string(params, 'isolateId')),
  );
  return FdbScreenshotCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FdbSharedPrefsCommandResponse> fdbSharedPrefs(
  String method,
  Map<String, dynamic> params,
) async {
  final response = await _sendControllerRequest(
    (token) => FdbSharedPrefsCommandRequest(
      token: token,
      method: method,
      sharedPrefsParams: params,
    ),
  );
  return FdbSharedPrefsCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FlutterInspectorTreeCommandResponse> flutterInspectorRootWidgetSummaryTree(
  String isolateId, {
  required String objectGroup,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final response = await _sendControllerRequest(
    (token) => FlutterInspectorRootWidgetSummaryTreeCommandRequest(
      token: token,
      isolateId: isolateId,
      objectGroup: objectGroup,
    ),
    timeout: timeout + const Duration(seconds: 5),
  );
  return FlutterInspectorTreeCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FlutterInspectorSelectedWidgetCommandResponse> flutterInspectorSelectedSummaryWidget(
  String isolateId, {
  required String objectGroup,
}) async {
  final response = await _sendControllerRequest(
    (token) => FlutterInspectorSelectedSummaryWidgetCommandRequest(
      token: token,
      isolateId: isolateId,
      objectGroup: objectGroup,
    ),
  );
  return FlutterInspectorSelectedWidgetCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FlutterInspectorShowCommandResponse> flutterInspectorShow(
  String isolateId, {
  required bool enabled,
}) async {
  final response = await _sendControllerRequest(
    (token) => FlutterInspectorShowCommandRequest(
      token: token,
      isolateId: isolateId,
      enabled: enabled,
    ),
  );
  return FlutterInspectorShowCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<FlutterInspectorTreeReadyCommandResponse> flutterInspectorWidgetTreeReady(
  String isolateId, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final response = await _sendControllerRequest(
    (token) => FlutterInspectorTreeReadyCommandRequest(token: token, isolateId: isolateId),
    timeout: timeout + const Duration(seconds: 5),
  );
  return FlutterInspectorTreeReadyCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<VmIsolateCommandResponse> getIsolate(String isolateId) async {
  final response = await _sendControllerRequest(
    (token) => GetIsolateCommandRequest(token: token, isolateId: isolateId),
  );
  return VmIsolateCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<VmMemoryUsageCommandResponse> getMemoryUsage(String isolateId) async {
  final response = await _sendControllerRequest(
    (token) => GetMemoryUsageCommandRequest(token: token, isolateId: isolateId),
  );
  return VmMemoryUsageCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<VmAllocationProfileCommandResponse> getAllocationProfile(
  String isolateId, {
  bool? gc,
  bool? reset,
}) async {
  final response = await _sendControllerRequest(
    (token) => GetAllocationProfileCommandRequest(
      token: token,
      isolateId: isolateId,
      gc: gc,
      reset: reset,
    ),
  );
  return VmAllocationProfileCommandResponse.fromResponse(_responseFields(response));
}

/// @Throwing(AppDiedException)
/// @Throwing(ControllerCommandFailed)
/// @Throwing(ControllerUnavailable)
Future<VmServiceExtensionCallCommandResponse> extCall(
  String method, {
  Map<String, dynamic> params = const {},
}) async {
  final response = await _sendControllerRequest(
    (token) => ExtCallCommandRequest(
      token: token,
      method: method,
      extensionParams: params,
    ),
  );
  return VmServiceExtensionCallCommandResponse.fromResponse(_responseFields(response));
}

Map<String, dynamic> _responseFields(ControllerResponse response) {
  final json = response.toJson();
  return (json['result'] as Map?)?.cast<String, dynamic>() ?? const {};
}

Future<bool> isControllerAvailable() async {
  try {
    final response = await sendControllerCommand(
      ControllerCommand.status,
      timeout: const Duration(seconds: 3),
    );
    return response.field('running') == true;
  } catch (_) {
    return false;
  }
}

/// @Throwing(FormatException)
String _string(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing required controller field: $name');
}

String? _optionalString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value == null) return null;
  return value.toString();
}

/// @Throwing(FormatException)
int _int(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is int) return value;
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed != null) return parsed;
  throw FormatException('Missing required integer controller field: $name');
}
