import 'dart:io';

import 'package:fdb/app_died_exception.dart';
import 'package:fdb/commands/back.dart';
import 'package:fdb/commands/clean.dart';
import 'package:fdb/commands/shared_prefs.dart';
import 'package:fdb/commands/deeplink.dart';
import 'package:fdb/commands/describe.dart';
import 'package:fdb/commands/devices.dart';
import 'package:fdb/commands/doctor.dart';
import 'package:fdb/commands/double_tap.dart';
import 'package:fdb/commands/input.dart';
import 'package:fdb/commands/kill.dart';
import 'package:fdb/commands/launch.dart';
import 'package:fdb/commands/native_tap.dart';
import 'package:fdb/commands/longpress.dart';
import 'package:fdb/commands/logs.dart';
import 'package:fdb/commands/reload.dart';
import 'package:fdb/commands/restart.dart';
import 'package:fdb/commands/screenshot.dart';
import 'package:fdb/commands/scroll.dart';
import 'package:fdb/commands/scroll_to.dart';
import 'package:fdb/commands/select.dart';
import 'package:fdb/commands/selected.dart';
import 'package:fdb/commands/skill.dart';
import 'package:fdb/commands/status.dart';
import 'package:fdb/commands/swipe.dart';
import 'package:fdb/commands/syslog.dart';
import 'package:fdb/commands/tap.dart';
import 'package:fdb/commands/tree.dart';
import 'package:fdb/commands/wait.dart';
import 'package:fdb/constants.dart';

const usage = '''
Usage: fdb [--session-dir <path>] <command> [args]

Commands:
  devices     List connected devices
  deeplink    Open a deep link URL on the device
  launch      Launch a Flutter app
               --device <id>       (required) target device/simulator ID
               --project <path>    Flutter project root (default: CWD)
               --flavor <name>     Build flavor
               --target <file>     Entry-point file (default: lib/main.dart)
               --flutter-sdk <path> Path to Flutter SDK root
               --verbose           Pass --verbose to flutter run; full output
                                   is captured in .fdb/logs.txt
  reload      Hot reload the running app
  restart     Hot restart the running app
  screenshot  Take a device screenshot
  logs        Get filtered app logs
  syslog      Read native system logs (Android logcat, iOS syslog, macOS log)
  tree        Get the widget tree
  describe    Describe the current screen (interactive elements + text)
  doctor      Check app, VM service, fdb_helper, platform tools, and device state
  native-tap  Tap native (non-Flutter) UI at coordinates via platform tools
  tap         Tap a widget by selector, coordinates, or @N ref from describe
  longpress   Long-press a widget by selector or coordinates
  double-tap  Double-tap a widget by selector or coordinates
  input       Enter text into a field
  scroll      Scroll in a direction
  scroll-to   Scroll until a widget is visible
  wait        Wait until a widget or route changes state
  swipe       Swipe a widget or screen (PageView, Dismissible)
  back        Navigate back (Navigator.maybePop)
  clean       Clear app cache and data directories (requires fdb_helper)
  shared-prefs get|get-all|set|remove|clear SharedPreferences (requires fdb_helper)
  select      Toggle widget selection mode
  selected    Get the currently selected widget
  status      Check if the app is running
  kill        Stop the running app
  skill       Print the AI agent skill file (SKILL.md)

Global options:
  --session-dir <path>  Use this .fdb/ session directory instead of auto-resolving
  --version             Print the fdb version
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

  // Strip global flags before the command word.
  var remaining = args.toList();
  String? explicitSessionDir;

  while (remaining.isNotEmpty && remaining[0].startsWith('-')) {
    if (remaining[0] == '--session-dir' && remaining.length > 1) {
      explicitSessionDir = remaining[1];
      remaining = remaining.sublist(2);
    } else if (remaining[0] == '--version' || remaining[0] == '-v') {
      stdout.writeln('fdb $version');
      exit(0);
    } else {
      // Unknown global flag — leave it for the command to handle or reject.
      break;
    }
  }

  if (remaining.isEmpty) {
    stderr.writeln(usage);
    exit(1);
  }

  final command = remaining[0];

  final commandArgs = remaining.sublist(1);

  // Resolve session directory.
  // `launch` manages its own session dir via --project; skip auto-resolution.
  // All other commands benefit from walking up to find an active .fdb/.
  if (command != 'launch' && command != 'devices' && command != 'skill') {
    if (explicitSessionDir != null) {
      initSessionDirFromPath(explicitSessionDir);
    } else {
      final resolved = resolveSessionDir();
      if (command != 'status' && resolved == null) {
        stderr.writeln(
          'ERROR: No .fdb/ session found. Run from the project root or pass --session-dir <path>.',
        );
        exit(1);
      }
    }
  }

  try {
    final exitCode = await _runCommand(command, commandArgs);
    exit(exitCode);
  } on AppDiedException catch (e) {
    _formatAppDied(e);
    exit(1);
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
    case 'syslog':
      return runSyslog(args);
    case 'tree':
      return runTree(args);
    case 'describe':
      return runDescribe(args);
    case 'doctor':
      return runDoctor(args);
    case 'native-tap':
      return runNativeTap(args);
    case 'tap':
      return runTap(args);
    case 'double-tap':
      return runDoubleTap(args);
    case 'longpress':
      return runLongpress(args);
    case 'input':
      return runInput(args);
    case 'scroll':
      return runScroll(args);
    case 'scroll-to':
      return runScrollTo(args);
    case 'wait':
      return runWait(args);
    case 'swipe':
      return runSwipe(args);
    case 'back':
      return runBack(args);
    case 'clean':
      return runClean(args);
    case 'shared-prefs':
      return runSharedPrefs(args);
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

/// Formats an [AppDiedException] to stderr in the standard fdb error style:
///
/// ```
/// ERROR: APP_DIED REASON=jetsam_highwater
/// Last 20 log lines:
///   <line>
///   ...
/// See: fdb crash-report
/// ```
void _formatAppDied(AppDiedException e) {
  final reasonSuffix = e.reason != null ? ' REASON=${e.reason}' : '';
  stderr.writeln('ERROR: APP_DIED$reasonSuffix');

  if (e.logLines.isNotEmpty) {
    stderr.writeln('Last ${e.logLines.length} log lines:');
    for (final line in e.logLines) {
      stderr.writeln('  $line');
    }
  }

  stderr.writeln('See: fdb crash-report');
}
