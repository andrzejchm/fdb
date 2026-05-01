import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Notification;
import 'package:push/push.dart';

abstract class NotificationClient {
  Future<String> getPermissionStatus();

  Future<String> requestPermission();

  Future<String?> getToken();

  Future<Map<String, Object?>?> getLaunchPayload();

  VoidCallback addOnForegroundMessage(void Function(RemotePushEvent event) onEvent);

  VoidCallback addOnBackgroundMessage(void Function(RemotePushEvent event) onEvent);

  VoidCallback addOnNotificationTap(void Function(Map<String, Object?> payload) onTap);
}

class PushNotificationClient implements NotificationClient {
  const PushNotificationClient();

  @override
  Future<String> getPermissionStatus() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final settings = await Push.instance.getNotificationSettings();
      return settings.authorizationStatus.toString().split('.').last;
    }

    if (Platform.isAndroid) {
      final enabled = await Push.instance.areNotificationsEnabled();
      return enabled ? 'granted' : 'denied';
    }

    return 'unsupported';
  }

  @override
  Future<String> requestPermission() async {
    final granted = await Push.instance.requestPermission();
    if (Platform.isIOS || Platform.isMacOS) {
      return getPermissionStatus();
    }
    return granted ? 'granted' : 'denied';
  }

  @override
  Future<String?> getToken() {
    return Push.instance.token;
  }

  @override
  Future<Map<String, Object?>?> getLaunchPayload() async {
    final payload = await Push.instance.notificationTapWhichLaunchedAppFromTerminated;
    return _normalizePayload(payload);
  }

  @override
  VoidCallback addOnForegroundMessage(void Function(RemotePushEvent event) onEvent) {
    return Push.instance.addOnMessage((message) {
      onEvent(RemotePushEvent.fromRemoteMessage(source: 'foreground', message: message));
    });
  }

  @override
  VoidCallback addOnBackgroundMessage(void Function(RemotePushEvent event) onEvent) {
    return Push.instance.addOnBackgroundMessage((message) {
      onEvent(RemotePushEvent.fromRemoteMessage(source: 'background', message: message));
    });
  }

  @override
  VoidCallback addOnNotificationTap(void Function(Map<String, Object?> payload) onTap) {
    return Push.instance.addOnNotificationTap((payload) {
      onTap(_normalizePayload(payload) ?? const {});
    });
  }

  Map<String, Object?>? _normalizePayload(Map<String?, Object?>? payload) {
    if (payload == null) {
      return null;
    }

    return payload.map((key, value) => MapEntry(key ?? 'null', _normalizeValue(value)));
  }

  Object? _normalizeValue(Object? value) {
    if (value is Map) {
      return value.map((key, entryValue) => MapEntry(key.toString(), _normalizeValue(entryValue)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }
}

class RemotePushEvent {
  const RemotePushEvent({
    required this.source,
    required this.title,
    required this.body,
    required this.payload,
    required this.deeplink,
  });

  factory RemotePushEvent.fromRemoteMessage({
    required String source,
    required RemoteMessage message,
  }) {
    final payload = (message.data ?? const <String?, Object?>{}).map(
      (key, value) => MapEntry(key ?? 'null', _normalizeValue(value)),
    );
    return RemotePushEvent(
      source: source,
      title: message.notification?.title ?? '',
      body: message.notification?.body ?? '',
      payload: payload,
      deeplink: extractDeeplink(payload),
    );
  }

  final String source;
  final String title;
  final String body;
  final Map<String, Object?> payload;
  final String? deeplink;

  String get formattedPayload {
    if (payload.isEmpty) {
      return '{}';
    }

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}

class NotificationTapEvent {
  const NotificationTapEvent({required this.source, required this.payload, required this.deeplink});

  final String source;
  final Map<String, Object?> payload;
  final String? deeplink;

  String get formattedPayload {
    if (payload.isEmpty) {
      return '{}';
    }

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}

Object? _normalizeValue(Object? value) {
  if (value is Map) {
    return value.map((key, entryValue) => MapEntry(key.toString(), _normalizeValue(entryValue)));
  }
  if (value is List) {
    return value.map(_normalizeValue).toList(growable: false);
  }
  return value;
}

String? extractDeeplink(Map<String, Object?> payload) {
  const prioritizedKeys = ['deeplink', 'deepLink', 'url', 'URL', 'link'];

  for (final key in prioritizedKeys) {
    final value = payload[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }

  for (final value in payload.values) {
    if (value is String && _looksLikeUrl(value)) {
      return value;
    }
    if (value is Map<String, Object?>) {
      final nested = extractDeeplink(value);
      if (nested != null) {
        return nested;
      }
    }
    if (value is Map) {
      final nested = extractDeeplink(value.map((key, entryValue) => MapEntry(key.toString(), entryValue)));
      if (nested != null) {
        return nested;
      }
    }
  }

  return null;
}

bool _looksLikeUrl(String value) {
  return value.contains('://') || value.startsWith('/');
}

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key, NotificationClient? client})
    : client = client ?? const PushNotificationClient();

  final NotificationClient client;

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> with WidgetsBindingObserver {
  VoidCallback? _unsubscribeForeground;
  VoidCallback? _unsubscribeBackground;
  VoidCallback? _unsubscribeTap;
  String _permissionStatus = 'unknown';
  String? _token;
  RemotePushEvent? _lastForeground;
  RemotePushEvent? _lastBackground;
  NotificationTapEvent? _launchTap;
  NotificationTapEvent? _lastTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unsubscribeForeground = widget.client.addOnForegroundMessage(_handleForegroundMessage);
    _unsubscribeBackground = widget.client.addOnBackgroundMessage(_handleBackgroundMessage);
    _unsubscribeTap = widget.client.addOnNotificationTap(_handleTapPayload);
    unawaited(_loadInitialState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeForeground?.call();
    _unsubscribeBackground?.call();
    _unsubscribeTap?.call();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionStatus());
    }
  }

  Future<void> _loadInitialState() async {
    final launchPayload = await widget.client.getLaunchPayload();
    final status = await widget.client.getPermissionStatus();
    final token = await widget.client.getToken();
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionStatus = status;
      _token = token;
      if (launchPayload != null) {
        _launchTap = NotificationTapEvent(
          source: 'launch',
          payload: launchPayload,
          deeplink: extractDeeplink(launchPayload),
        );
      }
    });
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await widget.client.getPermissionStatus();
    final token = await widget.client.getToken();
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionStatus = status;
      _token = token;
    });
  }

  Future<void> _requestPermission() async {
    final status = await widget.client.requestPermission();
    final token = await widget.client.getToken();
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionStatus = status;
      _token = token;
    });
  }

  void _handleForegroundMessage(RemotePushEvent event) {
    if (!mounted) {
      return;
    }
    setState(() => _lastForeground = event);
  }

  void _handleBackgroundMessage(RemotePushEvent event) {
    if (!mounted) {
      return;
    }
    setState(() => _lastBackground = event);
  }

  void _handleTapPayload(Map<String, Object?> payload) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastTap = NotificationTapEvent(source: 'tap', payload: payload, deeplink: extractDeeplink(payload));
    });
  }

  void _clearEvents() {
    setState(() {
      _lastForeground = null;
      _lastBackground = null;
      _launchTap = null;
      _lastTap = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remote Push Receipt', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Status: $_permissionStatus', key: const Key('notification_permission_status')),
                  const SizedBox(height: 4),
                  Text('Token: ${_token ?? '—'}', key: const Key('notification_token')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        key: const Key('request_notification_permission'),
                        onPressed: _requestPermission,
                        child: const Text('Request notification permission'),
                      ),
                      ElevatedButton(
                        key: const Key('refresh_notification_permission'),
                        onPressed: _refreshPermissionStatus,
                        child: const Text('Refresh status'),
                      ),
                      OutlinedButton(
                        key: const Key('clear_notification_events'),
                        onPressed: _clearEvents,
                        child: const Text('Clear events'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _RemotePushEventCard(title: 'Last foreground push', keyName: 'foreground', event: _lastForeground),
          const SizedBox(height: 16),
          _RemotePushEventCard(title: 'Last background push', keyName: 'background', event: _lastBackground),
          const SizedBox(height: 16),
          _NotificationTapEventCard(title: 'Launch-from-notification payload', keyName: 'launch', event: _launchTap),
          const SizedBox(height: 16),
          _NotificationTapEventCard(title: 'Last tapped notification payload', keyName: 'tap', event: _lastTap),
        ],
      ),
    );
  }
}

