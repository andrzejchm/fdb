import 'dart:convert';
import 'dart:io';

import 'package:fdb/src/controller/session.dart';
import 'package:fdb/src/controller/vm_service/vm_service.dart';
import 'package:test/test.dart';

void main() {
  group('VM service getVM parsing', () {
    test('extracts VM process fields and isolate IDs', () {
      final vm = VM.fromResponse({
        'jsonrpc': '2.0',
        'id': '1',
        'result': {
          'name': 'example_test_app',
          'pid': 12345,
          'isolates': [
            {'id': 'isolates/1'},
            {'id': 'isolates/2'},
            {'name': 'missing id'},
          ],
        },
      });

      expect(vm, isNotNull);
      expect(vm!.name, 'example_test_app');
      expect(vm.pid, 12345);
      expect(vm.isolates, ['isolates/1', 'isolates/2']);
    });

    test('returns null for getVM errors', () {
      final vm = VM.fromResponse({
        'jsonrpc': '2.0',
        'id': '1',
        'error': {'message': 'failed'},
      });

      expect(vm, isNull);
    });
  });

  group('VM service client wrapper', () {
    test('calls methods through package:vm_service and returns normalized payloads', () async {
      final server = await _startVmServiceServer((request) {
        expect(request['method'], 'ext.fdb.example');
        expect(request['params'], {'value': 'abc'});
        return {
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': {
            'type': '_extensionType',
            'method': 'ext.fdb.example',
            'value': 42,
          },
        };
      });
      addTearDown(server.close);
      _useVmServiceServer(server);

      final response = await callVmServiceMethod(
        'ext.fdb.example',
        params: {'value': 'abc'},
      );

      expect(response, {'value': 42});
    });

    test('decodes VM service RPC error details into normalized fields', () async {
      final server = await _startVmServiceServer((request) {
        return {
          'jsonrpc': '2.0',
          'id': request['id'],
          'error': {
            'code': -32000,
            'message': 'Server error',
            'data': {'details': '{"error":"failed"}'},
          },
        };
      });
      addTearDown(server.close);
      _useVmServiceServer(server);

      final response = await callVmServiceMethod('ext.fdb.example');

      expect(response, {
        'error': 'failed',
        'errorCode': -32000,
        'errorMessage': 'Server error',
        'errorDetails': '{"error":"failed"}',
      });
    });
  });

  group('typed VM service result parsing', () {
    test('fdb widget action results extract fields from extension payload maps', () {
      final result = FdbTapCommandResponse.fromResponse({
        'type': '_extensionType',
        'method': 'ext.fdb.tap',
        'status': 'Success',
        'widgetType': 'ElevatedButton',
        'x': 12.5,
        'y': 24.0,
        'warning': 'covered',
      });

      expect(result.isSuccess, isTrue);
      expect(result.widgetType, 'ElevatedButton');
      expect(result.x, 12.5);
      expect(result.y, 24.0);
      expect(result.warning, 'covered');
    });

    test('extension errors are decoded into typed result fields', () {
      final result = FdbBackCommandResponse.fromResponse({
        'error': 'Navigator unavailable',
        'errorCode': -32000,
        'errorMessage': 'Server error',
        'errorDetails': '{"error":"Navigator unavailable"}',
      });

      expect(result.isSuccess, isFalse);
      expect(result.error, 'Navigator unavailable');
      expect(result.popped, isNull);
    });

    test('flutter inspector result extracts decoded widget tree', () {
      final result = FlutterInspectorTreeCommandResponse.fromResponse({
        'result': '{"description":"MaterialApp","children":[]}',
        'type': '_extensionType',
      });

      expect(result.tree, {
        'description': 'MaterialApp',
        'children': <dynamic>[],
      });
    });

    test('flutter inspector result accepts direct widget tree maps', () {
      final result = FlutterInspectorTreeCommandResponse.fromResponse({
        'description': 'MaterialApp',
        'children': <dynamic>[],
      });

      expect(result.tree, {
        'description': 'MaterialApp',
        'children': <dynamic>[],
      });
    });

    test('flutter inspector result accepts tree maps under result', () {
      final result = FlutterInspectorTreeCommandResponse.fromResponse({
        'result': {
          'description': 'MaterialApp',
          'children': <dynamic>[],
        },
      });

      expect(result.tree, {
        'description': 'MaterialApp',
        'children': <dynamic>[],
      });
    });

    test('generic VM service call extracts result and error details', () {
      final success = VmServiceExtensionCallCommandResponse.fromResponse({
        'type': '_extensionType',
        'size': 42,
      });
      expect(success.extensionResult, {'size': 42});

      final failure = VmServiceExtensionCallCommandResponse.fromResponse({
        'error': 'boom',
        'errorCode': -32000,
        'errorMessage': 'Server error',
        'errorDetails': 'boom',
      });
      expect(failure.errorCode, -32000);
      expect(failure.errorMessage, 'Server error');
      expect(failure.errorDetails, 'boom');
    });

    test('fdb results extract fields from controller response maps', () {
      final clean = FdbCleanCommandResponse.fromResponse({
        'status': 'Success',
        'dirs': ['cache', 'documents'],
        'deletedEntries': 7,
      });

      expect(clean.isSuccess, isTrue);
      expect(clean.dirs, ['cache', 'documents']);
      expect(clean.deletedEntries, 7);

      final describe = FdbDescribeCommandResponse.fromResponse({
        'snapshot': {
          'route': '/',
          'interactive': <dynamic>[],
        },
      });

      expect(describe.snapshot, {
        'route': '/',
        'interactive': <dynamic>[],
      });
    });

    test('VM protocol results extract fields from controller response maps', () {
      final isolate = VmIsolateCommandResponse.fromResponse({
        'name': 'main',
        'extensionRPCs': ['ext.fdb.tap'],
      });
      expect(isolate.name, 'main');
      expect(isolate.extensionRPCs, ['ext.fdb.tap']);

      final memory = VmMemoryUsageCommandResponse.fromResponse({
        'heapUsage': 10,
        'externalUsage': 20,
        'heapCapacity': 30,
      });
      expect(memory.heapUsage, 10);
      expect(memory.externalUsage, 20);
      expect(memory.heapCapacity, 30);
    });
  });
}

Future<HttpServer> _startVmServiceServer(
  Map<String, dynamic> Function(Map<String, dynamic> request) respond,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.transform(WebSocketTransformer()).listen((socket) {
    socket.listen((data) {
      final request = jsonDecode(data as String) as Map<String, dynamic>;
      socket.add(jsonEncode(respond(request)));
    });
  });
  return server;
}

void _useVmServiceServer(HttpServer server) {
  final dir = Directory.systemTemp.createTempSync('fdb_vm_service_test_');
  addTearDown(() {
    initSessionDir(Directory.current.path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  initSessionDirFromPath(dir.path);
  ensureSessionDir();
  File(vmUriFile).writeAsStringSync(
    'ws://${InternetAddress.loopbackIPv4.address}:${server.port}/ws',
  );
}
