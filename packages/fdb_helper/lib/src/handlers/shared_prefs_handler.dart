import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleSharedPrefs(
  String method,
  Map<String, String> params,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final action = params['action'] ?? '';

    switch (action) {
      case 'getAll':
        final keys = prefs.getKeys();
        final all = <String, dynamic>{};
        for (final key in keys) {
          all[key] = prefs.get(key);
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'status': 'Success', 'values': all}),
        );

      case 'get':
        final key = params['key'];
        if (key == null || key.isEmpty) {
          return errorResponse('missing key param');
        }
        final value = prefs.get(key);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'status': 'Success',
            'key': key,
            'value': value,
            'exists': value != null,
          }),
        );

      case 'set':
        final key = params['key'];
        final raw = params['value'];
        final type = params['type'] ?? 'string';
        if (key == null || key.isEmpty) {
          return errorResponse('missing key param');
        }
        if (raw == null) return errorResponse('missing value param');
        switch (type) {
          case 'bool':
            await prefs.setBool(key, raw == 'true');
          case 'int':
            final n = int.tryParse(raw);
            if (n == null) return errorResponse('invalid int: $raw');
            await prefs.setInt(key, n);
          case 'double':
            final d = double.tryParse(raw);
            if (d == null) return errorResponse('invalid double: $raw');
            await prefs.setDouble(key, d);
          default:
            await prefs.setString(key, raw);
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'status': 'Success', 'key': key, 'value': raw}),
        );

      case 'remove':
        final key = params['key'];
        if (key == null || key.isEmpty) {
          return errorResponse('missing key param');
        }
        await prefs.remove(key);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'status': 'Success', 'key': key}),
        );

      case 'clear':
        await prefs.clear();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'status': 'Success'}),
        );

      default:
        return errorResponse(
          'unknown action: $action. '
          'Use get | getAll | set | remove | clear',
        );
    }
  } catch (e) {
    return errorResponse('sharedPrefs failed: $e');
  }
}
