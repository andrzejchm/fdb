import 'dart:io';

import 'package:fdb/cli/binstub_sdk_check_cli.dart';
import 'package:fdb/core/binstub_sdk_check.dart';
import 'package:test/test.dart';

/// Header and snapshot fast path shared by both binstub formats pub writes.
String _head(String pubCache, String script, String version, String package) {
  final snapshot = '$pubCache/global_packages/$package/bin/$script.dart-$version.snapshot';
  return '''
#!/usr/bin/env sh
# This file was created by pub v$version.
# Package: $package
# Version: 1.11.1
# Executable: ${script == 'fdb' ? 'fdb' : 'fdb-controller'}
# Script: $script
if [ -f $snapshot ]; then
  dart "$snapshot" "\$@"
  # The VM exits with code 253 if the snapshot version is out-of-date.
  # If it is, we need to delete it and run "pub global" manually.
  exit_code=\$?
  if [ \$exit_code != 253 ]; then
    exit \$exit_code
  fi
''';
}

/// Format 1: `if [ -f snap ]; then ... fi; dart pub global run ...`.
String _shapeIfFi(String pubCache, String script, String version, {String package = 'fdb'}) =>
    '${_head(pubCache, script, version, package)}fi\ndart pub global run $package:$script "\$@"\n';

/// Format 2: `if ...; then ...; dart pub -v global run ...; else ...; fi`.
String _shapeIfElse(String pubCache, String script, String version) => '${_head(pubCache, script, version, 'fdb')}'
    '  dart pub -v global run fdb:$script "\$@"\nelse\n  dart pub global run fdb:$script "\$@"\nfi\n';

