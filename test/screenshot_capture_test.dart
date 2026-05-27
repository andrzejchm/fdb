import 'dart:io';

import 'package:fdb/core/commands/screenshot/screenshot.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  group('screenshotHostPid', () {
    test('prefers app pid over flutter tool pid', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      File(pidFile).writeAsStringSync('2222');
      File(appPidFile).writeAsStringSync('1111');

      expect(screenshotHostPid(), 1111);
    });

    test('falls back to flutter tool pid when app pid is absent', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      File(pidFile).writeAsStringSync('2222');

      expect(screenshotHostPid(), 2222);
    });
  });
}

Future<Directory> _createTempSessionRoot() async {
  final root = await Directory.systemTemp.createTemp('fdb_screenshot_test_');
  final session = Directory('${root.path}/.fdb');
  session.createSync(recursive: true);
  initSessionDirFromPath(session.path);
  return root;
}
