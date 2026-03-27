import 'dart:io';

import 'package:fdb/commands/devices.dart';
import 'package:fdb/commands/kill.dart';
import 'package:fdb/commands/launch.dart';
import 'package:fdb/commands/logs.dart';
import 'package:fdb/commands/reload.dart';
import 'package:fdb/commands/restart.dart';
import 'package:fdb/commands/screenshot.dart';
import 'package:fdb/commands/select.dart';
import 'package:fdb/commands/selected.dart';
import 'package:fdb/commands/status.dart';
import 'package:fdb/commands/tree.dart';

const usage = '''
Usage: fdb <command> [args]

Commands:
  devices     List connected devices
  launch      Launch a Flutter app
  reload      Hot reload the running app
  restart     Hot restart the running app
  screenshot  Take a device screenshot
  logs        Get filtered app logs
  tree        Get the widget tree
  select      Toggle widget selection mode
  selected    Get the currently selected widget
  status      Check if the app is running
  kill        Stop the running app
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(usage);
    exit(1);
  }

  final command = args[0];
  final commandArgs = args.sublist(1);

  try {
    final exitCode = await _runCommand(command, commandArgs);
    exit(exitCode);
  } catch (e) {
    stderr.writeln('ERROR: $e');
    exit(1);
  }
}

Future<int> _runCommand(String command, List<String> args) {
  switch (command) {
    case 'devices':
      return runDevices(args);
    case 'launch':
      return runLaunch(args);
    case 'reload':
      return runReload(args);
    case 'restart':
      return runRestart(args);
    case 'screenshot':
      return runScreenshot(args);
    case 'logs':
      return runLogs(args);
    case 'tree':
      return runTree(args);
    case 'select':
      return runSelect(args);
    case 'selected':
      return runSelected(args);
    case 'status':
      return runStatus(args);
    case 'kill':
      return runKill(args);
    default:
      stderr.writeln('ERROR: Unknown command: $command');
      stderr.writeln(usage);
      return Future.value(1);
  }
}
