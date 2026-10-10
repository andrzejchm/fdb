import 'dart:async';
import 'dart:io';

import 'package:fdb/src/controller/controller.dart';
import 'package:fdb/src/controller/process_utils.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fdb_publish_debug_port_');
    final session = Directory('${root.path}/.fdb')..createSync();
    initSessionDirFromPath(session.path);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('writes the VM URI file only after the app PID is written', () async {
    final pidLookup = Completer<void>();

    final publish = publishDebugPort(
      'ws://127.0.0.1:1/ws',
      writeAppPid: () async {
        await pidLookup.future;
        File(appPidFile).writeAsStringSync('82633');
      },
    );

    // While the PID lookup is in flight, launch must not see the app as ready.
    await Future<void>.delayed(Duration.zero);
    expect(readVmUri(), isNull);

    pidLookup.complete();
    await publish;

    expect(readAppPid(), 82633);
    expect(readVmUri(), 'ws://127.0.0.1:1/ws');
  });

  test('still writes the VM URI file when the PID lookup fails', () async {
    await expectLater(
      publishDebugPort(
        'ws://127.0.0.1:1/ws',
        writeAppPid: () async => throw const SocketException('refused'),
      ),
      throwsA(isA<SocketException>()),
    );

    expect(readAppPid(), isNull);
    expect(readVmUri(), 'ws://127.0.0.1:1/ws');
  });
}
