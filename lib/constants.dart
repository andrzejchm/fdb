import 'dart:io';

import 'package:fdb/src/controller/session.dart' as controller;

/// fdb version — update this AND pubspec.yaml on every release.
const version = '1.9.0';

const sessionDirName = controller.sessionDirName;

void initSessionDir(String projectPath) => controller.initSessionDir(projectPath);

void initSessionDirFromPath(String sessionDirPath) => controller.initSessionDirFromPath(sessionDirPath);

String? resolveSessionDir({Directory? start}) => controller.resolveSessionDir(start: start);

String ensureSessionDir() => controller.ensureSessionDir();

String get sessionDirPath => controller.sessionDirPath;

String get pidFile => controller.pidFile;
String get appPidFile => controller.appPidFile;
String get controllerPidFile => controller.controllerPidFile;
String get controllerPortFile => controller.controllerPortFile;
String get controllerTokenFile => controller.controllerTokenFile;
String get logFile => controller.logFile;
String get logCollectorPidFile => controller.logCollectorPidFile;
String get logCollectorScript => controller.logCollectorScript;
String get vmUriFile => controller.vmUriFile;
String get launcherScript => controller.launcherScript;
String get deviceFile => controller.deviceFile;
String get platformFile => controller.platformFile;
String get appIdFile => controller.appIdFile;
String get defaultScreenshotPath => controller.defaultScreenshotPath;

const launchTimeoutSeconds = 300; // 5 minutes
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;