void main() {
  late Directory tmp;
  late String pubCache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fdb_binstub_test_');
    pubCache = tmp.resolveSymbolicLinksSync();
    Directory('$pubCache/bin').createSync(recursive: true);
    Directory('$pubCache/global_packages/fdb/bin').createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeSnapshot(String script, String version) =>
      File('$pubCache/global_packages/fdb/bin/$script.dart-$version.snapshot').writeAsStringSync('kernel');

  File writeBinstub(String name, String content) {
    final f = File('$pubCache/bin/$name')..writeAsStringSync(content);
    if (!Platform.isWindows) Process.runSync('chmod', ['755', f.path]);
    return f;
  }

  BinstubSdkCheckInput input({String? script, bool repairEnabled = true, bool isWindows = false}) => (
        pubCacheDir: pubCache,
        runningDartVersion: '3.12.2',
        scriptPath: script ?? '$pubCache/global_packages/fdb/bin/fdb.dart-3.12.2.snapshot',
        repairEnabled: repairEnabled,
        isWindows: isWindows,
      );

  test('no mismatch → no-op, file untouched', () {
    writeSnapshot('fdb', '3.12.2');
    final content = _shapeIfFi(pubCache, 'fdb', '3.12.2');
    final f = writeBinstub('fdb', content);

    expect(checkBinstubSdk(input()), isA<BinstubSdkCheckNoOp>());
    expect(f.readAsStringSync(), content);
  });

  test('mismatch + matching snapshot → both binstub shapes repaired and kept executable', () {
    writeSnapshot('fdb', '3.12.2');
    writeSnapshot('controller', '3.12.2');
    final fdb = writeBinstub('fdb', _shapeIfFi(pubCache, 'fdb', '3.13.5'));
    final controller = writeBinstub('fdb-controller', _shapeIfElse(pubCache, 'controller', '3.11.5'));

    final repaired = checkBinstubSdk(input()) as BinstubSdkCheckRepaired;

    expect(repaired.unrepaired, isEmpty);
    expect(repaired.repairs, [
      (binstub: fdb.path, from: '3.13.5', to: '3.12.2'),
      (binstub: controller.path, from: '3.11.5', to: '3.12.2'),
    ]);

    // Only snapshot references change; the "created by pub" header is kept.
    expect(fdb.readAsStringSync(), _shapeIfFi(pubCache, 'fdb', '3.12.2').replaceFirst('pub v3.12.2', 'pub v3.13.5'));
    expect(
      controller.readAsStringSync(),
      _shapeIfElse(pubCache, 'controller', '3.12.2').replaceFirst('pub v3.12.2', 'pub v3.11.5'),
    );
    expect(Directory('$pubCache/bin').listSync().where((e) => e.path.contains('fdb-tmp')), isEmpty);
    if (!Platform.isWindows) {
      for (final f in [fdb, controller]) {
        expect(f.statSync().mode & 0x1ff, 0x1ed, reason: '${f.path} must stay 0755');
      }
    }

    // Second run is a no-op.
    expect(checkBinstubSdk(input()), isA<BinstubSdkCheckNoOp>());
    final lines = formatBinstubSdkCheckResult(repaired);
    expect(lines, hasLength(2));
    expect(lines, everyElement(contains('Repointed it to the 3.12.2 snapshot')));
    expect(lines.first, startsWith('WARNING: fdb launcher ${fdb.path} referenced a Dart 3.13.5 snapshot'));
  });

  test('mismatch + missing snapshot → silent no-op, file untouched', () {
    writeSnapshot('fdb', '3.12.2');
    final content = _shapeIfElse(pubCache, 'controller', '3.11.5');
    final f = writeBinstub('fdb-controller', content);

    expect(checkBinstubSdk(input()), isA<BinstubSdkCheckNoOp>());
    expect(f.readAsStringSync(), content);
  });

  test('opt-out → detected but not written', () {
    writeSnapshot('fdb', '3.12.2');
    final content = _shapeIfFi(pubCache, 'fdb', '3.13.5');
    final f = writeBinstub('fdb', content);

    final result = checkBinstubSdk(input(repairEnabled: false)) as BinstubSdkCheckUnrepaired;

    final m = result.mismatches.single;
    expect((m.binstub, m.from, m.to, m.reason), (f.path, '3.13.5', '3.12.2', BinstubUnrepairedReason.optedOut));
    expect(f.readAsStringSync(), content);
    final line = formatBinstubSdkCheckResult(result).single;
    expect(line, allOf(contains('fdb was activated with Dart 3.13.5'), contains('FDB_NO_BINSTUB_REPAIR=1')));
  });

  test('script not under global_packages/fdb → no-op', () {
    writeSnapshot('fdb', '3.12.2');
    final content = _shapeIfFi(pubCache, 'fdb', '3.13.5');
    final f = writeBinstub('fdb', content);

    for (final script in [
      '/some/repo/.dart_tool/pub/bin/fdb/fdb.dart-3.12.2.snapshot',
      '/some/repo/bin/fdb.dart',
      '$pubCache/global_packages/fdbx/bin/fdb.dart-3.12.2.snapshot',
      '',
    ]) {
      expect(checkBinstubSdk(input(script: script)), isA<BinstubSdkCheckNoOp>(), reason: script);
    }
    expect(f.readAsStringSync(), content);
  });

  test('Windows → no-op', () {
    writeSnapshot('fdb', '3.12.2');
    writeBinstub('fdb', _shapeIfFi(pubCache, 'fdb', '3.13.5'));
    expect(checkBinstubSdk(input(isWindows: true)), isA<BinstubSdkCheckNoOp>());
  });

  test('binstub not belonging to fdb is left untouched', () {
    writeSnapshot('fdb', '3.12.2');
    final content = _shapeIfFi(pubCache, 'fdb', '3.13.5', package: 'other');
    final f = writeBinstub('fdb', content);

    expect(checkBinstubSdk(input()), isA<BinstubSdkCheckNoOp>());
    expect(f.readAsStringSync(), content);
  });

  test('symlinked binstub → target rewritten, link kept', () {
    writeSnapshot('fdb', '3.12.2');
    final real = File('${tmp.path}/real_fdb')..writeAsStringSync(_shapeIfFi(pubCache, 'fdb', '3.13.5'));
    final link = Link('$pubCache/bin/fdb')..createSync(real.path);

    expect(checkBinstubSdk(input()), isA<BinstubSdkCheckRepaired>());
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(real.readAsStringSync(), contains('fdb.dart-3.12.2.snapshot'));
  }, testOn: '!windows');
}
