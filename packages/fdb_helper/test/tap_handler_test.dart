import 'dart:convert';

import 'package:fdb_helper/src/handlers/tap_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A custom button that owns its gesture handling, like a design-system button.
/// Not in fdb's closed list of interactive widget types.
class CustomButton extends StatefulWidget {
  const CustomButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  @override
  Widget build(BuildContext context) => FocusableActionDetector(
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Semantics(button: true, child: const Icon(Icons.send, size: 48)),
        ),
      );
}

void main() {
  testWidgets('--key on a custom button taps its own detector, not a screen-level GestureDetector', (tester) async {
    var buttonTaps = 0;
    var screenTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Screen-level detector, e.g. to dismiss the keyboard.
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => screenTaps++,
            child: Column(
              children: [
                const Expanded(child: Center(child: Text('Conversation'))),
                Align(
                  alignment: Alignment.centerRight,
                  child: CustomButton(key: const ValueKey('send_button'), onPressed: () => buttonTaps++),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final (:type, :point) = await _tapKey(tester, 'send_button');

    expect(type, 'CustomButton');
    expect(point, tester.getCenter(find.byKey(const ValueKey('send_button'))));
    expect((buttonTaps, screenTaps), (1, 0));
  });

  testWidgets('--key on a button whose centre is scrolled past the edge taps its visible part', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 580),
                ElevatedButton(key: const ValueKey('submit'), onPressed: () => taps++, child: const Text('Submit')),
              ],
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('submit')));
    expect(rect.center.dy, greaterThan(600));

    final (:type, :point) = await _tapKey(tester, 'submit');

    expect(type, 'ElevatedButton');
    expect(rect.contains(point) && point.dy < 600, isTrue, reason: '$point not in visible part of $rect');
    expect(taps, 1);
  });
}

Future<({String type, Offset point})> _tapKey(WidgetTester tester, String key) async {
  final response = await tester.runAsync(() => handleTap('ext.fdb.tap', {'key': key}));
  final result = jsonDecode(response!.result ?? response.errorDetail!) as Map<String, dynamic>;
  expect(result['status'], 'Success', reason: '$result');
  return (type: result['widgetType'] as String, point: Offset(result['x'] as double, result['y'] as double));
}
