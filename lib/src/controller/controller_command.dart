import 'package:fdb/src/controller/commands/requests.dart';
import 'package:fdb/src/controller/controller_request.dart';

typedef ControllerRequestReader = ControllerRequest Function(Map<String, Object?> json);

enum ControllerCommand {
  status('status', StatusCommandRequest.fromJson),
  reload('reload', ReloadCommandRequest.fromJson),
  restart('restart', RestartCommandRequest.fromJson),
  kill('kill', KillCommandRequest.fromJson),
  checkFdbHelper('checkFdbHelper', CheckFdbHelperCommandRequest.fromJson),
  findAllIsolateIds('findAllIsolateIds', FindAllIsolateIdsCommandRequest.fromJson),
  findFlutterIsolateId('findFlutterIsolateId', FindFlutterIsolateIdCommandRequest.fromJson),
  fdbBack('fdbBack', FdbBackCommandRequest.fromJson),
  fdbClean('fdbClean', FdbCleanCommandRequest.fromJson),
  fdbDescribe('fdbDescribe', FdbDescribeCommandRequest.fromJson),
  fdbDoubleTap('fdbDoubleTap', FdbDoubleTapCommandRequest.fromJson),
  fdbEnterText('fdbEnterText', FdbEnterTextCommandRequest.fromJson),
  fdbLongPress('fdbLongPress', FdbLongPressCommandRequest.fromJson),
  fdbScroll('fdbScroll', FdbScrollCommandRequest.fromJson),
  fdbScrollTo('fdbScrollTo', FdbScrollToCommandRequest.fromJson),
  fdbSwipe('fdbSwipe', FdbSwipeCommandRequest.fromJson),
  fdbSwipePath('fdbSwipePath', FdbSwipePathCommandRequest.fromJson),
  fdbTap('fdbTap', FdbTapCommandRequest.fromJson),
  fdbWaitFor('fdbWaitFor', FdbWaitForCommandRequest.fromJson),
  fdbElements('fdbElements', FdbElementsCommandRequest.fromJson),
  fdbScreenshot('fdbScreenshot', FdbScreenshotCommandRequest.fromJson),
  fdbSharedPrefs('fdbSharedPrefs', FdbSharedPrefsCommandRequest.fromJson),
  flutterInspectorRootWidgetSummaryTree(
    'flutterInspectorRootWidgetSummaryTree',
    FlutterInspectorRootWidgetSummaryTreeCommandRequest.fromJson,
  ),
  flutterInspectorSelectedSummaryWidget(
    'flutterInspectorSelectedSummaryWidget',
    FlutterInspectorSelectedSummaryWidgetCommandRequest.fromJson,
  ),
  flutterInspectorShow(
    'flutterInspectorShow',
    FlutterInspectorShowCommandRequest.fromJson,
  ),
  flutterInspectorWidgetTreeReady(
    'flutterInspectorWidgetTreeReady',
    FlutterInspectorTreeReadyCommandRequest.fromJson,
  ),
  getIsolate('getIsolate', GetIsolateCommandRequest.fromJson),
  getMemoryUsage('getMemoryUsage', GetMemoryUsageCommandRequest.fromJson),
  getAllocationProfile('getAllocationProfile', GetAllocationProfileCommandRequest.fromJson),
  extCall('extCall', ExtCallCommandRequest.fromJson);

  const ControllerCommand(this.wireName, this.readRequest);

  final String wireName;
  final ControllerRequestReader readRequest;

  static ControllerCommand? fromWireName(String? value) {
    for (final command in values) {
      if (command.wireName == value) return command;
    }
    return null;
  }
}
