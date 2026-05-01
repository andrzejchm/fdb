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
import 'package:fdb/core/app_died_exception.dart';

Future<int> runFdbCommand(String command, List<String> args) {
  switch (command) {
    case 'devices':
      return runDevicesCli(args);
    case 'deeplink':
      return runDeeplinkCli(args);
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
      return Future.value(1);
  }
}

void formatAppDied(AppDiedException e) {
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
