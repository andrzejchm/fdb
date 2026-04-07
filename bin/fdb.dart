import 'dart:io';

import 'package:fdb/commands/back.dart';
import 'package:fdb/commands/deeplink.dart';
import 'package:fdb/commands/describe.dart';
import 'package:fdb/commands/devices.dart';
import 'package:fdb/commands/input.dart';
import 'package:fdb/commands/kill.dart';
import 'package:fdb/commands/launch.dart';
import 'package:fdb/commands/longpress.dart';
import 'package:fdb/commands/logs.dart';
import 'package:fdb/commands/reload.dart';
import 'package:fdb/commands/restart.dart';
import 'package:fdb/commands/screenshot.dart';
import 'package:fdb/commands/scroll.dart';
import 'package:fdb/commands/select.dart';
import 'package:fdb/commands/selected.dart';
import 'package:fdb/commands/skill.dart';
import 'package:fdb/commands/status.dart';
import 'package:fdb/commands/swipe.dart';
import 'package:fdb/commands/tap.dart';
import 'package:fdb/commands/tree.dart';
import 'package:fdb/constants.dart';

const usage = '''
Usage: fdb <command> [args]

Commands:
  devices     List connected devices
  deeplink    Open a deep link URL on the device
  launch      Launch a Flutter app
  reload      Hot reload the running app
  restart     Hot restart the running app
  screenshot  Take a device screenshot
  logs        Get filtered app logs
  tree        Get the widget tree
  describe    Describe the current screen (interactive elements + text)
  tap         Tap a widget by selector or @N ref from describe
  longpress   Long-press a widget by selector
  input       Enter text into a field
  scroll      Scroll in a direction
  swipe       Swipe a widget or screen (PageView, Dismissible)
  back        Navigate back (Navigator.maybePop)
  select      Toggle widget selection mode
  selected    Get the currently selected widget
  status      Check if the app is running
  kill        Stop the running app
  skill       Print the AI agent skill file (SKILL.md)

Options:
  --version   Print the fdb version
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(usage);
    exit(1);
  }

  if (args[0] == '--help' || args[0] == '-h') {
    stdout.write(usage);
    exit(0);
  }

  final command = args[0];

  if (command == '--version' || command == '-v') {
    stdout.writeln('fdb $version');
    exit(0);
  }

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
    case 'describe':
      return runDescribe(args);
    case 'tap':
      return runTap(args);
    case 'longpress':
      return runLongpress(args);
    case 'input':
      return runInput(args);
    case 'scroll':
      return runScroll(args);
    case 'swipe':
      return runSwipe(args);
    case 'back':
      return runBack(args);
    case 'select':
      return runSelect(args);
    case 'selected':
      return runSelected(args);
    case 'status':
      return runStatus(args);
    case 'kill':
      return runKill(args);
    case 'skill':
      return runSkill(args);
    default:
      stderr.writeln('ERROR: Unknown command: $command');
      stderr.writeln(usage);
      return Future.value(1);
  }
}
