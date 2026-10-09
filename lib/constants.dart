import 'dart:io';

import 'package:fdb/src/controller/session.dart' as controller;

/// fdb version — update this AND pubspec.yaml on every release.
const version = '1.13.1';

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
String get projectPathFile => controller.projectPathFile;
String get defaultScreenshotPath => controller.defaultScreenshotPath;

/// Default `fdb launch --timeout`. First debug builds of large apps (CocoaPods,
/// Gradle, Xcode from a cold cache) routinely take longer than 5 minutes, and
/// the wait already ends early when the build fails, so a longer ceiling only
/// costs time when a build is genuinely still running.
const launchTimeoutSeconds = 600; // 10 minutes

/// Default `fdb attach --timeout`. Attach does not build, so it keeps the
/// previous 5 minute ceiling.
const attachTimeoutSeconds = 300; // 5 minutes
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;
