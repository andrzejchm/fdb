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
    required this.mode,
    required this.sessionDir,
    required this.project,
    required this.device,
    required this.flutter,
    this.flavor,
    this.target,
    this.appId,
    this.debugUrl,
    required this.verbose,
    this.dartDefines = const [],
    this.dartDefineFromFiles = const [],
  });

  final _ControllerMode mode;
  final String sessionDir;
  final String project;
  final String device;
  final String flutter;
  final String? flavor;
  final String? target;
  final String? appId;
  final String? debugUrl;
  final bool verbose;
  final List<String> dartDefines;
  final List<String> dartDefineFromFiles;
}

enum _ControllerMode { run, attach }

ArgParser buildControllerArgParser() => ArgParser()
  ..addOption('mode', allowed: ['run', 'attach'], defaultsTo: 'run')
  ..addOption('session-dir')
  ..addOption('project')
  ..addOption('device')
  ..addOption('flutter')
  ..addOption('flavor')
  ..addOption('target')
  ..addOption('app-id')
  ..addOption('debug-url')
  ..addMultiOption('dart-define', splitCommas: false)
  ..addMultiOption('dart-define-from-file', splitCommas: false)
  ..addFlag('verbose', negatable: false);

_ControllerConfig? _parseArgs(List<String> args) {
  final parser = buildControllerArgParser();

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

  final modeName = results.option('mode') ?? 'run';

  return _ControllerConfig(
    mode: modeName == 'attach' ? _ControllerMode.attach : _ControllerMode.run,
    sessionDir: sessionDir,
    project: project,
    device: device,
    flutter: flutter,
    flavor: results.option('flavor'),
    target: results.option('target'),
    appId: results.option('app-id'),
    debugUrl: results.option('debug-url'),
    verbose: results.flag('verbose'),
    dartDefines: results.multiOption('dart-define'),
    dartDefineFromFiles: results.multiOption('dart-define-from-file'),
  );
}

List<String> buildFlutterRunArgs({
  required String device,
  String? flavor,
  String? target,
  required List<String> dartDefines,
  required List<String> dartDefineFromFiles,
  required bool verbose,
}) =>
    <String>[
      'run',
      '--machine',
      '-d',
      device,
      '--debug',
      '--pid-file',
      pidFile,
      if (flavor != null) ...['--flavor', flavor],
      if (target != null) ...['--target', target],
      for (final define in dartDefines) '--dart-define=$define',
      for (final file in dartDefineFromFiles) '--dart-define-from-file=$file',
      if (verbose) '--verbose',
    ];

List<String> buildFlutterAttachArgs({
  required String device,
  String? target,
  String? appId,
  String? debugUrl,
  required bool verbose,
}) =>
    <String>[
      'attach',
      '--machine',
      '-d',
      device,
      '--pid-file',
      pidFile,
      if (target != null) ...['--target', target],
      if (appId != null) ...['--app-id', appId],
      if (debugUrl != null) ...['--debug-url', debugUrl],
      if (verbose) '--verbose',
    ];

/// Writes the app PID file and only then the VM URI file for one
/// `app.debugPort` event.
///
/// `fdb launch` and `fdb attach` treat the VM URI file as the "app is ready"
/// signal and read the PID right after it appears, so the PID file has to
/// exist by then. [lookupAppPid] returns the app PID, or null when it is
/// unknown; a PID of 0 or less (DWDS on web reports -1) also counts as
/// unknown and is not written.
///
/// [isCurrent] is checked after the lookup: when a newer `app.debugPort`
/// event arrived in the meantime, nothing is written, so a slow lookup cannot
/// overwrite the newer URI and PID. Never throws (it runs unawaited); errors
/// go to [onError].
Future<void> publishDebugPort(
  String wsUri, {
  required Future<int?> Function() lookupAppPid,
  required bool Function() isCurrent,
  void Function(Object error) onError = _ignoreError,
}) async {
  int? pid;
  try {
    pid = await lookupAppPid();
  } catch (e) {
    onError(e);
  }
  if (!isCurrent()) return;

  try {
    if (pid != null && pid > 0) {
      File(appPidFile).writeAsStringSync(pid.toString());
    }
  } catch (e) {
    onError(e);
  }

  try {
    File(vmUriFile).writeAsStringSync(wsUri);
  } catch (e) {
    onError(e);
  }
}

void _ignoreError(Object _) {}

