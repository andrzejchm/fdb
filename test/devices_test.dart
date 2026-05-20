import 'dart:io';

import 'package:fdb/core/commands/devices/devices.dart';
import 'package:test/test.dart';

void main() {
  group('listDevices', () {
    test('uses project-local FVM flutter when available', () async {
      final root = await Directory.systemTemp.createTemp('fdb_devices_test_');
      addTearDown(() async {
        await root.delete(recursive: true);
      });

      final flutterBin = File('${root.path}/.fvm/flutter_sdk/bin/flutter')
        ..createSync(recursive: true);

      String? executable;
      List<String>? arguments;
      final result = await listDevices(
        (
          projectPath: root.path,
          processRunner: (command, args) async {
            executable = command;
            arguments = args;
            return ProcessResult(
              1,
              0,
              '[{"id":"device-1","name":"Phone","targetPlatform":"ios","emulator":true}]',
              '',
            );
          },
        ),
      );

      expect(executable, flutterBin.path);
      expect(arguments, ['devices', '--machine']);
      expect(result, isA<DevicesListed>());
    });
  });
}