class _RemotePushEventCard extends StatelessWidget {
  const _RemotePushEventCard({required this.title, required this.keyName, required this.event});

  final String title;
  final String keyName;
  final RemotePushEvent? event;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: event == null
            ? Text('No $title yet.', key: Key('${keyName}_notification_empty'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Source: ${event.source}', key: Key('${keyName}_notification_source')),
                  const SizedBox(height: 4),
                  Text('Title: ${event.title.isEmpty ? '—' : event.title}', key: Key('${keyName}_notification_title')),
                  const SizedBox(height: 4),
                  Text('Body: ${event.body.isEmpty ? '—' : event.body}', key: Key('${keyName}_notification_body')),
                  const SizedBox(height: 4),
                  Text('Deeplink: ${event.deeplink ?? '—'}', key: Key('${keyName}_notification_deeplink')),
                  const SizedBox(height: 12),
                  Text(
                    event.formattedPayload,
                    key: Key('${keyName}_notification_payload'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NotificationTapEventCard extends StatelessWidget {
  const _NotificationTapEventCard({required this.title, required this.keyName, required this.event});

  final String title;
  final String keyName;
  final NotificationTapEvent? event;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: event == null
            ? Text('No $title yet.', key: Key('${keyName}_notification_empty'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Source: ${event.source}', key: Key('${keyName}_notification_source')),
                  const SizedBox(height: 4),
                  Text('Deeplink: ${event.deeplink ?? '—'}', key: Key('${keyName}_notification_deeplink')),
                  const SizedBox(height: 12),
                  Text(
                    event.formattedPayload,
                    key: Key('${keyName}_notification_payload'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
      ),
    );
  }
}
