import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'package:fdb_controller/src/controller/controller_response.dart';

Future<ControllerRequest> readControllerRequest(
  Socket socket, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final line = await utf8.decoder.bind(socket).transform(const LineSplitter()).first.timeout(timeout);
  return ControllerRequest.fromJsonLine(line);
}

Future<void> writeControllerRequest(
  Socket socket,
  ControllerRequest request,
) async {
  socket.writeln(request.toJsonLine());
  await socket.flush();
}

Future<ControllerResponse> readControllerResponse(
  Socket socket, {
  required Duration timeout,
}) async {
  final completer = Completer<ControllerResponse>();
  late final StreamSubscription<String> subscription;
  subscription = utf8.decoder.bind(socket).transform(const LineSplitter()).listen(
    (line) {
      if (!completer.isCompleted) {
        completer.complete(ControllerResponse.fromJsonLine(line));
      }
    },
    onError: (Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Controller disconnected before responding.'),
        );
      }
    },
  );

  try {
    return await completer.future.timeout(timeout);
  } finally {
    await subscription.cancel();
  }
}

Future<void> writeControllerResponse(
  Socket socket,
  CommandResponse response,
) async {
  socket.writeln(jsonEncode(_controllerResponseJson(response)));
  await socket.flush();
}

Map<String, Object?> _controllerResponseJson(CommandResponse response) {
  if (response is ControllerResponse) return response.toJson();
  final fields = Map<String, Object?>.from(response.toJson())..remove('ok');
  return response.ok
      ? ControllerResponse.success(fields).toJson()
      : ControllerResponse.failure(response.error ?? 'Command failed.').toJson();
}
