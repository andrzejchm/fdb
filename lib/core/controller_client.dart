import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/process_utils.dart';

class ControllerUnavailable implements Exception {
  const ControllerUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> sendControllerCommand(
  String command, {
  Map<String, Object?> params = const {},
  Duration timeout = const Duration(seconds: 30),
}) async {
  final port = readControllerPort();
  final token = readControllerToken();
  if (port == null || token == null) {
    throw const ControllerUnavailable('Controller metadata not found.');
  }

  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: const Duration(seconds: 3),
  );

  final completer = Completer<Map<String, dynamic>>();
  late final StreamSubscription<String> subscription;
  subscription = utf8.decoder.bind(socket).transform(const LineSplitter()).listen(
    (line) {
      final message = jsonDecode(line) as Map<String, dynamic>;
      if (!completer.isCompleted) {
        completer.complete(message);
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
          const ControllerUnavailable(
            'Controller disconnected before responding.',
          ),
        );
      }
    },
  );

  socket.writeln(
    jsonEncode({
      'token': token,
      'command': command,
      'params': params,
    }),
  );

  try {
    final response = await completer.future.timeout(timeout);
    final ok = response['ok'] == true;
    if (!ok) {
      throw ControllerUnavailable(
        response['error'] as String? ?? 'Controller command failed.',
      );
    }
    return response;
  } finally {
    await subscription.cancel();
    await socket.close();
  }
}

Future<bool> isControllerAvailable() async {
  try {
    final response = await sendControllerCommand(
      'status',
      timeout: const Duration(seconds: 3),
    );
    return response['running'] == true;
  } catch (_) {
    return false;
  }
}
