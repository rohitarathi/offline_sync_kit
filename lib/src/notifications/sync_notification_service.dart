import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wrapper around [FlutterLocalNotificationsPlugin] used by the sync engine.
class SyncNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialises the notification plugin and requests the Android permission.
  /// Call once during app startup.
  static Future<void> initialize({
    String androidIconName = '@mipmap/ic_launcher',
  }) async {
    if (_initialized) return;

    final android = AndroidInitializationSettings(androidIconName);
    await _plugin.initialize(InitializationSettings(android: android));

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Shows a simple notification with [title] and [body].
  static Future<void> show(
    String title,
    String body, {
    String channelId = 'offline_sync_kit',
    String channelName = 'Background Sync',
    String? subText,
  }) async {
    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
      subText: subText,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(android: details),
    );
  }

  /// Convenience method that shows a sync summary notification.
  static Future<void> showSyncSummary({
    required String entityLabel,
    required int successCount,
    required int failureCount,
  }) async {
    var body = '✅ $successCount synced successfully';
    if (failureCount > 0) {
      body += '\n❌ $failureCount failed';
    }
    await show('$entityLabel Sync Summary', body);
  }
}
