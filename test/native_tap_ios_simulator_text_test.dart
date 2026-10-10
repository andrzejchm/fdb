import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_accessibility.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid_source.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_native_tap.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:test/test.dart';

// Fixtures are real `describe` output from an iPhone 17 Pro simulator
// (iOS 26.2) running example/test_app.
String _fixture(String name) => File('test/fixtures/native_tap/$name').readAsStringSync();

IosAxSnapshot _snapshot(String json) => switch (parseIosSimulatorAccessibility(json)) {
      IosAxParsed(:final snapshot) => snapshot,
      IosAxInvalid(:final reason) => throw StateError(reason),
    };

final _flutterApp = _fixture('ios_sim_flutter_app.json');
final _openInAlert = _fixture('ios_sim_springboard_alert.json');
final _notificationAlert = _fixture('ios_sim_notification_alert.json');
final _openInAlertLandscape = _fixture('ios_sim_springboard_alert_landscape.json');
final _locationAlertLandscape = _fixture('ios_sim_location_alert_landscape.json');
final _portraitAlertOverLandscape = _fixture('ios_sim_portrait_springboard_alert_over_landscape.json');

/// What the helper prints right after an app launches: a bare application
/// element with a zero frame.
const _notReady = '{"elements":[{"depth":0,"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},'
    '"label":"","pid":49478,"role":"AXApplication"}],"orientation":"portrait","screen":{"height":874,"width":402}}';

String _tree(List<String> elements, {double width = 402, double height = 874}) =>
    '{"orientation":"portrait","screen":{"width":$width,"height":$height},"elements":['
    '{"depth":0,"enabled":true,"frame":{"x":0,"y":0,"width":$width,"height":$height},'
    '"label":"App","pid":1,"role":"AXApplication"},'
    '${elements.join(',')}]}';

String _element(
  String label, {
  double x = 10,
  double y = 10,
  double width = 100,
  double height = 40,
  bool enabled = true,
  String? identifier,
  bool nullFrame = false,
}) =>
    '{"depth":1,"enabled":$enabled,"label":"$label","pid":1,"role":"AXButton"'
    '${identifier != null ? ',"identifier":"$identifier"' : ''},'
    '"frame":${nullFrame ? 'null' : '{"x":$x,"y":$y,"width":$width,"height":$height}'}}';

