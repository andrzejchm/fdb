import 'dart:convert';

import 'package:fdb_helper/src/handlers/double_tap_handler.dart';
import 'package:fdb_helper/src/handlers/tap_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A custom button that owns its gesture handling, like a design-system button.
/// Not in fdb's closed list of interactive widget types.
class CustomButton extends StatefulWidget {
  const CustomButton({super.key, required this.onPressed});

  /// Null disables the button, like most design-system buttons.
  final VoidCallback? onPressed;

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

  group('a covered button', () {
    late _Taps taps;
    setUp(() => taps = _Taps());

    testWidgets('under a modal bottom sheet fails and taps nothing', (tester) async {
      await tester.pumpWidget(_screen(taps));
      showModalBottomSheet<void>(
        context: tester.element(find.byKey(const ValueKey('submit'))),
        builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
      );
      await tester.pumpAndSettle();

      final error = await _tapError(tester, {'key': 'submit'});
      await tester.pumpAndSettle();

      expect(error, contains('ModalBarrier'));
      expect(taps.all, (button: 0, screen: 0, overlay: 0));
      expect(find.text('Sheet'), findsOneWidget, reason: 'the barrier was tapped and dismissed the sheet');
    });

    for (final selector in [
      {'key': 'submit'},
      {'text': 'Submit'},
    ]) {
      testWidgets('under a full-screen opaque GestureDetector fails and taps nothing ($selector)', (tester) async {
        await tester.pumpWidget(_screen(taps, coverWithDetector: true));

        final error = await _tapError(tester, selector);

        expect(error, contains('covered by GestureDetector'));
        expect(taps.all, (button: 0, screen: 0, overlay: 0));
      });
    }
  });

  testWidgets('--text on a Text inside an ElevatedButton taps the button inside the text', (tester) async {
    final taps = _Taps();
    await tester.pumpWidget(_screen(taps));

    final (:type, :point) = await _tap(tester, {'text': 'Submit'});

    expect(type, isNot('Text'));
    expect(tester.getRect(find.text('Submit')).contains(point), isTrue);
    expect(taps.all, (button: 1, screen: 0, overlay: 0));
  });

  group('a disabled target', () {
    for (final (name, handler) in [
      ('tap', (Map<String, String> p) => handleTap('ext.fdb.tap', p)),
      ('long-press', (Map<String, String> p) => handleTap('ext.fdb.longPress', {...p, 'duration': '600'})),
      ('double-tap', (Map<String, String> p) => handleDoubleTap('ext.fdb.doubleTap', p)),
    ]) {
      testWidgets('ElevatedButton fails without tapping ($name)', (tester) async {
        final taps = _Taps();
        await tester.pumpWidget(_screen(taps, enabled: false));

        final response = await tester.runAsync(() => handler({'text': 'Submit'}));
        final result = jsonDecode(response!.result ?? response.errorDetail!) as Map<String, dynamic>;

        expect(result['error'], 'ElevatedButton is disabled', reason: '$result');
        expect(taps.all, (button: 0, screen: 0, overlay: 0));
      });
    }

    testWidgets('custom button whose detector has no onTap fails without tapping', (tester) async {
      var screenTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            onTap: () => screenTaps++,
            child: const Center(child: CustomButton(key: ValueKey('send_button'), onPressed: null)),
          ),
        ),
      );

      expect(await _tapError(tester, {'key': 'send_button'}), 'CustomButton is disabled');
      expect(screenTaps, 0);
    });

    testWidgets('is tapped exactly once after it becomes enabled', (tester) async {
      final enabled = ValueNotifier(false);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ValueListenableBuilder(
              valueListenable: enabled,
              builder: (_, isEnabled, __) => ElevatedButton(
                key: const ValueKey('send'),
                onPressed: isEnabled ? () => taps++ : null,
                child: const Text('Send'),
              ),
            ),
          ),
        ),
      );

      expect(await _tapError(tester, {'key': 'send'}), 'ElevatedButton is disabled');
      enabled.value = true;
      await tester.pump();
      final (:type, point: _) = await _tapKey(tester, 'send');

      expect(type, 'ElevatedButton');
      expect(taps, 1);
    });
  });
}

class _Taps {
  int button = 0;
  int screen = 0;
  int overlay = 0;

  ({int button, int screen, int overlay}) get all => (button: button, screen: screen, overlay: overlay);
}

/// A keyed "Submit" button inside a screen-level GestureDetector (a keyboard
/// dismisser), optionally covered by a full-screen opaque GestureDetector.
Widget _screen(_Taps taps, {bool coverWithDetector = false, bool enabled = true}) => MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps.screen++,
          child: Stack(
            children: [
              Center(
                child: ElevatedButton(
                  key: const ValueKey('submit'),
                  onPressed: enabled ? () => taps.button++ : null,
                  child: const Text('Submit'),
                ),
              ),
              if (coverWithDetector)
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps.overlay++),
                ),
            ],
          ),
        ),
      ),
    );

Future<({String type, Offset point})> _tapKey(WidgetTester tester, String key) => _tap(tester, {'key': key});

Future<({String type, Offset point})> _tap(WidgetTester tester, Map<String, String> selector) async {
  final result = await _handleTap(tester, selector);
  expect(result['status'], 'Success', reason: '$result');
  return (type: result['widgetType'] as String, point: Offset(result['x'] as double, result['y'] as double));
}

Future<String> _tapError(WidgetTester tester, Map<String, String> selector) async {
  final result = await _handleTap(tester, selector);
  expect(result['error'], isA<String>(), reason: 'tapped $result');
  return result['error'] as String;
}

Future<Map<String, dynamic>> _handleTap(WidgetTester tester, Map<String, String> selector) async {
  final response = await tester.runAsync(() => handleTap('ext.fdb.tap', selector));
  return jsonDecode(response!.result ?? response.errorDetail!) as Map<String, dynamic>;
}
