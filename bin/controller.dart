import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fdb/constants.dart';
import 'package:fdb/core/process_utils.dart';

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  if (config == null) {
    stderr.writeln('Missing required controller arguments.');
    exitCode = 64;
    return;
  }

  final controller = _FdbController(config);
  await controller.run();
}

class _ControllerConfig {
  const _ControllerConfig({
    required this.sessionDir,
    required this.project,
    required this.device,
    required this.flutter,
    this.flavor,
    this.target,
    required this.verbose,
  });

  final String sessionDir;
  final String project;
  final String device;
  final String flutter;
  final String? flavor;
  final String? target;
  final bool verbose;
}

_ControllerConfig? _parseArgs(List<String> args) {
  String? sessionDir;
  String? project;
  String? device;
  String? flutter;
  String? flavor;
  String? target;
  var verbose = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--session-dir':
        sessionDir = args[++i];
      case '--project':
        project = args[++i];
      case '--device':
        device = args[++i];
      case '--flutter':
        flutter = args[++i];
      case '--flavor':
        flavor = args[++i];
      case '--target':
        target = args[++i];
      case '--verbose':
        verbose = true;
    }
  }

  if (sessionDir == null || project == null || device == null || flutter == null) {
    return null;
  }

  return _ControllerConfig(
    sessionDir: sessionDir,
    project: project,
    device: device,
    flutter: flutter,
    flavor: flavor,
    target: target,
    verbose: verbose,
  );
}

class _FdbController {
  _FdbController(this.config);

  final _ControllerConfig config;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _random = Random.secure();
  late final IOSink _logSink;
  late final ServerSocket _server;
  late final String _token;
  Process? _flutterProcess;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  String? _appId;
  String? _vmUri;
  bool _running = false;
  bool _stopRequested = false;
  int _nextId = 0;

