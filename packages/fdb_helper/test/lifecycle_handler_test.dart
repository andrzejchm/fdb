import 'dart:convert';

import 'package:fdb_helper/src/handlers/lifecycle_handler.dart';
import 'package:fdb_helper/src/version.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _callHandler() async {
  final response = await handleLifecycle('ext.fdb.lifecycle', const {});
  return jsonDecode(response.result!) as Map<String, dynamic>;
}

void main() {
  testWidgets('reports the view device pixel ratio', (tester) async {
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.resetDevicePixelRatio);

    expect((await _callHandler())['devicePixelRatio'], 3.5);
  });

  testWidgets('reports resumed when the app is in the foreground', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(await _callHandler(), {
      'status': 'Success',
      'lifecycleState': 'resumed',
      'fdbHelperVersion': fdbHelperVersion,
      'devicePixelRatio': tester.view.devicePixelRatio,
    });
  });

  testWidgets('reports paused when another app covers this one', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    expect(await _callHandler(), {
      'status': 'Success',
      'lifecycleState': 'paused',
      'fdbHelperVersion': fdbHelperVersion,
      'devicePixelRatio': tester.view.devicePixelRatio,
    });
  });
}
