import 'dart:convert';

import 'package:fdb_helper/src/handlers/describe_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('marks only disabled interactive widgets with enabled: false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Enabled button')),
              const ElevatedButton(onPressed: null, child: Text('Disabled button')),
              IconButton(key: const ValueKey('icon_on'), onPressed: () {}, icon: const Icon(Icons.add)),
              const IconButton(key: ValueKey('icon_off'), onPressed: null, icon: Icon(Icons.add)),
              Switch(key: const ValueKey('switch_on'), value: true, onChanged: (_) {}),
              const Switch(key: ValueKey('switch_off'), value: true, onChanged: null),
              const Checkbox(key: ValueKey('checkbox_off'), value: true, onChanged: null),
              const TextField(key: ValueKey('field_on')),
              const TextField(key: ValueKey('field_off'), enabled: false),
              ListTile(title: const Text('Enabled tile'), onTap: () {}),
              ListTile(title: const Text('Disabled tile'), enabled: false, onTap: () {}),
              GestureDetector(key: const ValueKey('detector_on'), onTap: () {}, child: const Text('Detector')),
            ],
          ),
        ),
      ),
    );

    final response = await handleDescribe('ext.fdb.describe', {});
    final interactive = (jsonDecode(response.result!)['interactive'] as List).cast<Map<String, dynamic>>();
    final enabledByLabel = {
      for (final entry in interactive) entry['key'] ?? entry['text']: entry['enabled'],
    };

    expect(enabledByLabel, {
      'Enabled button': null,
      'Disabled button': false,
      'icon_on': null,
      'icon_off': false,
      'switch_on': null,
      'switch_off': false,
      'checkbox_off': false,
      'field_on': null,
      'field_off': false,
      'Enabled tile': null,
      'Disabled tile': false,
      'detector_on': null,
    });
  });
}