  Future<void> run() async {
    initSessionDirFromPath(config.sessionDir);
    ensureSessionDir();

    _logSink = File(logFile).openWrite(mode: FileMode.append);
    _token = _generateToken();
    File(controllerPidFile).writeAsStringSync(pid.toString());
    File(controllerTokenFile).writeAsStringSync(_token);

    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    File(controllerPortFile).writeAsStringSync(_server.port.toString());
    unawaited(_acceptClients());

    final args = <String>[
      'run',
      '--machine',
      '-d',
      config.device,
      '--debug',
      '--pid-file',
      pidFile,
      if (config.flavor != null) ...['--flavor', config.flavor!],
      if (config.target != null) ...['--target', config.target!],
      if (config.verbose) '--verbose',
    ];

    _flutterProcess = await Process.start(
      config.flutter,
      args,
      workingDirectory: config.project,
    );

    _stdoutSub =
        _flutterProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_handleStdoutLine);
    _stderrSub = _flutterProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_appendLogLine);

    final exitCodeValue = await _flutterProcess!.exitCode;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    await _logSink.flush();
    await _logSink.close();
    await _server.close();
    _cleanupControllerFiles();
    if (_stopRequested && exitCodeValue == 0) {
      exit(0);
    }
    exit(exitCodeValue);
  }

  Future<void> _acceptClients() async {
    await for (final client in _server) {
      unawaited(_handleClient(client));
    }
  }

  Future<void> _handleClient(Socket client) async {
    try {
      final line =
          await utf8.decoder.bind(client).transform(const LineSplitter()).first.timeout(const Duration(seconds: 5));
      final request = jsonDecode(line) as Map<String, dynamic>;
      if (request['token'] != _token) {
        client.writeln(jsonEncode({'ok': false, 'error': 'Invalid token'}));
        return;
      }
      final command = request['command'] as String?;
      final params = (request['params'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final response = await _handleCommand(command ?? '', params);
      client.writeln(jsonEncode(response));
    } catch (e) {
      client.writeln(jsonEncode({'ok': false, 'error': e.toString()}));
    } finally {
      await client.flush();
      await client.close();
    }
  }

  Future<Map<String, dynamic>> _handleCommand(
    String command,
    Map<String, Object?> params,
  ) async {
    switch (command) {
      case 'status':
        return {
          'ok': true,
          'running': _running,
          'pid': readAppPid() ?? readPid(),
          'vmServiceUri': _vmUri ?? readVmUri(),
        };
      case 'reload':
        return _restart(fullRestart: false);
      case 'restart':
        return _restart(fullRestart: true);
      case 'kill':
        _stopRequested = true;
        final result = await _sendRequest('app.stop', {'appId': _requireAppId()});
        return {
          'ok': result['result'] == true,
          'result': result['result'],
        };
      case 'refresh_vm_uri':
        return {
          'ok': true,
          'vmServiceUri': _vmUri ?? readVmUri(),
        };
      default:
        return {'ok': false, 'error': 'Unknown command: $command'};
    }
  }

  Future<Map<String, dynamic>> _restart({required bool fullRestart}) async {
    final result = await _sendRequest('app.restart', {
      'appId': _requireAppId(),
      'fullRestart': fullRestart,
      'pause': false,
      'reason': 'fdb',
    });
    final payload = result['result'] as Map<String, dynamic>?;
    return {
      'ok': payload?['code'] == 0,
      'message': payload?['message'] as String? ?? '',
      'result': payload,
    };
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    final process = _flutterProcess;
    if (process == null) {
      return {'ok': false, 'error': 'Flutter process is not running.'};
    }

    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(
      jsonEncode([
        {
          'id': id,
          'method': method,
          'params': params,
        },
      ]),
    );

    final response = await completer.future.timeout(const Duration(seconds: 30));
    final error = response['error'];
    if (error != null) {
      return {'ok': false, 'error': error.toString()};
    }
    return response;
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('[')) {
      _appendLogLine(line);
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      _appendLogLine(line);
      return;
    }
    if (decoded is! List) {
      _appendLogLine(line);
      return;
    }

    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;

      final event = entry['event'] as String?;
      if (event != null) {
        final params = entry['params'] as Map<String, dynamic>? ?? const {};
        switch (event) {
          case 'app.start':
            _appId = params['appId'] as String?;
            _running = true;
          case 'app.debugPort':
            final wsUri = params['wsUri'] as String?;
            if (wsUri != null && wsUri.isNotEmpty) {
              _vmUri = wsUri;
              File(vmUriFile).writeAsStringSync(wsUri);
              unawaited(_writeAppPidFromVm(wsUri));
            }
          case 'app.stop':
            _running = false;
          case 'app.log':
            final log = params['log'] as String?;
            if (log != null && log.isNotEmpty) {
              _appendLogLine(log);
            }
          case 'app.progress':
            final message = params['message'] as String?;
            if (message != null && message.isNotEmpty) {
              _appendLogLine(message);
            }
        }
      }

      final id = entry['id'];
      if (id is! int) continue;
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(entry);
      }
    }
  }

  Future<void> _writeAppPidFromVm(String wsUri) async {
    try {
      final socket = await WebSocket.connect(
        wsUri,
        customClient: HttpClient()..maxConnectionsPerHost = 1,
      );
      final requestId = 'getvm_${DateTime.now().microsecondsSinceEpoch}';
      final completer = Completer<int?>();
      late final StreamSubscription sub;
      sub = socket.listen((data) {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        if (message['id'] != requestId) return;
        final result = message['result'] as Map<String, dynamic>?;
        completer.complete(result?['pid'] as int?);
      });
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'getVM',
          'params': const {},
        }),
      );
      final appPid = await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      await socket.close();
      if (appPid != null) {
        File(appPidFile).writeAsStringSync(appPid.toString());
      }
    } catch (_) {}
  }

  void _appendLogLine(String line) {
    _logSink.writeln(line);
  }

  void _cleanupControllerFiles() {
    for (final path in [controllerPidFile, controllerPortFile, controllerTokenFile]) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  String _requireAppId() {
    final appId = _appId;
    if (appId == null || appId.isEmpty) {
      throw StateError('Flutter app is not attached yet.');
    }
    return appId;
  }

  String _generateToken() {
    final values = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(values);
  }
}
