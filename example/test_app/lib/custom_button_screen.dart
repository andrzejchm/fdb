import 'package:flutter/material.dart';

const customButtonRoute = '/custom-button-test';

/// Screen for `task test:tap-custom-button`: a keyed custom button that owns
/// its GestureDetector, inside a screen-level GestureDetector (the usual
/// keyboard-dismiss wrapper). `fdb tap --key custom_send_button` must hit the
/// button, not the centre of the outer detector.
///
/// Also for `task test:tap-covered-button`: the "Cover" action shows an opaque
/// overlay over the body. While it is shown, tapping the button must fail and
/// deliver no tap anywhere.
class CustomButtonTestScreen extends StatefulWidget {
  const CustomButtonTestScreen({super.key});

  @override
  State<CustomButtonTestScreen> createState() => _CustomButtonTestScreenState();
}

class _CustomButtonTestScreenState extends State<CustomButtonTestScreen> {
  int _buttonTaps = 0;
  int _screenTaps = 0;
  int _overlayTaps = 0;
  bool _covered = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Button Test'),
        actions: [
          TextButton(
            key: const Key('cover_toggle'),
            onPressed: () => setState(() => _covered = !_covered),
            child: Text(_covered ? 'Uncover' : 'Cover'),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _screenTaps++),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'button=$_buttonTaps screen=$_screenTaps',
                      key: const Key('custom_button_counter'),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CustomSendButton(
                      key: const Key('custom_send_button'),
                      onPressed: () => setState(() => _buttonTaps++),
                    ),
                  ),
                ),
              ],
            ),
            if (_covered)
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('cover_overlay'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _overlayTaps++),
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text('overlay=$_overlayTaps'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A design-system style button: not a Material/Cupertino button type, it
/// builds its own focus handling, GestureDetector and semantics.
class CustomSendButton extends StatefulWidget {
  const CustomSendButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<CustomSendButton> createState() => _CustomSendButtonState();
}

class _CustomSendButtonState extends State<CustomSendButton> {
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(button: true, child: const Icon(Icons.send, size: 40)),
      ),
    );
  }
}
