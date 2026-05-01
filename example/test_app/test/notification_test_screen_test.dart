import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/notification_test_screen.dart';

void main() {
  testWidgets('shows current notification permission status', (tester) async {
    final client = FakeNotificationClient(permissionStatus: 'authorized');

    await tester.pumpWidget(MaterialApp(home: NotificationTestScreen(client: client)));
    await tester.pump();

    expect(find.text('Status: authorized'), findsOneWidget);
  });

  testWidgets('renders foreground push details', (tester) async {
    final client = FakeNotificationClient(
      permissionStatus: 'authorized',
      foregroundEvent: const RemotePushEvent(
        source: 'foreground',
        title: 'Hello',
        body: 'World',
        payload: {'deeplink': 'fdbtest://notifications/foreground'},
        deeplink: 'fdbtest://notifications/foreground',
      ),
    );

    await tester.pumpWidget(MaterialApp(home: NotificationTestScreen(client: client)));
    await tester.pump();

    expect(find.text('Last foreground push'), findsOneWidget);
    expect(find.textContaining('Title: Hello'), findsOneWidget);
    expect(find.textContaining('Body: World'), findsOneWidget);
    expect(find.textContaining('Deeplink: fdbtest://notifications/foreground'), findsOneWidget);
  });

  testWidgets('renders launch tap payload', (tester) async {
    final client = FakeNotificationClient(
      permissionStatus: 'authorized',
      launchPayload: const {
        'deeplink': 'fdbtest://notifications/launch',
        'title': 'Launch title',
      },
    );

    await tester.pumpWidget(MaterialApp(home: NotificationTestScreen(client: client)));
    await tester.pump();

    expect(find.text('Launch-from-notification payload'), findsOneWidget);
    expect(find.textContaining('Deeplink: fdbtest://notifications/launch'), findsOneWidget);
    expect(find.textContaining('"title": "Launch title"'), findsOneWidget);
  });

  testWidgets('clears all event cards', (tester) async {
    final client = FakeNotificationClient(
      permissionStatus: 'authorized',
      foregroundEvent: const RemotePushEvent(
        source: 'foreground',
        title: 'Before clear',
        body: 'Body',
        payload: {'deeplink': 'fdbtest://notifications/foreground'},
        deeplink: 'fdbtest://notifications/foreground',
      ),
      launchPayload: const {'deeplink': 'fdbtest://notifications/launch'},
    );

    await tester.pumpWidget(MaterialApp(home: NotificationTestScreen(client: client)));
    await tester.pump();

    await tester.tap(find.byKey(const Key('clear_notification_events')));
    await tester.pump();

    expect(find.text('No Last foreground push yet.'), findsOneWidget);
    expect(find.text('No Launch-from-notification payload yet.'), findsOneWidget);
  });
}

class FakeNotificationClient implements NotificationClient {
  FakeNotificationClient({
    required this.permissionStatus,
    this.launchPayload,
    this.foregroundEvent,
    this.backgroundEvent,
    this.tapPayload,
  });

  String permissionStatus;
  Map<String, Object?>? launchPayload;
  RemotePushEvent? foregroundEvent;
  RemotePushEvent? backgroundEvent;
  Map<String, Object?>? tapPayload;
  String? token;

  @override
  VoidCallback addOnBackgroundMessage(void Function(RemotePushEvent event) onEvent) {
    if (backgroundEvent != null) {
      onEvent(backgroundEvent!);
    }
    return () {};
  }

  @override
  VoidCallback addOnForegroundMessage(void Function(RemotePushEvent event) onEvent) {
    if (foregroundEvent != null) {
      onEvent(foregroundEvent!);
    }
    return () {};
  }

  @override
  VoidCallback addOnNotificationTap(void Function(Map<String, Object?> payload) onTap) {
    if (tapPayload != null) {
      onTap(tapPayload!);
    }
    return () {};
  }

  @override
  Future<Map<String, Object?>?> getLaunchPayload() async => launchPayload;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<String> getPermissionStatus() async => permissionStatus;

  @override
  Future<String> requestPermission() async {
    permissionStatus = 'authorized';
    return permissionStatus;
  }
}