/// How long `fdb launch` / `fdb attach` wait for a replaced controller to exit
/// after SIGTERM before sending SIGKILL (a SIGKILL'd controller orphans its
/// flutter tool again).
///
/// The controller needs at most about 6 s to stop the flutter tool
/// ([stopFlutterProcess]: 3 s after SIGTERM, 3 s after SIGKILL) and up to 6 s
/// more for a log collector that ignores SIGTERM. `fdb kill`'s 10 s fallback
/// is enough: it stops the log collector itself before signalling the
/// controller, so only the flutter tool's ~6 s remain. This value adds margin
/// on top of the 12 s worst case.
const controllerShutdownTimeout = Duration(seconds: 15);

/// Stops the flutter tool [process] (`flutter run` / `flutter attach`) before
/// the controller exits: SIGTERM, then SIGKILL if it is still alive after
/// [exitTimeout].
///
/// This only detaches: on mobile targets the app keeps running (verified on
/// the iOS simulator); desktop and web are not verified. Stopping the app is
/// the job of
/// the `kill` controller command (`app.stop`), which `fdb kill` and
/// `fdb launch` send before signalling the controller. Never throws.
Future<void> stopFlutterProcess(
  Process process, {
  Duration exitTimeout = const Duration(seconds: 3),
}) async {
  var exited = false;
  final exitFuture = process.exitCode.then((_) => exited = true);

  Future<void> waitForExit(Duration timeout) async {
    if (exited) return;
    try {
      await exitFuture.timeout(timeout);
    } on TimeoutException {
      // Still running; the caller escalates.
    }
  }

  // Lets an already completed exitCode mark the process as exited, so a
  // process that is already gone gets no signal.
  await waitForExit(Duration.zero);
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigkill]) {
    if (exited) return;
    process.kill(signal);
    await waitForExit(exitTimeout);
  }
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
  bool _flutterExited = false;
  Future<void>? _signalShutdown;
  Future<void>? _finishing;
  int _nextId = 0;
  int _debugPortGeneration = 0;

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

    final args = switch (config.mode) {
      _ControllerMode.run => buildFlutterRunArgs(
          device: config.device,
          flavor: config.flavor,
          target: config.target,
          dartDefines: config.dartDefines,
          dartDefineFromFiles: config.dartDefineFromFiles,
          verbose: config.verbose,
        ),
      _ControllerMode.attach => buildFlutterAttachArgs(
          device: config.device,
          target: config.target,
          appId: config.appId,
          debugUrl: config.debugUrl,
          verbose: config.verbose,
        ),
    };

    _flutterProcess = await Process.start(
      config.flutter,
      args,
      workingDirectory: config.project,
    );

    _stdoutSub = _flutterProcess!.stdout
        .transform(tolerantUtf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);
    _stderrSub =
        _flutterProcess!.stderr.transform(tolerantUtf8.decoder).transform(const LineSplitter()).listen(_appendLogLine);

    // A SIGTERM (e.g. from `fdb launch` replacing this session) or SIGINT
    // would otherwise kill the controller and leave the flutter tool and the
    // log collector running with nobody owning them.
    ProcessSignal.sigint.watch().listen((_) => _shutdownOnSignal(130));
    // ProcessSignal.sigterm.watch() is not supported on Windows.
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => _shutdownOnSignal(143));
    }

    final exitCodeValue = await _flutterProcess!.exitCode;
    _flutterExited = true;
    final signalShutdown = _signalShutdown;
    if (signalShutdown != null) {
      // The signal handler is stopping things and exits on its own.
      await signalShutdown;
      return;
    }
    await _finish(_stopRequested && exitCodeValue == 0 ? 0 : exitCodeValue);
  }

  /// Stops the flutter tool child, then cleans up and exits with [code].
  /// Runs at most once.
  Future<void> _shutdownOnSignal(int code) {
    return _signalShutdown ??= () async {
      final process = _flutterProcess;
      if (process != null && !_flutterExited) {
        await stopFlutterProcess(process);
      }
      await _finish(code);
    }();
  }

  /// Cleans up and exits with [code]. Runs at most once: `fdb kill` can send
  /// SIGTERM while the controller is already finishing after flutter exited.
  Future<void> _finish(int code) => _finishing ??= _cleanupAndExit(code);

  Future<void> _cleanupAndExit(int code) async {
    await _logCollector.stop();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    await _logSink.flush();
    await _logSink.close();
    await _server.close();
    _cleanupControllerFiles();
    exit(code);
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
          unawaited(_logCollector.start(wsUri));
          final generation = ++_debugPortGeneration;
          unawaited(
            publishDebugPort(
              wsUri,
              lookupAppPid: () => getVmFromUri(wsUri, timeout: const Duration(seconds: 5)).then((vm) => vm?.pid),
              isCurrent: () => generation == _debugPortGeneration,
              onError: (e) => _appendLogLine('WARNING: Failed to resolve app PID from VM service: $e'),
            ),
          );
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
