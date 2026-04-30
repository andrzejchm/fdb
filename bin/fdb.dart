import 'dart:io';

import 'package:fdb/cli/adapters/back_cli.dart';
import 'package:fdb/cli/adapters/clean_cli.dart';
import 'package:fdb/cli/adapters/crash_report_cli.dart';
import 'package:fdb/cli/adapters/deeplink_cli.dart';
import 'package:fdb/cli/adapters/describe_cli.dart';
import 'package:fdb/cli/adapters/devices_cli.dart';
import 'package:fdb/cli/adapters/doctor_cli.dart';
import 'package:fdb/cli/adapters/double_tap_cli.dart';
import 'package:fdb/cli/adapters/ext_cli.dart';
import 'package:fdb/cli/adapters/gc_cli.dart';
import 'package:fdb/cli/adapters/input_cli.dart';
import 'package:fdb/cli/adapters/kill_cli.dart';
import 'package:fdb/cli/adapters/launch_cli.dart';
import 'package:fdb/cli/adapters/logs_cli.dart';
import 'package:fdb/cli/adapters/longpress_cli.dart';
import 'package:fdb/cli/adapters/mem_cli.dart';
import 'package:fdb/cli/adapters/native_tap_cli.dart';
import 'package:fdb/cli/adapters/reload_cli.dart';
import 'package:fdb/cli/adapters/restart_cli.dart';
import 'package:fdb/cli/adapters/screenshot_cli.dart';
import 'package:fdb/cli/adapters/scroll_cli.dart';
import 'package:fdb/cli/adapters/scroll_to_cli.dart';
import 'package:fdb/cli/adapters/select_cli.dart';
import 'package:fdb/cli/adapters/selected_cli.dart';
import 'package:fdb/cli/adapters/shared_prefs_cli.dart';
import 'package:fdb/cli/adapters/skill_cli.dart';
import 'package:fdb/cli/adapters/status_cli.dart';
import 'package:fdb/cli/adapters/swipe_cli.dart';
import 'package:fdb/cli/adapters/syslog_cli.dart';
import 'package:fdb/cli/adapters/tap_cli.dart';
import 'package:fdb/cli/adapters/tree_cli.dart';
import 'package:fdb/cli/adapters/wait_cli.dart';
import 'package:fdb/constants.dart';
import 'package:fdb/core/app_died_exception.dart';

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
  crash-report Fetch the most recent OS-level crash record for the app
               --app-id <id>       Bundle id / package name (auto from .fdb/app_id.txt)
               --last <duration>   Time window to search (default: 1h)
               --all               Return all crash records in the window
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
  ext         list|call VM service extensions registered by the running app
  select      Toggle widget selection mode
  selected    Get the currently selected widget
  mem         Inspect heap usage; subcommands: profile, diff
  gc          Force a full garbage collection across all isolates
               --json              Output KEY=value tokens (HEAP_BEFORE, HEAP_AFTER, HEAP_DELTA)
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
  // `--help` / `-h` is also session-agnostic — adapters print parser.usage
  // without needing a session.
  // All other commands benefit from walking up to find an active .fdb/.
  final wantsHelp = commandArgs.contains('--help') || commandArgs.contains('-h');
  // `fdb mem diff` is pure file I/O — no VM connection required.
  final isMemDiff = command == 'mem' && commandArgs.isNotEmpty && commandArgs[0] == 'diff';
  // Commands that manage their own session dir or must run even on unhealthy sessions.
  const sessionResolutionExempt = {'launch', 'devices', 'skill'};
  // Commands that run against a potentially dead/missing session (soft-fail on null).
  const sessionSoftFail = {'status', 'doctor', 'crash-report'};
  if (!sessionResolutionExempt.contains(command) && !wantsHelp && !isMemDiff) {
    if (explicitSessionDir != null) {
      initSessionDirFromPath(explicitSessionDir);
    } else {
      final resolved = resolveSessionDir();
      if (!sessionSoftFail.contains(command) && resolved == null) {
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
      return runDevicesCli(args);
    case 'deeplink':
      return runDeeplinkCli(args);
    case 'launch':
      return runLaunchCli(args);
    case 'reload':
      return runReloadCli(args);
    case 'restart':
      return runRestartCli(args);
    case 'screenshot':
      return runScreenshotCli(args);
    case 'logs':
      return runLogsCli(args);
    case 'syslog':
      return runSyslogCli(args);
    case 'crash-report':
      return runCrashReportCli(args);
    case 'tree':
      return runTreeCli(args);
    case 'describe':
      return runDescribeCli(args);
    case 'doctor':
      return runDoctorCli(args);
    case 'native-tap':
      return runNativeTapCli(args);
    case 'tap':
      return runTapCli(args);
    case 'double-tap':
      return runDoubleTapCli(args);
    case 'longpress':
      return runLongpressCli(args);
    case 'input':
      return runInputCli(args);
    case 'scroll':
      return runScrollCli(args);
    case 'scroll-to':
      return runScrollToCli(args);
    case 'wait':
      return runWaitCli(args);
    case 'swipe':
      return runSwipeCli(args);
    case 'back':
      return runBackCli(args);
    case 'clean':
      return runCleanCli(args);
    case 'shared-prefs':
      return runSharedPrefsCli(args);
    case 'ext':
      return runExtCli(args);
    case 'select':
      return runSelectCli(args);
    case 'selected':
      return runSelectedCli(args);
    case 'status':
      return runStatusCli(args);
    case 'kill':
      return runKillCli(args);
    case 'mem':
      return runMemCli(args);
    case 'gc':
      return runGcCli(args);
    case 'skill':
      return runSkillCli(args);
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
