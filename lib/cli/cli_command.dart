import 'package:fdb/cli/adapters/adapters.g.dart';

typedef CliRunner = Future<int> Function(List<String> args);

enum CliCommand {
  attach('attach', null),
  devices('devices', runDevicesCli),
  deeplink('deeplink', runDeeplinkCli),
  launch('launch', null),
  reload('reload', runReloadCli),
  restart('restart', runRestartCli),
  screenshot('screenshot', runScreenshotCli),
  logs('logs', runLogsCli),
  syslog('syslog', runSyslogCli),
  crashReport('crash-report', runCrashReportCli),
  tree('tree', runTreeCli),
  describe('describe', runDescribeCli),
  doctor('doctor', runDoctorCli),
  nativeTap('native-tap', runNativeTapCli),
  tap('tap', runTapCli),
  doubleTap('double-tap', runDoubleTapCli),
  longpress('longpress', runLongpressCli),
  input('input', runInputCli),
  scroll('scroll', runScrollCli),
  scrollTo('scroll-to', runScrollToCli),
  wait('wait', runWaitCli),
  swipe('swipe', runSwipeCli),
  swipePath('swipe-path', runSwipePathCli),
  back('back', runBackCli),
  clean('clean', runCleanCli),
  sharedPrefs('shared-prefs', runSharedPrefsCli),
  ext('ext', runExtCli),
  select('select', runSelectCli),
  selected('selected', runSelectedCli),
  status('status', runStatusCli),
  kill('kill', runKillCli),
  mem('mem', runMemCli),
  gc('gc', runGcCli),
  grantPermission('grant-permission', runGrantPermissionCli),
  heap('heap', runHeapCli),
  simulator('simulator', runSimulatorCli),
  skill('skill', runSkillCli);

  const CliCommand(this.wireName, this.runner);

  final String wireName;
  final CliRunner? runner;

  static CliCommand? fromWireName(String? value) {
    for (final command in values) {
      if (command.wireName == value) return command;
    }
    return null;
  }
}
