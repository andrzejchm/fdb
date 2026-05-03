import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/controller_request.dart';
import 'package:fdb/controller/controller_response.dart';

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
  socket.writeln(jsonEncode(response.toJson()));
  await socket.flush();
}