void main() {
  group('parseIosSimulatorAccessibility', () {
    test('reads the Flutter app tree', () {
      final s = _snapshot(_flutterApp);

      expect(s.orientation, 'portrait');
      expect((s.screenWidth, s.screenHeight), (402.0, 874.0));
      expect(s.elements.first.isApplication, isTrue);
      expect(s.elements.first.label, 'Test App');
      final fab = s.elements.last;
      expect(fab.label, 'Increment');
      expect(fab.role, 'AXButton');
      expect(fab.enabled, isTrue);
      expect(fab.depth, 1);
      expect((fab.frame!.centerX, fab.frame!.centerY), (358.0, 796.0));
    });

    test('reads a SpringBoard alert with identifiers and values absent', () {
      final s = _snapshot(_openInAlert);

      expect(s.elements.map((e) => e.label), [
        '', // the application label is a single space, trimmed
        'Open in “Test App”?',
        'Cancel',
        'Open',
      ]);
      expect(s.elements[2].identifier, isEmpty);
      expect(s.elements[2].value, isEmpty);
    });

    test('reads landscape trees in interface points', () {
      for (final json in [_openInAlertLandscape, _locationAlertLandscape, _portraitAlertOverLandscape]) {
        final s = _snapshot(json);
        expect(s.orientation, 'landscapeRight');
        expect((s.screenWidth, s.screenHeight), (874.0, 402.0));
      }
    });

    test('keeps identifiers and values', () {
      final s = _snapshot(
        '{"orientation":"portrait","screen":{"width":402,"height":874},"elements":[{"label":"Maps","role":"AXButton",'
        '"identifier":"Maps","value":"Widget","enabled":true,"pid":7,"depth":1,'
        '"frame":{"x":24.3,"y":88,"width":168.3,"height":191}}]}',
      );

      expect(s.elements.single.identifier, 'Maps');
      expect(s.elements.single.value, 'Widget');
      expect(s.elements.single.pid, 7);
    });

    test('a null frame stays null', () {
      final s = _snapshot(_tree([_element('Ghost', nullFrame: true)]));

      expect(s.elements.last.frame, isNull);
    });

    test('rejects output that is not the describe JSON', () {
      expect(parseIosSimulatorAccessibility('not json'), isA<IosAxInvalid>());
      expect(parseIosSimulatorAccessibility('[]'), isA<IosAxInvalid>());
      expect(parseIosSimulatorAccessibility('{"elements":[]}'), isA<IosAxInvalid>());
      expect(
        parseIosSimulatorAccessibility('{"screen":{"width":1,"height":2}}'),
        isA<IosAxInvalid>().having((r) => r.reason, 'reason', contains('no screen size or element list')),
      );
    });
  });

  group('findIosAxMatches', () {
    List<String> labels(List<IosAxMatch> matches) => [for (final m in matches) m.label];

    test('exact label on a SpringBoard alert', () {
      final matches = findIosAxMatches(_snapshot(_openInAlert), 'Open');

      expect(labels(matches), ['Open']);
      expect((matches.single.x, matches.single.y), (275.0, 474.0));
    });

    test('ignores case and folds typographic quotes', () {
      final alert = _snapshot(_notificationAlert);
      expect(labels(findIosAxMatches(alert, "don't allow")), ['Don’t Allow']);
      expect(labels(findIosAxMatches(alert, 'ALLOW')), ['Allow']);
      expect(labels(findIosAxMatches(_snapshot(_openInAlert), 'Open in "Test App"?')), ['Open in “Test App”?']);
    });

    test('exact beats case-insensitive', () {
      final s = _snapshot(_tree([_element('ok', x: 0), _element('OK', x: 200)]));

      expect(labels(findIosAxMatches(s, 'OK')), ['OK']);
      expect(labels(findIosAxMatches(s, 'Ok')), ['ok', 'OK']);
    });

    test('falls back to the accessibility identifier', () {
      final s = _snapshot(_tree([_element('', identifier: 'allow_button'), _element('Allow', x: 200)]));

      final matches = findIosAxMatches(s, 'allow_button');
      expect(labels(matches), ['allow_button']);
      expect(labels(findIosAxMatches(s, 'Allow')), ['Allow'], reason: 'a label match wins over identifiers');
    });

    test('skips zero-frame semantics nodes scrolled off screen', () {
      // "Notification Test" is listed twice: once on screen, once with a zero frame.
      final matches = findIosAxMatches(_snapshot(_flutterApp), 'Notification Test');

      expect(matches, hasLength(1));
      expect((matches.single.x.round(), matches.single.y.round()), (201, 366));
      expect(findIosAxMatches(_snapshot(_flutterApp), 'Native View Test'), isEmpty);
    });

    test('several matches in screen order', () {
      final matches = findIosAxMatches(_snapshot(_flutterApp), 'Save');

      expect([for (final m in matches) (m.x.round(), m.y.round())], [(201, 710), (201, 766)]);
    });

    test('skips the application element, disabled, frameless and off-screen elements', () {
      final s = _snapshot(
        _tree([
          _element('Gone', enabled: false),
          _element('Gone', nullFrame: true),
          _element('Gone', x: 500, y: 10),
          _element('Gone', y: 900),
          _element('Gone', width: 0),
        ]),
      );

      expect(findIosAxMatches(s, 'App'), isEmpty);
      expect(findIosAxMatches(s, 'Gone'), isEmpty);
    });

    test('two matches on the same tap point count once', () {
      final s = _snapshot(_tree([_element('Row'), _element('Row')]));

      expect(findIosAxMatches(s, 'Row'), hasLength(1));
    });

    test('landscape alert frames are in interface points', () {
      expect(
        [for (final m in findIosAxMatches(_snapshot(_openInAlertLandscape), 'Open')) (m.x.round(), m.y.round())],
        [(511, 214)],
      );
      expect(
        [
          for (final m in findIosAxMatches(_snapshot(_locationAlertLandscape), 'Allow While Using App'))
            (m.x.round(), m.y.round()),
        ],
        [(437, 248)],
      );
      // SpringBoard reported portrait frames here; the helper rotated them.
      expect(
        [for (final m in findIosAxMatches(_snapshot(_portraitAlertOverLandscape), 'Allow')) (m.x.round(), m.y.round())],
        [(511, 258)],
      );
    });

    test('an empty query matches nothing', () {
      expect(findIosAxMatches(_snapshot(_openInAlert), '  '), isEmpty);
    });
  });

  test('iosAxVisibleLabels lists distinct on-screen labels on one line each', () {
    expect(iosAxVisibleLabels(_snapshot(_openInAlert)), ['Open in “Test App”?', 'Cancel', 'Open']);
    final app = iosAxVisibleLabels(_snapshot(_flutterApp));
    expect(app, contains('Increment'));
    expect(app.where((l) => l == 'Save'), hasLength(1));
    expect(app, isNot(contains('Native View Test')), reason: 'zero-frame nodes are not visible');
    expect(app, isNot(contains('Test App')), reason: 'the application element is not a label');
    expect(iosAxVisibleLabels(_snapshot(_tree([_element(r'two\nlines')]))), ['two lines']);
    expect(iosAxVisibleLabels(_snapshot(_notReady)), isEmpty);
  });

  group('nativeTapIosSimulatorText', () {
    late List<Object> trees;
    late List<(double, double)> taps;
    late IosSimulatorHidResult tapResult;
    late DateTime clock;
    late int describes;

    setUp(() {
      trees = [];
      taps = [];
      tapResult = const IosSimulatorHidTapped();
      clock = DateTime(2026);
      describes = 0;
    });

    Future<NativeTapResult> run(String text, {int? index, int? timeout, String? udid = 'UDID'}) =>
        nativeTapIosSimulatorText(
          (x: null, y: null, text: text, index: index, timeoutSeconds: timeout, logical: false),
          udid: udid,
          describe: (u) async {
            expect(u, 'UDID');
            describes++;
            final next = trees.length > 1 ? trees.removeAt(0) : trees.single;
            return next is IosSimulatorDescribeResult ? next : IosSimulatorDescribed(next as String);
          },
          tap: (u, x, y) async {
            taps.add((x, y));
            return tapResult;
          },
          now: () => clock,
          sleep: (d) async => clock = clock.add(d),
        );

    test('taps the frame center and reports the label', () async {
      trees = [_openInAlert];

      final result = await run('Open');

      expect(result, isA<NativeTapIosSimulator>().having((r) => (r.x, r.y, r.text), 'tap', (275, 474, 'Open')));
      expect(taps, [(275.0, 474.0)]);
    });

    test('keeps reading while the tree is not ready', () async {
      trees = [_notReady, _notReady, _notificationAlert];

      final result = await run('Allow');

      expect(result, isA<NativeTapIosSimulator>().having((r) => r.text, 'text', 'Allow'));
      expect(describes, 3);
    });

    test('no match after the timeout lists the visible labels', () async {
      trees = [_openInAlert];

      final result = await run('Allow', timeout: 1);

      expect(
        result,
        isA<NativeTapNoMatch>()
            .having((r) => r.query, 'query', 'Allow')
            .having((r) => r.visibleLabels, 'labels', ['Open in “Test App”?', 'Cancel', 'Open']),
      );
      expect(taps, isEmpty);
      // 1 s at 300 ms per attempt: reads at 0, 300, 600, 900 and 1200 ms.
      expect(describes, 5);
    });

    test('--timeout 0 reads once', () async {
      trees = [_notReady];

      expect(await run('Allow', timeout: 0), isA<NativeTapNoMatch>().having((r) => r.visibleLabels, 'labels', []));
      expect(describes, 1);
    });

    test('several matches without --index are ambiguous', () async {
      trees = [_flutterApp];

      final result = await run('Save');

      expect(
        result,
        isA<NativeTapAmbiguous>().having((r) => r.candidates, 'candidates', [
          (label: 'Save', x: 201, y: 710),
          (label: 'Save', x: 201, y: 766),
        ]),
      );
      expect(taps, isEmpty);
    });

    test('--index picks a match', () async {
      trees = [_flutterApp];

      final result = await run('save', index: 1);

      expect(result, isA<NativeTapIosSimulator>().having((r) => (r.x, r.y), 'point', (201, 766)));
    });

    test('--index past the last match', () async {
      trees = [_flutterApp];

      final result = await run('Save', index: 2, timeout: 0);

      expect(
        result,
        isA<NativeTapIndexOutOfRange>().having((r) => (r.query, r.index, r.count), 'fields', ('Save', 2, 2)),
      );
    });

    test('multi-line labels are reported on one line', () async {
      trees = [
        _tree([_element(r'Status:\nauthorized')])
      ];

      final result = await run('Status:\nauthorized');

      expect(result, isA<NativeTapIosSimulator>().having((r) => r.text, 'text', 'Status: authorized'));
    });

    test('an unreadable tree fails at once, without a fallback tap', () async {
      trees = [const IosSimulatorDescribeUnavailable('this CoreSimulator has no accessibility request API')];

      final result = await run('Allow');

      expect(
        result,
        isA<NativeTapIosSimulatorAccessibilityUnavailable>()
            .having((r) => r.reason, 'reason', 'this CoreSimulator has no accessibility request API'),
      );
      expect(describes, 1);
      expect(taps, isEmpty);
    });

    test('unknown orientation fails at once', () async {
      trees = [const IosSimulatorDescribeOrientationUnknown('cannot tell')];

      expect(
        await run('Allow'),
        isA<NativeTapIosSimulatorOrientationUnknown>().having((r) => r.message, 'message', 'cannot tell'),
      );
    });

    test('invalid JSON is reported as unavailable', () async {
      trees = ['garbage'];

      expect(
        await run('Allow'),
        isA<NativeTapIosSimulatorAccessibilityUnavailable>()
            .having((r) => r.reason, 'reason', startsWith('the accessibility tree is not valid JSON')),
      );
    });

    test('no simulator UDID', () async {
      expect(await run('Allow', udid: null), isA<NativeTapIosSimulatorAccessibilityUnavailable>());
    });

    test('tap failures map to the coordinate tap results', () async {
      trees = [_openInAlert];

      tapResult = const IosSimulatorHidFailed('touch partially delivered: boom');
      expect(await run('Open'), isA<NativeTapIosSimulatorFailed>());
      tapResult = const IosSimulatorHidOutOfBounds('outside');
      expect(await run('Open'), isA<NativeTapIosSimulatorOutOfBounds>());
      tapResult = const IosSimulatorHidOrientationUnknown('rotating');
      expect(await run('Open'), isA<NativeTapIosSimulatorOrientationUnknown>());
      tapResult = const IosSimulatorHidUnavailable('xcrun not available');
      expect(
        await run('Open'),
        isA<NativeTapIosSimulatorAccessibilityUnavailable>().having((r) => r.reason, 'reason', 'xcrun not available'),
      );
    });
  });

  group('iosSimulatorDescribe with a fake runner', () {
    late Directory cacheDir;
    late List<List<String>> calls;
    late Object helperOutput;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('fdb-describe-test-');
      calls = [];
      helperOutput = (exitCode: 0, stdout: _openInAlert, stderr: '');
    });

    tearDown(() => cacheDir.delete(recursive: true));

    Future<HidProcessOutput> runner(String executable, List<String> arguments, Duration timeout) async {
      calls.add([executable, ...arguments]);
      if (executable == 'xcrun') {
        await File(arguments.last).writeAsString('binary');
        return (exitCode: 0, stdout: '', stderr: '');
      }
      if (helperOutput is TimeoutException) throw helperOutput as TimeoutException;
      return helperOutput as HidProcessOutput;
    }

    Future<IosSimulatorDescribeResult> describe() => iosSimulatorDescribe(
          udid: 'UDID',
          environment: {'DEVELOPER_DIR': '/dev/dir'},
          runner: runner,
          cacheDir: cacheDir.path,
        );

    test('runs the cached helper with describe and returns its stdout', () async {
      final result = await describe();

      expect(result, isA<IosSimulatorDescribed>().having((r) => r.json, 'json', _openInAlert));
      expect(calls.last, [iosSimulatorHidBinaryPath(cacheDir.path), 'describe', '/dev/dir', 'UDID']);
    });

    test('exit code 1 is unavailable with the ERROR line', () async {
      helperOutput = (
        exitCode: 1,
        stdout: '',
        stderr: 'objc[1]: noise\nERROR: simulator 00000000-0000-0000-0000-000000000000 not found\n',
      );

      expect(
        await describe(),
        isA<IosSimulatorDescribeUnavailable>()
            .having((r) => r.reason, 'reason', 'simulator 00000000-0000-0000-0000-000000000000 not found'),
      );
    });

    test('exit code 5 is orientation unknown', () async {
      helperOutput = (exitCode: 5, stdout: '', stderr: "ERROR: native-tap can't tell which way\n");

      expect(
        await describe(),
        isA<IosSimulatorDescribeOrientationUnknown>()
            .having((r) => r.message, 'message', "native-tap can't tell which way"),
      );
    });

    test('a timeout is unavailable', () async {
      helperOutput = TimeoutException('describe');

      expect(
        await describe(),
        isA<IosSimulatorDescribeUnavailable>().having((r) => r.reason, 'reason', contains('timed out')),
      );
    });
  });

  test('helper source has the describe subcommand and guards the private API', () {
    expect(iosSimulatorHidSource, contains('arguments[1] == "describe"'));
    expect(iosSimulatorHidSource, contains('AccessibilityPlatformTranslation'));
    expect(iosSimulatorHidSource, contains('sendAccessibilityRequestAsync:completionQueue:completionHandler:'));
    expect(iosSimulatorHidSource, contains('frontmostApplicationWithDisplayId:bridgeDelegateToken:'));
    expect(iosSimulatorHidSource, contains('guard device.responds(to: sendAXSelector)'));
    expect(iosSimulatorHidSource, contains('withExtendedLifetime(delegate)'));
    // The tap path still checks its usage and bounds.
    expect(iosSimulatorHidSource, contains('arguments.count == 6 && arguments[1] == "tap"'));
  });

  test(
    'compiles the real helper and describes an unknown simulator',
    () async {
      final cacheDir = await Directory.systemTemp.createTemp('fdb-describe-it-');
      addTearDown(() => cacheDir.delete(recursive: true));

      final result = await iosSimulatorDescribe(udid: '00000000-0000-0000-0000-000000000000', cacheDir: cacheDir.path);

      expect(File(iosSimulatorHidBinaryPath(cacheDir.path)).existsSync(), isTrue);
      expect(result, isA<IosSimulatorDescribeUnavailable>().having((r) => r.reason, 'reason', contains('not found')));
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: _hasSimulatorToolchain() ? false : 'requires macOS with xcrun swiftc, simctl and SimulatorKit',
  );
}

bool _hasSimulatorToolchain() {
  if (!Platform.isMacOS) return false;
  try {
    if (Process.runSync('xcrun', ['--find', 'swiftc']).exitCode != 0) return false;
    if (Process.runSync('xcrun', ['simctl', 'help']).exitCode != 0) return false;
    final developerDir =
        Platform.environment['DEVELOPER_DIR'] ?? (Process.runSync('xcode-select', ['-p']).stdout as String).trim();
    return Directory('$developerDir/Library/PrivateFrameworks/SimulatorKit.framework').existsSync() ||
        Directory('$developerDir/../SharedFrameworks/SimulatorKit.framework').existsSync();
  } catch (_) {
    return false;
  }
}
