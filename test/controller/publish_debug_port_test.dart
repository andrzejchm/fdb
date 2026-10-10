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
    final pidLookup = Completer<int?>();

    final publish = publishDebugPort(
      'ws://127.0.0.1:1/ws',
      lookupAppPid: () => pidLookup.future,
      isCurrent: () => true,
    );

    // While the PID lookup is in flight, launch must not see the app as ready.
    await Future<void>.delayed(Duration.zero);
    expect(readVmUri(), isNull);
    expect(readAppPid(), isNull);

    pidLookup.complete(82633);
    await publish;

    expect(readAppPid(), 82633);
    expect(readVmUri(), 'ws://127.0.0.1:1/ws');
  });

  test('still writes the VM URI file when the PID lookup fails, and reports the error', () async {
    final errors = <Object>[];

    await publishDebugPort(
      'ws://127.0.0.1:1/ws',
      lookupAppPid: () async => throw const SocketException('refused'),
      isCurrent: () => true,
      onError: errors.add,
    );

    expect(errors.single, isA<SocketException>());
    expect(readAppPid(), isNull);
    expect(readVmUri(), 'ws://127.0.0.1:1/ws');
  });

  test('does not throw when writing the session files fails', () async {
    root.deleteSync(recursive: true);
    root.createSync();
    final errors = <Object>[];

    await publishDebugPort(
      'ws://127.0.0.1:1/ws',
      lookupAppPid: () async => 1234,
      isCurrent: () => true,
      onError: errors.add,
    );

    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<FileSystemException>()));
  });

  for (final pid in [-1, 0]) {
    test('treats VM pid $pid (DWDS on web reports -1) as unknown', () async {
      await publishDebugPort(
        'ws://127.0.0.1:1/ws',
        lookupAppPid: () async => pid,
        isCurrent: () => true,
      );

      expect(File(appPidFile).existsSync(), isFalse);
      expect(readVmUri(), 'ws://127.0.0.1:1/ws');
    });
  }

  test('a slow lookup for an older debugPort event does not overwrite a newer one', () async {
    var generation = 0;
    final oldLookup = Completer<int?>();

    final oldGeneration = ++generation;
    final oldPublish = publishDebugPort(
      'ws://127.0.0.1:1/old/ws',
      lookupAppPid: () => oldLookup.future,
      isCurrent: () => oldGeneration == generation,
    );

    final newGeneration = ++generation;
    await publishDebugPort(
      'ws://127.0.0.1:2/new/ws',
      lookupAppPid: () async => 2222,
      isCurrent: () => newGeneration == generation,
    );

    oldLookup.complete(1111);
    await oldPublish;

    expect(readAppPid(), 2222);
    expect(readVmUri(), 'ws://127.0.0.1:2/new/ws');
  });
}
