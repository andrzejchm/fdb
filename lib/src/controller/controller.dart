import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_transport.dart';
import 'package:fdb/src/controller/log_collector_manager.dart';
import 'package:fdb/src/controller/vm_service/vm_service.dart';
import 'package:fdb/src/controller/process_utils.dart';

Future<void> runController(List<String> args) async {
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
  final parser = ArgParser()
    ..addOption('session-dir')
    ..addOption('project')
    ..addOption('device')
    ..addOption('flutter')
    ..addOption('flavor')
    ..addOption('target')
    ..addFlag('verbose', negatable: false);

  late final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return null;
  }

  final sessionDir = results.option('session-dir');
  final project = results.option('project');
  final device = results.option('device');
  final flutter = results.option('flutter');
  if (sessionDir == null || project == null || device == null || flutter == null) {
    return null;
  }

  return _ControllerConfig(
    sessionDir: sessionDir,
    project: project,
    device: device,
    flutter: flutter,
    flavor: results.option('flavor'),
    target: results.option('target'),
    verbose: results.flag('verbose'),
  );
}

class _FdbController implements ControllerContext {
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
  late final LogCollectorManager _logCollector;
  bool _running = false;
  bool _stopRequested = false;
  int _nextId = 0;

  @override
  bool get running => _running;

  @override
  String? get vmServiceUri => _vmUri ?? readVmUri();

  Future<void> run() async {
    initSessionDirFromPath(config.sessionDir);
    ensureSessionDir();

    _logSink = File(logFile).openWrite(mode: FileMode.append);
    _logCollector = LogCollectorManager(logWarning: _appendLogLine);
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
      final request = await readControllerRequest(client);
      if (request.token != _token) {
        await writeControllerResponse(
          client,
          ControllerResponse.failure('Invalid token'),
        );
        return;
      }
      final response = await _handleCommand(request);
      await writeControllerResponse(client, response);
    } catch (e) {
      await writeControllerResponse(
        client,
        ControllerResponse.failure(e.toString()),
      );
    } finally {
      await client.close();
    }
  }

  Future<CommandResponse> _handleCommand(ControllerRequest request) async {
    return request.createRunner(this).execute(request);
  }

  @override
  void requestStop() {
    _stopRequested = true;
  }

  @override
  Future<Map<String, dynamic>> sendFlutterRequest(
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
        _handleEvent(event, params);
      }

      _resolvePendingResponse(entry);
    }
  }

  void _handleEvent(String event, Map<String, dynamic> params) {
    switch (event) {
      case 'app.start':
        _appId = params['appId'] as String?;
        _running = true;
      case 'app.debugPort':
        final wsUri = params['wsUri'] as String?;
        if (wsUri != null && wsUri.isNotEmpty) {
          _vmUri = wsUri;
          File(vmUriFile).writeAsStringSync(wsUri);
          unawaited(_logCollector.start(wsUri));
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

  void _resolvePendingResponse(Map<String, dynamic> entry) {
    final id = entry['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(entry);
    }
  }

  Future<void> _writeAppPidFromVm(String wsUri) async {
    try {
      final vm = await getVmFromUri(wsUri, timeout: const Duration(seconds: 5));
      if (vm?.pid != null) {
        File(appPidFile).writeAsStringSync(vm!.pid.toString());
      }
    } catch (e) {
      _appendLogLine('WARNING: Failed to resolve app PID from VM service: $e');
    }
  }

  void _appendLogLine(String line) {
    _logSink.writeln(line);
  }

  void _cleanupControllerFiles() {
    if (readControllerPid() != pid) {
      return;
    }

    for (final path in [controllerPidFile, controllerPortFile, controllerTokenFile]) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  @override
  String requireAppId() {
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
