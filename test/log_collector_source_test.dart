import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/log_collector_source.dart';
import 'package:test/test.dart';

void main() {
  group('generated log collector', () {
    test('fdb logs --follow streams Logging and WriteEvent lines while running', () async {
      final tempDir = await Directory.systemTemp.createTemp('fdb_log_collector_test');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sessionDir = Directory('${tempDir.path}/.fdb')..createSync(recursive: true);
      final logPath = '${sessionDir.path}/logs.txt';
      final pidPath = '${sessionDir.path}/collector.pid';
      final sourcePath = '${tempDir.path}/collector.dart';
      final followScriptPath = '${tempDir.path}/follow_logs.dart';
      await File(sourcePath).writeAsString(logCollectorSource);
      await File(followScriptPath).writeAsString(_followLogsScript);

      final allowClose = Completer<void>();

      final server = await _startServer((socket) async {
        var listenRequests = 0;

        await for (final data in socket) {
          final request = jsonDecode(data as String) as Map<String, dynamic>;
          if (request['method'] != 'streamListen') {
            continue;
          }

          listenRequests++;
          if (listenRequests != 3) {
            continue;
          }

          socket.add(jsonEncode(_loggingEvent('ui', 'logging line')));
          socket.add(jsonEncode(_writeEvent('stdout line\n')));
          await allowClose.future;
          await socket.close();
        }
      });
      addTearDown(() async => server.close(force: true));

      final process = await Process.start('dart', [
        sourcePath,
        _wsUri(server),
        logPath,
        pidPath,
      ]);
      addTearDown(() async {
        process.kill();
        await process.exitCode;
      });

      await _waitForFile(logPath);

      final followProcess = await Process.start('dart', [
        '--packages=${_packageConfigPath()}',
        followScriptPath,
        tempDir.path,
      ]);
      addTearDown(() async {
        followProcess.kill();
        await followProcess.exitCode;
      });

      final lines = await _waitForProcessLines(
        followProcess.stdout,
        2,
      );
      expect(lines, ['[ui] logging line', 'stdout line']);
      allowClose.complete();
    });

    test('keeps latest lines readable after an unexpected VM stream crash', () async {
      final tempDir = await Directory.systemTemp.createTemp('fdb_log_collector_test');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sessionDir = Directory('${tempDir.path}/.fdb')..createSync(recursive: true);
      final logPath = '${sessionDir.path}/logs.txt';
      final pidPath = '${sessionDir.path}/collector.pid';
      final sourcePath = '${tempDir.path}/collector.dart';
      await File(sourcePath).writeAsString(logCollectorSource);

      final crashComplete = Completer<void>();
      late HttpServer server;
      server = await _startServer((socket) async {
        var listenRequests = 0;

        await for (final data in socket) {
          final request = jsonDecode(data as String) as Map<String, dynamic>;
          if (request['method'] != 'streamListen') {
            continue;
          }

          listenRequests++;
          if (listenRequests != 3) {
            continue;
          }

          socket.add(jsonEncode(_loggingEvent('crash', 'logging line')));
          socket.add(jsonEncode(_writeEvent('stdout before crash\n')));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await server.close(force: true);
          if (!crashComplete.isCompleted) {
            crashComplete.complete();
          }
        }
      });
      addTearDown(() async => server.close(force: true));

      final collectorProcess = await Process.start('dart', [
        sourcePath,
        _wsUri(server),
        logPath,
        pidPath,
      ]);
      addTearDown(() async {
        collectorProcess.kill();
        await collectorProcess.exitCode;
      });

      await crashComplete.future.timeout(const Duration(seconds: 5));
      expect(
        await _waitForLogLines(logPath, 2),
        ['[crash] logging line', 'stdout before crash'],
      );
    });

    test('awaits queued flushes before closing the sink', () async {
      final tempDir = await Directory.systemTemp.createTemp('fdb_log_collector_test');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sessionDir = Directory('${tempDir.path}/.fdb')..createSync(recursive: true);
      final logPath = '${sessionDir.path}/logs.txt';
      final pidPath = '${sessionDir.path}/collector.pid';
      final sourcePath = '${tempDir.path}/collector.dart';
      final delayedFlushSource = logCollectorSource.replaceFirst(
        'await logSink.flush();',
        'await Future<void>.delayed(const Duration(milliseconds: 50));\n    await logSink.flush();',
      );
      await File(sourcePath).writeAsString(delayedFlushSource);

      final allowClose = Completer<void>();

      final server = await _startServer((socket) async {
        var listenRequests = 0;

        await for (final data in socket) {
          final request = jsonDecode(data as String) as Map<String, dynamic>;
          if (request['method'] != 'streamListen') {
            continue;
          }

          listenRequests++;
          if (listenRequests != 3) {
            continue;
          }

          socket.add(jsonEncode(_writeEvent('last line\n')));
          await allowClose.future;
          await socket.close();
        }
      });
      addTearDown(() async => server.close(force: true));

      final process = await Process.start('dart', [
        sourcePath,
        _wsUri(server),
        logPath,
        pidPath,
      ]);
      addTearDown(() async {
        process.kill();
        await process.exitCode;
      });

      expect(await _waitForLogLines(logPath, 1), ['last line']);
      allowClose.complete();
    });
  });
}

const _followLogsScript = '''
import 'dart:io';

import 'package:fdb/commands/logs.dart';
import 'package:fdb/constants.dart';

Future<void> main(List<String> args) async {
  initSessionDir(args[0]);
  exit(await runLogs(['--follow']));
}
''';

Future<HttpServer> _startServer(Future<void> Function(WebSocket socket) onSocket) {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.transform(WebSocketTransformer()).listen((socket) {
      unawaited(onSocket(socket));
    });
    return server;
  });
}

Map<String, dynamic> _loggingEvent(String loggerName, String message) {
  return {
    'method': 'streamNotify',
    'params': {
      'event': {
        'kind': 'Logging',
        'logRecord': {
          'message': {'valueAsString': message},
          'loggerName': {'valueAsString': loggerName},
        },
      },
    },
  };
}

Map<String, dynamic> _writeEvent(String text) {
  return {
    'method': 'streamNotify',
    'params': {
      'event': {
        'kind': 'WriteEvent',
        'bytes': base64Encode(utf8.encode(text)),
      },
    },
  };
}

String _wsUri(HttpServer server) => 'ws://${server.address.host}:${server.port}';

String _packageConfigPath() => '${Directory.current.path}/.dart_tool/package_config.json';

Future<void> _waitForFile(String path) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));

  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for file $path');
}

Future<List<String>> _waitForProcessLines(Stream<List<int>> stream, int expectedCount) async {
  final lines = <String>[];
  final completer = Completer<void>();
  late final StreamSubscription<String> subscription;

  subscription = stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    lines.add(line);
    if (lines.length >= expectedCount && !completer.isCompleted) {
      completer.complete();
    }
  });

  try {
    await completer.future.timeout(const Duration(seconds: 5));
    return lines.take(expectedCount).toList();
  } finally {
    await subscription.cancel();
  }
}

Future<List<String>> _waitForLogLines(String logPath, int expectedCount) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));

  while (DateTime.now().isBefore(deadline)) {
    final logFile = File(logPath);
    if (logFile.existsSync()) {
      final lines = await logFile.readAsLines();
      if (lines.length >= expectedCount) {
        return lines;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for $expectedCount log lines in $logPath');
}
