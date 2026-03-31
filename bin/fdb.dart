import 'dart:io';

import 'package:fdb/commands/deeplink.dart';
import 'package:fdb/commands/devices.dart';
import 'package:fdb/commands/input.dart';
import 'package:fdb/commands/kill.dart';
import 'package:fdb/commands/launch.dart';
import 'package:fdb/commands/logs.dart';
import 'package:fdb/commands/reload.dart';
import 'package:fdb/commands/restart.dart';
import 'package:fdb/commands/screenshot.dart';
import 'package:fdb/commands/scroll.dart';
import 'package:fdb/commands/select.dart';
import 'package:fdb/commands/selected.dart';
import 'package:fdb/commands/status.dart';
import 'package:fdb/commands/tap.dart';
import 'package:fdb/commands/tree.dart';

const usage = '''
Usage: fdb <command> [options]

Commands:
  devices      List connected Flutter devices
  launch       Launch a Flutter app (--device, --project required)
  kill         Stop a running app
  status       Check if app is running
  reload       Hot reload
  restart      Hot restart
  logs         View app logs (--last N, --follow, --tag TAG)
  screenshot   Take a screenshot (--output PATH)
  tree         Dump widget tree
  tap          Tap a widget (--text, --key, --type, --x/--y)
  input        Enter text into a focused field
  scroll       Scroll/swipe gesture
  select       Toggle widget selection mode
  selected     Get info about selected widget
  deeplink     Open a deep link in the app

Global options:
  --device ID  Target a specific device session (auto-detected if only one)

Session state is stored in ~/.fdb/sessions/<device-hash>/
Device cache is stored in ~/.fdb/devices.json
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
    case 'deeplink':
      return runDeeplink(args);
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
    case 'tap':
      return runTap(args);
    case 'input':
      return runInput(args);
    case 'scroll':
      return runScroll(args);
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
