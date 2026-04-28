import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Screen that embeds a WebView (WKWebView on iOS/macOS, WebView on Android).
///
/// The WebView renders a simple HTML page with a button. Tapping the button
/// via the native platform view (not through Flutter's GestureBinding) changes
/// the page title to "TAPPED", which the test verifies via fdb describe.
///
/// Used to verify that `fdb tap --at x,y` reaches native platform views
/// that sit outside Flutter's render tree.
class NativeViewTestScreen extends StatefulWidget {
  const NativeViewTestScreen({super.key});

  @override
  State<NativeViewTestScreen> createState() => _NativeViewTestScreenState();
}

class _NativeViewTestScreenState extends State<NativeViewTestScreen> {
  late final WebViewController _controller;
  String _pageTitle = 'waiting';

  // Pure HTML — no custom URL scheme, no external links.
  // The button changes document.title to "TAPPED" on click, which the
  // Flutter side polls and surfaces via the status text widget.
  static const _html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>waiting</title>
  <style>
    body {
      margin: 0;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      height: 100vh;
      background: #f0f4f8;
      font-family: sans-serif;
    }
    button {
      padding: 24px 48px;
      font-size: 20px;
      background: #1976d2;
      color: white;
      border: none;
      border-radius: 8px;
      cursor: pointer;
    }
    p { margin-top: 16px; font-size: 16px; }
  </style>
</head>
<body>
  <button id="native_btn" onclick="this.textContent='TAPPED'; document.title='TAPPED'; document.getElementById('status').textContent='TAPPED'; return false;">
    Tap Me (Native)
  </button>
  <p id="status">not tapped</p>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            final title = await _controller.getTitle() ?? '';
            if (mounted) setState(() => _pageTitle = title);
          },
        ),
      )
      ..setOnConsoleMessage((_) {})
      ..addJavaScriptChannel(
        'FdbBridge',
        onMessageReceived: (msg) {
          if (mounted) setState(() => _pageTitle = msg.message);
        },
      )
      ..loadHtmlString(_html);

    // Poll the page title so state updates when the button is tapped
    Timer.periodic(const Duration(milliseconds: 200), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final title = await _controller.getTitle() ?? '';
      if (mounted && title != _pageTitle) {
        setState(() => _pageTitle = title);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Native View Test'),
      ),
      body: Column(
        children: [
          // Flutter-side status — readable by fdb describe
          Container(
            key: const Key('native_tap_status'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _pageTitle == 'TAPPED'
                ? Colors.green.shade100
                : Colors.grey.shade200,
            child: Text(
              'WebView title: $_pageTitle',
              key: const Key('native_tap_status_text'),
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          // The platform view WebView — the button inside is NOT a Flutter widget
          Expanded(
            child: WebViewWidget(
              key: const Key('native_webview'),
              controller: _controller,
            ),
          ),
        ],
      ),
    );
  }
}
