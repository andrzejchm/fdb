import 'dart:convert';

import 'package:fdb_helper/src/handlers/lifecycle_handler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _callHandler() async {
  final response = await handleLifecycle('ext.fdb.lifecycle', const {});
  return jsonDecode(response.result!) as Map<String, dynamic>;
}

void main() {
  testWidgets('reports resumed when the app is in the foreground', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(await _callHandler(), {'status': 'Success', 'lifecycleState': 'resumed'});
  });

  testWidgets('reports paused when another app covers this one', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    expect(await _callHandler(), {'status': 'Success', 'lifecycleState': 'paused'});
  });
}
