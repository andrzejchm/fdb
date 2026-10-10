import 'dart:io';

import 'package:fdb/core/commands/native_tap/android_native_tap.dart';
import 'package:fdb/core/commands/native_tap/android_ui_dump.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:test/test.dart';

String _fixture(String name) => File('test/fixtures/native_tap/$name').readAsStringSync();

List<AndroidUiNode> _nodes(String raw) => switch (parseAndroidUiDump(raw)) {
      AndroidUiDumpParsed(:final nodes) => nodes,
      AndroidUiDumpInvalid(:final reason) => fail('expected a valid dump, got: $reason'),
    };

NativeTapInput _textInput(String text, {int? index, int timeoutSeconds = 5}) =>
    (x: null, y: null, text: text, index: index, timeoutSeconds: timeoutSeconds, logical: false);

NativeTapInput _atInput(double x, double y, {bool logical = false}) =>
    (x: x, y: y, text: null, index: null, timeoutSeconds: 5, logical: logical);

void main() {
  group('parseAndroidUiDump', () {
    test('parses a real permission dialog dump with the trailing "dumped to" line', () {
      final nodes = _nodes(_fixture('permission_dialog_hyperos.xml'));
      final labels = nodes.map((n) => n.text).where((t) => t.isNotEmpty).toList();
      expect(labels, [
        'Allow test_app to take pictures and record video?',
        'While using the app',
        'Only this time',
        'Don’t allow',
      ]);
      final allow = nodes.firstWhere((n) => n.text == 'While using the app');
      expect(allow.clickable, isTrue);
      expect(allow.bounds, const AndroidBounds(141, 2358, 1299, 2546));
      expect(allow.resourceId, 'com.android.permissioncontroller:id/permission_allow_foreground_only_button');
    });

    test('decodes XML entities and trims text', () {
      final nodes = _nodes(_fixture('entities_and_nesting.xml'));
      final texts = nodes.map((n) => n.text).where((t) => t.isNotEmpty).toList();
      expect(texts, [
        'Terms & Conditions',
        'Say "hi" <now> > later',
        'Line one\nline two',
        'OK',
        'ok',
        'Hidden',
        'Emoji 😀 😀',
      ]);
    });

    test('links nodes to their parents', () {
      final nodes = _nodes(_fixture('entities_and_nesting.xml'));
      final say = nodes.firstWhere((n) => n.text.startsWith('Say'));
      expect(say.parent?.parent?.resourceId, 'com.example:id/row');
      expect(nodes.first.parent, isNull);
    });

    test('a ">" inside a quoted attribute does not end the tag', () {
      final nodes =
          _nodes('<hierarchy rotation="0"><node text="a>b" clickable="true" bounds="[0,0][10,10]" /></hierarchy>');
      expect(nodes.single.text, 'a>b');
      expect(nodes.single.clickable, isTrue);
    });

    test('"could not get idle state" (exit 0 on device) is invalid, not an empty screen', () {
      final parse = parseAndroidUiDump('ERROR: could not get idle state.\n');
      expect(parse, isA<AndroidUiDumpInvalid>());
      expect((parse as AndroidUiDumpInvalid).reason, 'ERROR: could not get idle state.');
    });

    test('output without a hierarchy is invalid', () {
      final parse = parseAndroidUiDump('UI hierchary dumped to: /dev/tty\n');
      expect(parse, isA<AndroidUiDumpInvalid>());
      expect((parse as AndroidUiDumpInvalid).reason, contains('no <hierarchy>'));
      expect(parseAndroidUiDump(''), isA<AndroidUiDumpInvalid>());
    });

    test('a truncated dump is invalid', () {
      final raw = _fixture('permission_dialog_hyperos.xml');
      final parse = parseAndroidUiDump(raw.substring(0, raw.length ~/ 2));
      expect(parse, isA<AndroidUiDumpInvalid>());
      expect((parse as AndroidUiDumpInvalid).reason, contains('truncated'));
    });

    test('an empty self-closing hierarchy is a valid empty dump', () {
      expect(_nodes('<?xml version="1.0"?><hierarchy rotation="0" />'), isEmpty);
    });
  });

  group('parseAndroidBounds', () {
    test('parses [l,t][r,b] and centers', () {
      final b = parseAndroidBounds('[141,2358][1299,2546]')!;
      expect((b.centerX, b.centerY), (720, 2452));
    });

    test('rejects malformed bounds', () {
      expect(parseAndroidBounds('141,2358,1299,2546'), isNull);
      expect(parseAndroidBounds(null), isNull);
    });
  });

  group('findAndroidUiMatches', () {
    final dialog = _nodes(_fixture('permission_dialog_hyperos.xml'));
    final nested = _nodes(_fixture('entities_and_nesting.xml'));

    test('exact text', () {
      final matches = findAndroidUiMatches(dialog, 'While using the app');
      expect(matches.single.label, 'While using the app');
      expect((matches.single.bounds.centerX, matches.single.bounds.centerY), (720, 2452));
    });

    test('trims the query', () {
      expect(findAndroidUiMatches(dialog, '  Only this time '), hasLength(1));
    });

    test('content-desc', () {
      final matches = findAndroidUiMatches(nested, 'Close');
      expect(matches.single.target.resourceId, 'com.example:id/close');
    });

    test('exact case wins over case-insensitive matches', () {
      final matches = findAndroidUiMatches(nested, 'OK');
      expect(matches.single.node.resourceId, 'com.example:id/ok_1');
    });

    test('falls back to case-insensitive', () {
      final matches = findAndroidUiMatches(dialog, 'while using the APP');
      expect(matches.single.label, 'While using the app');
      expect(findAndroidUiMatches(nested, 'Ok'), hasLength(2));
    });

    test('resource-id, full or bare', () {
      final full = findAndroidUiMatches(dialog, 'com.android.permissioncontroller:id/permission_allow_one_time_button');
      final bare = findAndroidUiMatches(dialog, 'permission_allow_one_time_button');
      expect(full.single.label, 'Only this time');
      expect(bare.single.label, 'Only this time');
    });

    test('a non-clickable label inside a clickable row taps its own bounds', () {
      final matches = findAndroidUiMatches(nested, 'Say "hi" <now> > later');
      expect(matches.single.target, same(matches.single.node));
      expect(matches.single.bounds, const AndroidBounds(40, 320, 540, 480));
      expect(matches.single.label, 'Say "hi" <now> > later');
    });

    test('dialog message text taps inside its own bounds, not the allow button', () {
      final matches = findAndroidUiMatches(dialog, 'Allow test_app to take pictures and record video?');
      final m = matches.single;
      expect(m.bounds, const AndroidBounds(171, 2067, 1269, 2238));
      expect((m.bounds.centerX, m.bounds.centerY), (720, 2152));
      final allow = findAndroidUiMatches(dialog, 'While using the app').single.bounds;
      expect(allow.top <= m.bounds.centerY && m.bounds.centerY < allow.bottom, isFalse);
    });

    test('a node without usable bounds falls back to its clickable ancestor', () {
      final nodes = _nodes(
        '<hierarchy><node clickable="true" bounds="[0,0][100,100]">'
        '<node text="Go" clickable="false" bounds="[0,0][0,0]" /></node></hierarchy>',
      );
      final m = findAndroidUiMatches(nodes, 'Go').single;
      expect(m.bounds, const AndroidBounds(0, 0, 100, 100));
      expect(m.target.clickable, isTrue);
    });

    test('two separate labels inside one clickable container are two matches', () {
      final nodes = _nodes(
        '<hierarchy><node clickable="true" bounds="[0,0][1000,1000]">'
        '<node text="Allow" bounds="[0,0][500,100]" /><node text="Allow" bounds="[500,0][1000,100]" />'
        '</node></hierarchy>',
      );
      expect(findAndroidUiMatches(nodes, 'Allow'), hasLength(2));
    });

    test('skips disabled nodes', () {
      final nodes = _nodes(
        '<hierarchy><node bounds="[0,0][1000,1000]"><node text="Send" enabled="false" clickable="true" '
        'bounds="[0,0][100,100]" /></node></hierarchy>',
      );
      expect(findAndroidUiMatches(nodes, 'Send'), isEmpty);
    });

    test('skips nodes centered outside the screen', () {
      final nodes = _nodes(
        '<hierarchy><node bounds="[0,0][1080,2400]"><node text="Below" bounds="[0,2400][1080,2600]" />'
        '<node text="Edge" bounds="[0,2300][1080,2450]" /></node></hierarchy>',
      );
      expect(findAndroidUiMatches(nodes, 'Below'), isEmpty);
      expect(findAndroidUiMatches(nodes, 'Edge'), hasLength(1));
    });

    test('straight quotes and no-break spaces match their typographic forms', () {
      expect(findAndroidUiMatches(dialog, "Don't allow").single.label, 'Don’t allow');
      final nodes = _nodes('<hierarchy><node text="Say “hi”&#160;now" bounds="[0,0][10,10]" /></hierarchy>');
      expect(findAndroidUiMatches(nodes, 'say "hi" now'), hasLength(1));
    });

    test('labels that resolve to the same clickable target count once', () {
      final nodes = _nodes(
        '<hierarchy><node clickable="true" content-desc="Allow" bounds="[0,0][100,100]">'
        '<node text="Allow" clickable="false" bounds="[10,10][90,90]" /></node></hierarchy>',
      );
      expect(findAndroidUiMatches(nodes, 'Allow'), hasLength(1));
    });

    test('a non-clickable node without a clickable ancestor taps itself', () {
      final matches = findAndroidUiMatches(nested, 'Terms & Conditions');
      expect(matches.single.bounds, const AndroidBounds(40, 100, 1040, 200));
    });

    test('skips nodes without on-screen bounds', () {
      expect(findAndroidUiMatches(nested, 'Hidden'), isEmpty);
    });

    test('no match', () {
      expect(findAndroidUiMatches(dialog, 'Allow'), isEmpty);
      expect(findAndroidUiMatches(dialog, '   '), isEmpty);
    });
  });

  group('pickAndroidUiMatch', () {
    final nested = _nodes(_fixture('entities_and_nesting.xml'));
    final twoOks = findAndroidUiMatches(nested, 'Ok');

    test('one match without an index is picked', () {
      final pick = pickAndroidUiMatch(findAndroidUiMatches(nested, 'Close'), index: null);
      expect(pick, isA<AndroidUiPicked>());
    });

    test('several matches without an index are ambiguous', () {
      expect(pickAndroidUiMatch(twoOks, index: null), isA<AndroidUiPickAmbiguous>());
    });

    test('--index is 0-based, in document order', () {
      final first = pickAndroidUiMatch(twoOks, index: 0) as AndroidUiPicked;
      final second = pickAndroidUiMatch(twoOks, index: 1) as AndroidUiPicked;
      expect(first.match.node.resourceId, 'com.example:id/ok_1');
      expect(second.match.node.resourceId, 'com.example:id/ok_2');
    });

    test('--index past the end picks nothing', () {
      expect(pickAndroidUiMatch(twoOks, index: 2), isA<AndroidUiPickNone>());
      expect(pickAndroidUiMatch(const [], index: null), isA<AndroidUiPickNone>());
    });
  });

  test('androidVisibleLabels lists distinct on-screen labels on one line each', () {
    final labels = androidVisibleLabels(_nodes(_fixture('entities_and_nesting.xml')));
    expect(labels, [
      'Terms & Conditions',
      'Say "hi" <now> > later',
      'Line one line two',
      'Close',
      'OK',
      'ok',
      'Emoji 😀 😀',
    ]);
  });

  group('classifyAndroidInputTap', () {
    test('clean output is a success', () {
      expect(classifyAndroidInputTap(exitCode: 0, stdout: '', stderr: ''), isNull);
    });

    test('SecurityException with exit 0 is blocked injection', () {
      final result = classifyAndroidInputTap(
        exitCode: 0,
        stdout: '',
        stderr: 'java.lang.SecurityException: Injecting input events requires the caller (or the source of the '
            'instrumentation, if any) to have the INJECT_EVENTS permission.\n\tat android.os.Parcel...',
      );
      expect(result, isA<NativeTapInputInjectionBlocked>());
      expect((result as NativeTapInputInjectionBlocked).details, startsWith('java.lang.SecurityException'));
    });

    test('INJECT_EVENTS on stdout with a non-zero exit is blocked injection', () {
      final result = classifyAndroidInputTap(exitCode: 255, stdout: 'needs INJECT_EVENTS', stderr: '');
      expect(result, isA<NativeTapInputInjectionBlocked>());
    });

    test('another exception with exit 0 is a failure', () {
      final result = classifyAndroidInputTap(exitCode: 0, stdout: 'java.lang.IllegalStateException: boom', stderr: '');
      expect(result, isA<NativeTapAdbFailed>());
      expect((result as NativeTapAdbFailed).details, 'java.lang.IllegalStateException: boom');
    });

    test('a non-zero exit is a failure', () {
      final result = classifyAndroidInputTap(exitCode: 1, stdout: '', stderr: 'error: device offline');
      expect((result as NativeTapAdbFailed).details, 'error: device offline');
    });
  });

  group('--logical', () {
    test('parseWmDensity prefers the override density', () {
      expect(parseWmDensity('Physical density: 600\nOverride density: 480\n'), 480);
      expect(parseWmDensity('Physical density: 600\n'), 600);
      expect(parseWmDensity('garbage'), isNull);
    });

    test('logicalToPhysical multiplies and rounds', () {
      expect(logicalToPhysical(340, 793.3333, 3.75), (x: 1275, y: 2975));
      expect(logicalToPhysical(10.2, 20.6, 2), (x: 20, y: 41));
    });

    test('uses the app ratio when the app reports one', () async {
      final adb = _FakeAdb();
      final result = await nativeTapAndroid(
        _atInput(340, 793, logical: true),
        deviceId: 'dev1',
        adb: adb.call,
        appDevicePixelRatio: () async => 3.75,
      );
      expect(result, isA<NativeTapAndroid>());
      expect(adb.calls, [
        ['-s', 'dev1', 'shell', 'input', 'tap', '1275', '2974'],
      ]);
    });

    test('falls back to wm density / 160', () async {
      final adb = _FakeAdb()..respond(['shell', 'wm', 'density'], 'Physical density: 600\nOverride density: 480\n');
      final result = await nativeTapAndroid(
        _atInput(100, 200, logical: true),
        deviceId: null,
        adb: adb.call,
        appDevicePixelRatio: () async => null,
      );
      expect(result, isA<NativeTapAndroid>());
      expect((result as NativeTapAndroid).x, 300);
      expect(result.y, 600);
    });

    test('fails when no ratio is available', () async {
      final adb = _FakeAdb()..respond(['shell', 'wm', 'density'], '');
      final result = await nativeTapAndroid(
        _atInput(100, 200, logical: true),
        deviceId: null,
        adb: adb.call,
        appDevicePixelRatio: () async => null,
      );
      expect(result, isA<NativeTapDevicePixelRatioUnavailable>());
      expect(adb.calls.where((c) => c.contains('input')), isEmpty);
    });

    test('without --logical coordinates are physical and truncated', () async {
      final adb = _FakeAdb();
      final result = await nativeTapAndroid(_atInput(200.9, 400.2), deviceId: null, adb: adb.call);
      expect((result as NativeTapAndroid).x, 200);
      expect(result.y, 400);
      expect(result.text, isNull);
    });
  });

  group('nativeTapAndroid --text', () {
    final dialog = _fixture('permission_dialog_hyperos.xml');

    test('taps the center of the matched element', () async {
      final adb = _FakeAdb()..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], dialog);
      final result = await nativeTapAndroid(_textInput('While using the app'), deviceId: 'd', adb: adb.call);
      expect(result, isA<NativeTapAndroid>());
      final tapped = result as NativeTapAndroid;
      expect((tapped.x, tapped.y, tapped.text), (720, 2452, 'While using the app'));
      expect(adb.calls.last, ['-s', 'd', 'shell', 'input', 'tap', '720', '2452']);
    });

    test('polls until the dialog appears', () async {
      final clock = _FakeClock();
      final adb = _FakeAdb()
        ..respondSequence([
          'exec-out',
          'uiautomator',
          'dump',
          '/dev/tty'
        ], [
          'ERROR: could not get idle state.',
          _fixture('entities_and_nesting.xml'),
          dialog,
        ]);
      final result = await nativeTapAndroid(
        _textInput('Only this time'),
        deviceId: null,
        adb: adb.call,
        now: clock.now,
        sleep: clock.sleep,
      );
      expect((result as NativeTapAndroid).text, 'Only this time');
    });

    test('no match after the timeout lists the visible labels', () async {
      final clock = _FakeClock();
      final adb = _FakeAdb()..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], dialog);
      final result = await nativeTapAndroid(
        _textInput('Allow', timeoutSeconds: 1),
        deviceId: null,
        adb: adb.call,
        now: clock.now,
        sleep: clock.sleep,
      );
      expect(result, isA<NativeTapNoMatch>());
      expect((result as NativeTapNoMatch).visibleLabels, contains('While using the app'));
      expect(adb.calls.where((c) => c.contains('input')), isEmpty);
      expect(clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
    });

    test('several matches without --index are ambiguous and tap nothing', () async {
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], _fixture('entities_and_nesting.xml'));
      final result = await nativeTapAndroid(_textInput('Ok'), deviceId: null, adb: adb.call);
      expect(result, isA<NativeTapAmbiguous>());
      expect((result as NativeTapAmbiguous).candidates, [
        (label: 'OK', x: 270, y: 650),
        (label: 'ok', x: 810, y: 650),
      ]);
      expect(adb.calls.where((c) => c.contains('input')), isEmpty);
    });

    test('--index picks a match', () async {
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], _fixture('entities_and_nesting.xml'));
      final result = await nativeTapAndroid(_textInput('Ok', index: 1), deviceId: null, adb: adb.call);
      expect(((result as NativeTapAndroid).x, result.y, result.text), (810, 650, 'ok'));
    });

    test('--index out of range after the timeout', () async {
      final clock = _FakeClock();
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], _fixture('entities_and_nesting.xml'));
      final result = await nativeTapAndroid(
        _textInput('Ok', index: 5, timeoutSeconds: 1),
        deviceId: null,
        adb: adb.call,
        now: clock.now,
        sleep: clock.sleep,
      );
      expect(result, isA<NativeTapIndexOutOfRange>());
      expect((result as NativeTapIndexOutOfRange).count, 2);
    });

    test('falls back to dumping to a file, deleting it before and after', () async {
      const file = '/data/local/tmp/fdb_window_dump_test.xml';
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], 'Exception: /dev/tty not supported')
        ..respond(['shell', 'rm -f $file; uiautomator dump $file'], 'UI hierchary dumped to: $file')
        ..respond(['exec-out', 'cat', file], dialog);
      final result =
          await nativeTapAndroid(_textInput('Only this time'), deviceId: null, adb: adb.call, dumpFile: file);
      expect((result as NativeTapAndroid).text, 'Only this time');
      final catAt = adb.calls.indexWhere((c) => c.contains('cat'));
      expect(adb.calls[catAt + 1], ['shell', 'rm', '-f', file]);
    });

    test('the dump file is unique per invocation', () {
      expect(
        androidUiDumpFileFor(pid: 12, timestampMs: 34),
        isNot(androidUiDumpFileFor(pid: 12, timestampMs: 35)),
      );
    });

    test('an idle-state error retries /dev/tty without the file fallback', () async {
      final clock = _FakeClock();
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], 'ERROR: could not get idle state.');
      final result = await nativeTapAndroid(
        _textInput('Allow', timeoutSeconds: 1),
        deviceId: null,
        adb: adb.call,
        now: clock.now,
        sleep: clock.sleep,
        dumpFile: '/data/local/tmp/x.xml',
      );
      expect(result, isA<NativeTapUiDumpFailed>());
      expect((result as NativeTapUiDumpFailed).reason, 'ERROR: could not get idle state.');
      expect(adb.calls.where((c) => c.join(' ').contains('/data/local/tmp/x.xml')), isEmpty);
      expect(adb.calls.length, greaterThan(1));
    });

    test('a file dump that fails is never read, so a stale file is not used', () async {
      const file = '/data/local/tmp/y.xml';
      final clock = _FakeClock();
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], '')
        ..respond(['shell', 'rm -f $file; uiautomator dump $file'],
            'ERROR: null root node returned by UiTestAutomationBridge.');
      final result = await nativeTapAndroid(
        _textInput('Allow', timeoutSeconds: 1),
        deviceId: null,
        adb: adb.call,
        now: clock.now,
        sleep: clock.sleep,
        dumpFile: file,
      );
      expect(result, isA<NativeTapUiDumpFailed>());
      expect(adb.calls.where((c) => c.contains('cat')), isEmpty);
    });

    test('a non-adb exception is a failure, not "install adb"', () async {
      final result = await nativeTapAndroid(
        _textInput('x'),
        deviceId: null,
        adb: (_) async => throw StateError('boom'),
      );
      expect(result, isA<NativeTapAdbFailed>());
      expect((result as NativeTapAdbFailed).details, contains('boom'));
    });

    test('blocked injection after a match', () async {
      final adb = _FakeAdb()
        ..respond(['exec-out', 'uiautomator', 'dump', '/dev/tty'], dialog)
        ..respond(['shell', 'input', 'tap', '720', '2452'], '',
            stderr: 'java.lang.SecurityException: Injecting to another application requires INJECT_EVENTS permission');
      final result = await nativeTapAndroid(_textInput('While using the app'), deviceId: null, adb: adb.call);
      expect(result, isA<NativeTapInputInjectionBlocked>());
    });

    test('adb that cannot start is reported', () async {
      final result = await nativeTapAndroid(
        _textInput('x'),
        deviceId: null,
        adb: (_) async => throw const ProcessException('adb', [], 'No such file or directory'),
      );
      expect(result, isA<NativeTapAdbExecutionFailed>());
    });
  });
}

class _FakeAdb {
  final calls = <List<String>>[];
  final _responses = <String, List<ProcessResult>>{};

  void respond(List<String> args, String stdout, {String stderr = '', int exitCode = 0}) {
    _responses[args.join(' ')] = [ProcessResult(0, exitCode, stdout, stderr)];
  }

  void respondSequence(List<String> args, List<String> stdouts) {
    _responses[args.join(' ')] = [for (final s in stdouts) ProcessResult(0, 0, s, '')];
  }

  Future<ProcessResult> call(List<String> args) async {
    calls.add(args);
    final withoutDevice = args.first == '-s' ? args.sublist(2) : args;
    final queue = _responses[withoutDevice.join(' ')];
    if (queue == null) return ProcessResult(0, 0, '', '');
    return queue.length > 1 ? queue.removeAt(0) : queue.single;
  }
}

class _FakeClock {
  final _start = DateTime(2026);
  var elapsed = Duration.zero;

  DateTime now() => _start.add(elapsed);

  Future<void> sleep(Duration d) async => elapsed += d;
}
