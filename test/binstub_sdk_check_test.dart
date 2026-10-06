import 'dart:io';

import 'package:fdb/cli/binstub_sdk_check_cli.dart';
import 'package:fdb/core/binstub_sdk_check.dart';
import 'package:test/test.dart';

/// Header and snapshot fast path shared by both launcher formats pub writes.
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
  late String root;
  late String pubCache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fdb_binstub_test_');
    root = tmp.resolveSymbolicLinksSync();
    pubCache = '$root/pub cache';
    Directory('$pubCache/bin').createSync(recursive: true);
    Directory('$pubCache/global_packages/fdb/bin').createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File writeExecutable(String path, String content) {
    final f = File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    if (!Platform.isWindows) Process.runSync('chmod', ['755', f.path]);
    return f;
  }

  File writeBinstub(String name, String content) => writeExecutable('$pubCache/bin/$name', content);

  BinstubSdkCheckResult check(String running, {String? script, bool repairEnabled = true, bool isWindows = false}) =>
      checkBinstubSdk((
        pubCacheDir: pubCache,
        runningDartVersion: running,
        scriptPath: script ?? '$pubCache/global_packages/fdb/bin/fdb.dart-$running.snapshot',
        repairEnabled: repairEnabled,
        isWindows: isWindows,
      ));

  test('mismatch → both launcher shapes replaced once, then stable across SDK switches', () {
    final fdb = writeBinstub('fdb', _shapeIfFi(pubCache, 'fdb', '3.13.4'));
    final controller = writeBinstub('fdb-controller', _shapeIfElse(pubCache, 'controller', '3.13.4'));

    final result = check('3.12.2') as BinstubSdkCheckRepaired;

    expect(result.failed, isEmpty);
    expect(result.binstubs, [fdb.path, controller.path]);
    final fdbAfter = fdb.readAsStringSync();
    final controllerAfter = controller.readAsStringSync();
    for (final (content, script) in [(fdbAfter, 'fdb'), (controllerAfter, 'controller')]) {
      expect(content, startsWith(_head(pubCache, script, '3.13.4', 'fdb').split('\nif ').first));
      expect(content, contains(launcherMarker));
      expect(content, contains('dart pub global run fdb:$script "\$@"'));
      expect(content, isNot(contains('.dart-3.')), reason: 'no hardcoded SDK version');
    }
    expect(Directory('$pubCache/bin').listSync().where((e) => e.path.contains('fdb-tmp')), isEmpty);
    if (!Platform.isWindows) {
      for (final f in [fdb, controller]) {
        expect(f.statSync().mode & 0x1ff, 0x1ed, reason: '${f.path} must stay 0755');
      }
    }
    expect(formatBinstubSdkCheckResult(result).single, contains('Replaced ${fdb.path} and ${controller.path}'));

    for (final running in ['3.13.4', '3.12.2', '3.13.4', '3.11.5']) {
      expect(check(running), isA<BinstubSdkCheckNoOp>(), reason: running);
      expect(fdb.readAsStringSync(), fdbAfter);
      expect(controller.readAsStringSync(), controllerAfter);
    }
  });

  test('matching launcher replaced when another SDK already built a snapshot (pub rewrote it)', () {
    File('$pubCache/global_packages/fdb/bin/fdb.dart-3.13.4.snapshot').writeAsStringSync('');
    final f = writeBinstub('fdb', _shapeIfFi(pubCache, 'fdb', '3.12.2'));

    expect((check('3.12.2') as BinstubSdkCheckRepaired).binstubs, [f.path]);
    expect(f.readAsStringSync(), contains(launcherMarker));
  });

  test('launcher left untouched when there is nothing to fix or fdb must not touch it', () {
    final cases = <String, (String, BinstubSdkCheckResult Function())>{
      'matching SDK': (_shapeIfFi(pubCache, 'fdb', '3.12.2'), () => check('3.12.2')),
      'other package': (_shapeIfFi(pubCache, 'fdb', '3.13.4', package: 'other'), () => check('3.12.2')),
      'opted out': (_shapeIfFi(pubCache, 'fdb', '3.13.4'), () => check('3.12.2', repairEnabled: false)),
      'Windows': (_shapeIfFi(pubCache, 'fdb', '3.13.4'), () => check('3.12.2', isWindows: true)),
      'path activation': (
        _shapeIfFi(pubCache, 'fdb', '3.13.4'),
        () => check('3.12.2', script: '/repo/.dart_tool/pub/bin/fdb/fdb.dart-3.12.2.snapshot'),
      ),
      'other global package': (
        _shapeIfFi(pubCache, 'fdb', '3.13.4'),
        () => check('3.12.2', script: '$pubCache/global_packages/fdbx/bin/fdb.dart-3.12.2.snapshot'),
      ),
    };
    for (final MapEntry(key: name, value: (content, run)) in cases.entries) {
      final f = writeBinstub('fdb', content);
      expect(run(), isA<BinstubSdkCheckNoOp>(), reason: name);
      expect(f.readAsStringSync(), content, reason: name);
    }
  });

  test('symlinked launcher → target replaced, link kept', () {
    final real = writeExecutable('$root/real_fdb', _shapeIfFi(pubCache, 'fdb', '3.13.4'));
    final link = Link('$pubCache/bin/fdb')..createSync(real.path);

    expect(check('3.12.2'), isA<BinstubSdkCheckRepaired>());
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(real.readAsStringSync(), contains(launcherMarker));
  }, testOn: '!windows');

  test('unwritable launcher dir → failure reported, launcher untouched', () {
    final content = _shapeIfFi(pubCache, 'fdb', '3.13.4');
    final f = writeBinstub('fdb', content);
    Process.runSync('chmod', ['555', '$pubCache/bin']);
    addTearDown(() => Process.runSync('chmod', ['755', '$pubCache/bin']));

    final result = check('3.12.2') as BinstubSdkCheckUnrepaired;

    expect(f.readAsStringSync(), content);
    expect(formatBinstubSdkCheckResult(result).single, allOf(contains('Could not replace'), contains(f.path)));
  }, testOn: '!windows');

  group('runtime launcher', () {
    late String launcher;

    setUp(() {
      writeBinstub('fdb', _shapeIfFi(pubCache, 'fdb', '3.13.4'));
      check('3.12.2');
      launcher = '$pubCache/bin/fdb';
    });

    /// Fake `dart`: runs a "snapshot" by exiting with the code stored in it,
    /// and echoes every invocation.
    const fakeDart = '#!/bin/sh\necho "dart \$*"\ncase \$1 in *.snapshot) exit "\$(cat "\$1")";; esac\n';

    void writeSnapshot(String version, int exitCode) =>
        File('$pubCache/global_packages/fdb/bin/fdb.dart-$version.snapshot').writeAsStringSync('$exitCode');

    /// Runs the launcher with only [binDir] (plus system dirs) on PATH.
    ProcessResult run(String binDir) => Process.runSync(
          'sh',
          [launcher, 'status', 'a b'],
          environment: {'PATH': '$binDir:/usr/bin:/bin'},
          includeParentEnvironment: false,
        );

    String snapshot(String version) => '$pubCache/global_packages/fdb/bin/fdb.dart-$version.snapshot';

    test('picks the snapshot for the SDK on PATH, for each SDK layout', () {
      // Dart SDK: bin/dart + version.
      writeExecutable('$root/dart-sdk/bin/dart', fakeDart);
      File('$root/dart-sdk/version').writeAsStringSync('3.11.5\n');
      // Flutter SDK: bin/dart wrapper + bin/cache/dart-sdk/version (root version file is Flutter's).
      writeExecutable('$root/flutter/bin/dart', fakeDart);
      File('$root/flutter/version').writeAsStringSync('3.47.5\n');
      File('$root/flutter/bin/cache/dart-sdk/version')
        ..createSync(recursive: true)
        ..writeAsStringSync('3.13.4');
      // Relative symlink chain into the Dart SDK, as Homebrew installs it.
      Directory('$root/brew/bin').createSync(recursive: true);
      Link('$root/brew/bin/dart').createSync('../../dart-sdk/bin/dart');
      for (final v in ['3.11.5', '3.13.4']) {
        writeSnapshot(v, 7);
      }

      for (final (bin, version) in [
        ('$root/dart-sdk/bin', '3.11.5'),
        ('$root/flutter/bin', '3.13.4'),
        ('$root/brew/bin', '3.11.5'),
      ]) {
        final r = run(bin);
        expect(r.stdout, 'dart ${snapshot(version)} status a b\n', reason: bin);
        expect(r.exitCode, 7, reason: bin);
      }
    });

    test('falls back to pub global run when the version or snapshot is unknown, or the VM rejects it', () {
      writeExecutable('$root/shim/dart', fakeDart); // Version-manager shim: no version file.
      writeExecutable('$root/dart-sdk/bin/dart', fakeDart);
      File('$root/dart-sdk/version').writeAsStringSync('3.12.2\n');

      const pub = 'dart pub global run fdb:fdb status a b\n';
      expect(run('$root/shim').stdout, pub);
      expect(run('$root/dart-sdk/bin').stdout, pub, reason: 'no snapshot yet');

      writeSnapshot('3.12.2', 253);
      expect(run('$root/dart-sdk/bin').stdout, 'dart ${snapshot('3.12.2')} status a b\n$pub');
    });
  }, testOn: '!windows');
}
