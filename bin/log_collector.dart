import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) exit(1);

  final wsUri = args[0];
  final logPath = args[1];
  final pidPath = args[2];

  File(pidPath).writeAsStringSync('$pid');

  void cleanup() {
    try {
      File(pidPath).deleteSync();
    } catch (_) {}
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen((_) => cleanup());
  ProcessSignal.sigint.watch().listen((_) => cleanup());

  try {
    await _collect(wsUri, logPath);
  } catch (_) {
  } finally {
    try {
      File(pidPath).deleteSync();
    } catch (_) {}
  }
}

Future<void> _collect(String wsUri, String logPath) async {
  final ws = await WebSocket.connect(wsUri);
  final logSink = File(logPath).openWrite(mode: FileMode.append);

  Future<void> appendLine(String line) async {
    logSink.writeln(line);
    await logSink.flush();
  }

  Future<void> pendingWrite = Future.value();

  void enqueueLine(String line) {
    pendingWrite = pendingWrite.then<void>(
      (_) => appendLine(line),
      onError: (_) => appendLine(line),
    );
  }

  for (final stream in ['Logging', 'Stdout', 'Stderr']) {
    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': 'listen_$stream',
      'method': 'streamListen',
      'params': {'streamId': stream},
    }));
  }

  final completer = Completer<void>();

  ws.listen(
    (data) {
      try {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['method'] != 'streamNotify') return;

        final params = msg['params'] as Map<String, dynamic>;
        final event = params['event'] as Map<String, dynamic>;
        final kind = event['kind'] as String?;

        if (kind == 'Logging') {
          final logRecord = event['logRecord'] as Map<String, dynamic>?;
          if (logRecord == null) return;
          final message = logRecord['message'] as Map<String, dynamic>?;
          final loggerName = logRecord['loggerName'] as Map<String, dynamic>?;
          final text = message?['valueAsString'] as String?;
          if (text == null || text.isEmpty) return;
          final name = loggerName?['valueAsString'] as String?;
          if (name != null && name.isNotEmpty) {
            enqueueLine('[$name] $text');
          } else {
            enqueueLine(text);
          }
        } else if (kind == 'WriteEvent') {
          final bytes = event['bytes'] as String?;
          if (bytes == null) return;
          try {
            final decoded = utf8.decode(base64Decode(bytes)).trimRight();
            if (decoded.isNotEmpty) {
              enqueueLine(decoded);
            }
          } catch (_) {}
        }
      } catch (_) {}
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_) {
      if (!completer.isCompleted) completer.complete();
    },
  );

  try {
    await completer.future;
    await pendingWrite;
  } finally {
    await logSink.flush();
    await logSink.close();
    await ws.close();
  }
}
